library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.numeric_std.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;
use surf.AxiLitePkg.all;

library axi_soc_ultra_plus_core;
use axi_soc_ultra_plus_core.AxiSocUltraPlusPkg.all;

library work;
use work.AppPkg.all;

entity EvrDbSd is
    generic(
        TPD_G              : time            := 1 ns;
        SYNTH_MODE_G       : string          := "inferred";
        SD_EN              : boolean         := true;
        SD_BUFF_ADDR_WIDTH : integer         := 11;  -- Allocated SD buffer size
        SD_START_K         : slv(7 downto 0) := x"1C";  -- K.28.0, but mrf-openevr has 28.2=0x5C???
        SD_END_K           : slv(7 downto 0) := x"3C";  -- K.28.1
        AXIL_BASE_ADDR_G   : slv(31 downto 0));
    port (
        clk       : in sl;
        rst       : in sl;
        data      : in slv(7 downto 0);
        dataValid : in sl;
        dataK     : in sl;

        -- Trigger input to trigger dump of most recent shared data via AXI
        -- stream interface
        extTrig : in sl;

        distrBus : out slv(7 downto 0);

        -- AXI-Stream Interface (axisClk domain)
        axisClk    : in  sl;
        axisRst    : in  sl;
        axisMaster : out AxiStreamMasterType;
        axisSlave  : in  AxiStreamSlaveType;

        -- AXI-Lite Interface (axilClk domain)
        axilClk         : in  sl;
        axilRst         : in  sl;
        axilWriteMaster : in  AxiLiteWriteMasterType;
        axilWriteSlave  : out AxiLiteWriteSlaveType;
        axilReadMaster  : in  AxiLiteReadMasterType;
        axilReadSlave   : out AxiLiteReadSlaveType
        );
end entity EvrDbSd;

architecture rtl of EvrDbSd is

    type StateType is (
        IDLE_S,
        RECEIVE_S);

    type DataRegType is record
        state       : StateType;
        alignDone   : sl;
        isSd        : sl;
        writeEn     : sl;
        recBytesCnt : slv(15 downto 0);
        sdData      : slv(7 downto 0);
        distrBus    : slv(7 downto 0);
        recDone     : sl;
    end record DataRegType;

    constant DATA_REG_INIT_C : DataRegType := (
        state       => IDLE_S,
        alignDone   => '0',
        isSd        => '0',
        writeEn     => '0',
        recBytesCnt => (others => '0'),
        sdData      => (others => '0'),
        distrBus    => (others => '0'),
        recDone     => '0'
        );

    type AxilRegType is record
        axilReadSlave  : AxiLiteReadSlaveType;
        axilWriteSlave : AxiLiteWriteSlaveType;
        stateReg       : slv(7 downto 0);
        softTrig       : sl;
        testReg        : slv(31 downto 0);
    end record AxilRegType;

    constant AXIL_REG_INIT_C : AxilRegType := (
        axilReadSlave  => AXI_LITE_READ_SLAVE_INIT_C,
        axilWriteSlave => AXI_LITE_WRITE_SLAVE_INIT_C,
        stateReg       => (others => '0'),
        softTrig       => '0',
        testReg        => (others => '1')
        );

    signal dataR   : DataRegType := DATA_REG_INIT_C;
    signal dataRin : DataRegType;

    signal axilR   : AxilRegType := AXIL_REG_INIT_C;
    signal axilRin : AxilRegType;

    signal readoutTrigAsync : sl;
    signal readoutTrigSync  : sl;

    constant SD_BUFF_LEN : integer := 2**SD_BUFF_ADDR_WIDTH;

    constant NUM_AXIL_MASTERS_C : natural := 2;
    constant FB_INDEX_C         : natural := 0;  -- Two slots used at this index and this index + 1
    constant REG_INDEX_C        : natural := 1;

    constant AXIL_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL_MASTERS_C-1 downto 0) := genAxiLiteConfig(NUM_AXIL_MASTERS_C, AXIL_BASE_ADDR_G, 16, 12);

    signal axilReadMasters  : AxiLiteReadMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
    signal axilReadSlaves   : AxiLiteReadSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0)  := (others => AXI_LITE_READ_SLAVE_EMPTY_DECERR_C);
    signal axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
    signal axilWriteSlaves  : AxiLiteWriteSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0) := (others => AXI_LITE_WRITE_SLAVE_EMPTY_DECERR_C);

