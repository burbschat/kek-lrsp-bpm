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
        SD_EN              : boolean         := true;
        SD_BUFF_LEN        : integer         := 2048;  -- Allocated SD buffer length
        SD_BUFF_ADDR_WIDTH : integer         := 11;  -- Allocated SD buffer length
        SD_START_K         : slv(7 downto 0) := x"1C";  -- K.28.0, but mrf-openevr has 28.2=0x5C???
        SD_END_K           : slv(7 downto 0) := x"3C";  -- K.28.1
        TDEST_ROUTE_G      : slv(7 downto 0) := x"00";
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
        buffSel     : sl;
        writeEn     : sl;
        recBytesCnt : slv(15 downto 0);
        sdData      : slv(7 downto 0);
        distrBus    : slv(7 downto 0);
        recDoneStrb : sl;
    end record DataRegType;

    constant DATA_REG_INIT_C : DataRegType := (
        state       => IDLE_S,
        alignDone   => '0',
        isSd        => '0',
        buffSel     => '0',
        writeEn     => '0',
        recBytesCnt => (others => '0'),
        sdData      => (others => '0'),
        distrBus    => (others => '0'),
        recDoneStrb => '0'
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

    signal buffTrg     : slv(1 downto 0);
    signal buffSel     : sl;
    signal buffValid   : slv(1 downto 0);
    signal writeEn     : sl;
    signal sdData      : slv(7 downto 0);
    signal receiveDone : sl;
    signal buffRst     : slv(1 downto 0);

    signal readoutTrig : sl;
    signal softTrig    : sl;


    constant NUM_AXIS_MASTERS_C : natural := 2;

    constant NUM_AXIL_MASTERS_C : natural := 3;
    constant RING_INDEX_START_C : natural := 0;  -- Two slots used at this index and this index + 1
    constant REG_INDEX_C        : natural := 2;

    constant AXIL_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL_MASTERS_C-1 downto 0) := genAxiLiteConfig(NUM_AXIL_MASTERS_C, AXIL_BASE_ADDR_G, 16, 12);

    signal axilReadMasters  : AxiLiteReadMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
    signal axilReadSlaves   : AxiLiteReadSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0)  := (others => AXI_LITE_READ_SLAVE_EMPTY_DECERR_C);
    signal axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
    signal axilWriteSlaves  : AxiLiteWriteSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0) := (others => AXI_LITE_WRITE_SLAVE_EMPTY_DECERR_C);

    signal axisMasters : AxiStreamMasterArray(NUM_AXIS_MASTERS_C-1 downto 0);
    signal axisSlaves  : AxiStreamSlaveArray(NUM_AXIS_MASTERS_C-1 downto 0);

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
    readoutTrig <= extTrig or softTrig;

    -- Make buffer selection and trigger mutually exclusive
    buffValid(0) <= buffSel and writeEn;
    buffValid(1) <= not buffSel and writeEn;
    -- Read out the buffer that IS NOT currently used for writing!
    buffTrg(0)   <= not buffSel and readoutTrig;
    buffTrg(1)   <= buffSel and readoutTrig;
    -- Reset always the buffer that IS currently selected for writing!
    -- This does not actually zero out the buffer so if a transmission has less
    -- data than the buffer size and the transmission lengths vary one must keep
    -- track of the number of received bytes! TODO?
    buffRst(0)   <= buffSel and receiveDone;
    buffRst(1)   <= not buffSel and receiveDone;

    assert SD_BUFF_LEN = 2**SD_BUFF_ADDR_WIDTH report "Buffer 2**SD_BUFF_ADDR_WIDTH must equal SD_BUFF_LEN" severity failure;

    -- Those do not have to be ring buffers but the surf ring buffers come with
    -- axi stream readout which is convenient here.
    GEN_VEC : for i in 1 downto 0 generate
        U_AxiStreamRingBuffer : entity surf.AxiStreamRingBuffer
            generic map (
                TPD_G               => TPD_G,
                SYNTH_MODE_G        => "xpm",
                MEMORY_TYPE_G       => "block",
                COMMON_CLK_G        => false,
                DATA_BYTES_G        => 1,   -- 8 bit per transmission
                RAM_ADDR_WIDTH_G    => SD_BUFF_ADDR_WIDTH,  -- One bytes = 8 bit words but buff_len is in bytes
                -- AXI Stream Configurations
                FIFO_MEMORY_TYPE_G  => "block",
                FIFO_ADDR_WIDTH_G   => 9,   -- TODO: Adjust?
                GEN_SYNC_FIFO_G     => false,
                AXI_STREAM_CONFIG_G => DMA_AXIS_CONFIG_C)
            port map (
                -- Data to store in ring buffer (dataClk domain)
                dataClk         => clk,
                dataValid       => buffValid(i),
                dataValue       => sdData,  -- Data line shared between buffers, use write enable to only capture valid data
                dataRst         => buffRst(i),  -- Use to reset ring buffer pointers
                -- Trigger for readout over axis
                extTrig         => buffTrg(i),
                -- AXI-Lite interface (axilClk domain)
                axilClk         => axilClk,
                axilRst         => axilRst,
                axilReadMaster  => axilReadMasters(RING_INDEX_START_C + i),
                axilReadSlave   => axilReadSlaves(RING_INDEX_START_C + i),
                axilWriteMaster => axilWriteMasters(RING_INDEX_START_C + i),
                axilWriteSlave  => axilWriteSlaves(RING_INDEX_START_C + i),
                -- AXI-Stream Interface (axisClk domain)
                axisClk         => axisClk,
                axisRst         => axisRst,
                axisMaster      => axisMasters(i),
                axisSlave       => axisSlaves(i));
    end generate GEN_VEC;

    U_Mux : entity surf.AxiStreamMux
        generic map (
            TPD_G          => TPD_G,
            NUM_SLAVES_G   => NUM_AXIS_MASTERS_C,
            MODE_G         => "ROUTED",
            TDEST_ROUTES_G => (
                0          => TDEST_ROUTE_G,
                1          => TDEST_ROUTE_G),
            PIPE_STAGES_G  => 1)
        port map (
            -- Clock and reset
            axisClk      => axisClk,
            axisRst      => axisRst,
            -- Slaves
            sAxisMasters => axisMasters,
            sAxisSlaves  => axisSlaves,
            -- Master
            mAxisMaster  => axisMaster,
            mAxisSlave   => axisSlave);

    U_SoftTrigSync : entity surf.SynchronizerOneShot
        generic map(
            TPD_G => TPD_G)
        port map(
            clk     => clk,
            rst     => rst,
            dataIn  => axilR.softTrig,
            dataOut => softTrig);

    dataComb : process(dataR, dataValid, data, dataK)
        variable dataVar : slv(7 downto 0);
        variable v       : DataRegType;
    begin
        -- Latch the current value
        v := dataR;

        -- Reset strobes
        v.recDoneStrb := '0';

        if dataValid = '1' then         -- Do nothing if data invalid
            dataVar := data;

            v.writeEn := '0';           -- Default to no write

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
                            -- align K is always SD (TODO: Check!)
                            v.isSd      := '1';
                            -- Should always be 1 after initial start K
                            -- received. Consider setting back to 0 if e.g.
                            -- checksums fail (indicating misalignment)?
                            v.alignDone := '1';

                            -- Preset counter
                            v.recBytesCnt := x"07FF";  -- slv(to_unsigned(SD_BUFF_LEN, v.recBytesCnt'length));
                            -- Move to receive state
                            v.state       := RECEIVE_S;
                        end if;
                    when RECEIVE_S =>
                        -- Check for transmission end K or buffer full
                        if (dataK = '1' and data = SD_END_K) or (dataR.recBytesCnt = 0) then
                            -- Toggle selected buffer. Also toggles which
                            -- buffer is triggered for readout!
                            v.buffSel     := not dataR.buffSel;
                            -- Strobe receive done which also resets the buffer
                            -- that is queued for next recording
                            v.recDoneStrb := '1';
                            -- Move back to idle to wait for next start K
                            v.state       := IDLE_S;
                        -- Otherwise, if data is SD, record it into buffer
                        elsif v.isSd = '1' then
                            v.recBytesCnt := dataR.recBytesCnt - 1;  -- Decrement counter
                            v.sdData      := data;     -- Set data
                            v.writeEn     := '1';  -- Enable write to buffer
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
        distrBus    <= dataR.distrBus;
        buffSel     <= dataR.buffSel;
        receiveDone <= dataR.recDoneStrb;
        -- Write enable and data must be synchronous so include both in register
        writeEn     <= dataR.writeEn;
        sdData      <= dataR.sdData;

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