begin


    U_XBAR : entity surf.AxiLiteCrossbar
        generic map (
            TPD_G              => TPD_G,
            NUM_SLAVE_SLOTS_G  => 1,
            NUM_MASTER_SLOTS_G => NUM_AXIL_MASTERS_C,
            MASTERS_CONFIG_G   => AXIL_CONFIG_C)
        port map (
            axiClk              => axilClk,
            axiClkRst           => axilRst,
            sAxiWriteMasters(0) => axilWriteMaster,
            sAxiWriteSlaves(0)  => axilWriteSlave,
            sAxiReadMasters(0)  => axilReadMaster,
            sAxiReadSlaves(0)   => axilReadSlave,
            mAxiWriteMasters    => axilWriteMasters,
            mAxiWriteSlaves     => axilWriteSlaves,
            mAxiReadMasters     => axilReadMasters,
            mAxiReadSlaves      => axilReadSlaves);


    -- Or the internal software trigger and external trigger
    readoutTrigAsync <= extTrig or axilR.softTrig;

    U_AxiStreamFrameBuffer : entity surf.AxiStreamFrameBuffer
        generic map(
            TPD_G               => TPD_G,
            SYNTH_MODE_G        => SYNTH_MODE_G,
            MEMORY_TYPE_G       => "block",
            COMMON_CLK_G        => false,
            DATA_BYTES_G        => 1,   -- 8 bit per transmission
            RAM_ADDR_WIDTH_G    => SD_BUFF_ADDR_WIDTH,  -- One bytes = 8 bit words but buff_len is in bytes
            SAFE_BUFFS_G        => true,
            -- AXI Stream Configurations
            FIFO_MEMORY_TYPE_G  => "block",
            FIFO_ADDR_WIDTH_G   => 9,   -- TODO: Adjust?
            GEN_SYNC_FIFO_G     => false,
            AXI_STREAM_CONFIG_G => DMA_AXIS_CONFIG_C
            )
        port map (
            -- Data to store in ring buffer (dataClk domain)
            dataClk         => clk,
            dataValid       => dataR.writeEn,
            dataValue       => dataR.sdData,  -- Data line shared between buffers, use write enable to only capture valid data
            dataFrameTxLast => dataR.recDone,
            -- Trigger for readout over axis
            getFrameTrig    => readoutTrigSync,
            -- AXI-Lite interface (axilClk domain)
            axilClk         => axilClk,
            axilRst         => axilRst,
            axilReadMaster  => axilReadMasters(FB_INDEX_C),
            axilReadSlave   => axilReadSlaves(FB_INDEX_C),
            axilWriteMaster => axilWriteMasters(FB_INDEX_C),
            axilWriteSlave  => axilWriteSlaves(FB_INDEX_C),
            -- AXI-Stream Interface (axisClk domain)
            axisClk         => axisClk,
            axisRst         => axisRst,
            axisMaster      => axisMaster,
            axisSlave       => axisSlave);

    U_SoftTrigSync : entity surf.SynchronizerOneShot
        generic map(
            TPD_G => TPD_G)
        port map(
            clk     => clk,
            rst     => rst,
            dataIn  => readoutTrigAsync,
            dataOut => readoutTrigSync);

    dataComb : process(dataR, dataValid, data, dataK)
        variable dataVar : slv(7 downto 0);
        variable v       : DataRegType;
    begin
        -- Latch the current value
        v := dataR;

        -- Reset strobes
        v.recDone := '0';
        v.writeEn := '0';               -- Default to no write

        if dataValid = '1' then         -- Do nothing if data invalid
            dataVar := data;

            -- State machine only required if SD turned on.
            -- SD_EN might as well be a register but if so one must ensure
            -- reset after writing to it to ensure re-align.
            if SD_EN then
                if dataR.alignDone = '1' then
                    v.isSd := not dataR.isSd;  -- Toggle
                end if;
                -- State machine
                case dataR.state is
                    when IDLE_S =>
                        -- Wait for start K. DB is not output until at least one
                        -- start K is received. This is required as otherwise we
                        -- do not know if the current data is SD or DB.
                        if dataK = '1' and data = SD_START_K then
                            -- It appears that the transmission following the
                            -- align K is always SD
                            v.isSd      := '1';
                            -- Should always be 1 after initial start K
                            -- received. Consider setting back to 0 if e.g.
                            -- checksums fail (indicating misalignment)?
                            v.alignDone := '1';

                            -- Preset counter
                            v.recBytesCnt := slv(to_unsigned(SD_BUFF_LEN, v.recBytesCnt'length));
                            -- Move to receive state
                            v.state       := RECEIVE_S;
                        end if;
                    when RECEIVE_S =>
                        -- Check for transmission end K or buffer full
                        if (dataK = '1' and data = SD_END_K) or (dataR.recBytesCnt = 0) then
                            -- Strobe receive done which also resets the buffer
                            -- that is queued for next recording
                            v.recDone := '1';
                            -- Move back to idle to wait for next start K
                            v.state   := IDLE_S;
                        -- Otherwise, if data is SD, record it into buffer
                        elsif v.isSd = '1' then
                            v.recBytesCnt := dataR.recBytesCnt - 1;  -- Decrement counter
                            v.sdData      := data;  -- Set data
                            v.writeEn     := '1';   -- Enable write to buffer
                        end if;
                end case;

                -- Data is either DB or SD but DB arrives also when there is no
                -- SD transmission ongoing. TODO: Maybe all is DB when there is
                -- no SD transmission ongoing??? A but at least from ILA debug
                -- it seems like every second two bytes are 0 unless
                -- transmission ongoing so probably not?
                if not (v.isSd = '1') then
                    v.distrBus := data;
                end if;
            else
                -- if SD disabled, all transmissions are DB and we don't have
                -- to care about alignement or states
                v.distrBus := data;
            end if;
        end if;

        -- Outputs
        distrBus <= dataR.distrBus;

        -- Register the variable for next clock cycle
        dataRin <= v;

    end process dataComb;

    dataSeq : process(clk, rst)
    begin
        if rst = '1' then
            dataR <= DATA_REG_INIT_C;
        elsif rising_edge(clk) then
            dataR <= dataRin after TPD_G;
        end if;
    end process dataSeq;


    axilComb : process(axilR, axilReadMasters(REG_INDEX_C), axilWriteMasters(REG_INDEX_C), axilRst, dataR.state)
        variable v      : AxilRegType;
        variable axilEp : AxiLiteEndpointType;
    begin
        -- Latch the current value
        v := axilR;

        -- Reset strobes
        v.softTrig := '0';

        ------------------------
        -- AXI-Lite Transactions
        ------------------------

        -- Determine the transaction type
        axiSlaveWaitTxn(axilEp, axilWriteMasters(REG_INDEX_C), axilReadMasters(REG_INDEX_C), v.axilWriteSlave, v.axilReadSlave);

        axiSlaveRegisterR(axilEp, x"0", 0, axilR.stateReg);
        axiSlaveRegister (axilEp, x"4", 0, v.softTrig);
        axiSlaveRegister (axilEp, x"8", 0, v.testReg);

        -- Close the transaction
        axiSlaveDefault(axilEp, v.axilWriteSlave, v.axilReadSlave, AXI_RESP_DECERR_C);

        ----------------------------------------------------------------------

        -- Update state register
        -- Surely I'll get away with this...
        v.stateReg := conv_std_logic_vector(StateType'pos(dataR.state), axilR.stateReg'length);

        -- Reset (synchronous)
        if (axilRst = '1') then
            v := AXIL_REG_INIT_C;
        end if;

        -- Register the variable for next clock cycle
        axilRin <= v;
    end process axilComb;

    axilSeq : process (axilClk) is
    begin
        if rising_edge(axilClk) then
            axilR <= axilRin after TPD_G;
        end if;
    end process axilSeq;

end architecture rtl;
