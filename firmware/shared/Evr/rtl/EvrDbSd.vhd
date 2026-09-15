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

-- Description:
-- Handle decoding for the 'distributed bus' (trigger signals distributed
-- every cycle) and 'shared data' (periodically transmitted data buffer).
-- The former is output as signals (width=8). The latter is stored in a
-- frame buffer which allows for the most recent version of the data buffer
-- to be provided on a AXI-Stream interface at any time (the buffer
-- implementation actually ensures that this is possible at *any time* without
-- any dead time, i.e. a transmission should never be missed).

-- Notes:
-- > There should be a 16 bit (split into lower and upper byte, i.e. two
--   transmissions) after the SD_END_K is received. However, the manual does not
--   mention what kind of checksum that would be. I guess one could try to infer
--   it from the data... TODO: Try that and if successful implement checksum
--   check. Currently the checksum is just ignored.

entity EvrDbSd is
    generic(
        TPD_G              : time            := 1 ns;
        SYNTH_MODE_G       : string          := "inferred";
        SD_EN_G            : boolean         := true;
        SD_BUFF_ADDR_WIDTH : positive        := 11;  -- Allocated SD buffer size
        SD_START_K         : slv(7 downto 0) := x"1C";  -- K.28.0, but mrf-openevr has 28.2=0x5C???
        SD_END_K           : slv(7 downto 0) := x"3C";  -- K.28.1
        CHECKS_EN_G        : boolean         := true;  -- Enable checksum check
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
        RECEIVE_S,
        CHECKS_S);

    type DataRegType is record
        state             : StateType;
        alignDone         : sl;
        isSd              : sl;
        writeEn           : sl;
        sdData            : slv(7 downto 0);
        distrBus          : slv(7 downto 0);
        seg               : slv(6 downto 0);
        segLatched        : sl;
        recDone           : sl;
        checksLoc         : slv(15 downto 0);  -- Local checksum
        checksRec         : slv(15 downto 0);  -- Received checksum
        checksRecByteStat : slv(1 downto 0);  -- Indicate if upper/lower byte received
        checksMismatch    : sl;  -- Indicates checksum mismatch. Sticky flag, must be cleared by user.
    end record DataRegType;

    constant DATA_REG_INIT_C : DataRegType := (
        state             => IDLE_S,
        alignDone         => '0',
        isSd              => '0',
        writeEn           => '0',
        sdData            => (others => '0'),
        distrBus          => (others => '0'),
        seg               => (others => '0'),
        segLatched        => '0',
        recDone           => '0',
        checksLoc         => (others => '1'),  -- Start value for checksum is all ones
        checksRec         => (others => '0'),
        checksRecByteStat => (others => '0'),
        checksMismatch    => '0');

    type AxilRegType is record
        axilReadSlave     : AxiLiteReadSlaveType;
        axilWriteSlave    : AxiLiteWriteSlaveType;
        stateReg          : slv(7 downto 0);
        softTrig          : sl;
        checksMismatchClr : sl;
    end record AxilRegType;

    constant AXIL_REG_INIT_C : AxilRegType := (
        axilReadSlave     => AXI_LITE_READ_SLAVE_INIT_C,
        axilWriteSlave    => AXI_LITE_WRITE_SLAVE_INIT_C,
        stateReg          => (others => '0'),
        softTrig          => '0',
        checksMismatchClr => '0');

    signal dataR   : DataRegType := DATA_REG_INIT_C;
    signal dataRin : DataRegType;

    signal axilR   : AxilRegType := AXIL_REG_INIT_C;
    signal axilRin : AxilRegType;

    signal dataFrameRxLast : sl;

    signal readoutTrigAsync : sl;
    signal readoutTrigSync  : sl;

    signal checksSyncIn  : slv(32 downto 0);
    signal checksSyncOut : slv(32 downto 0);

    signal checksRecSync      : slv(15 downto 0);
    signal checksLocSync      : slv(15 downto 0);
    signal checksMismatchSync : sl;

    signal checksMismatchClr     : sl;
    signal checksMismatchClrSync : sl;

    -- Fix to one byte per clock. Buffer technically supports more but the
    -- checksumming for now is only implemented for 1 byte per clock.
    constant SD_BUFF_DATA_BYTES_C : positive := 1;

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

    U_EvrSdBuffer : entity work.EvrSdBuffer
        generic map(
            TPD_G               => TPD_G,
            SYNTH_MODE_G        => SYNTH_MODE_G,
            MEMORY_TYPE_G       => "block",
            COMMON_CLK_G        => false,
            DATA_BYTES_G        => SD_BUFF_DATA_BYTES_C,
            RAM_ADDR_WIDTH_G    => SD_BUFF_ADDR_WIDTH,
            -- AXI-Stream Configurations
            FIFO_MEMORY_TYPE_G  => "block",
            FIFO_ADDR_WIDTH_G   => 9,   -- TODO: Adjust?
            GEN_SYNC_FIFO_G     => false,
            AXI_STREAM_CONFIG_G => DMA_AXIS_CONFIG_C
            )
        port map (
            -- Data to store in ring buffer (dataClk domain)
            dataClk         => clk,
            dataRst         => rst,
            dataValid       => dataR.writeEn,
            dataValue       => dataR.sdData,  -- Data line shared between buffers, use write enable to only capture valid data
            dataSegIdx      => dataR.seg,
            dataFrameTxLast => dataR.recDone,
            dataFrameRxLast => dataFrameRxLast,
            -- Trigger for readout over axis
            dataRdTrig      => readoutTrigSync,
            -- AXI-Lite interface (axilClk domain)
            axilClk         => axilClk,
            axilRst         => axilRst,
            axilReadMaster  => axilReadMasters(FB_INDEX_C),
            axilReadSlave   => axilReadSlaves(FB_INDEX_C),
            axilWriteMaster => axilWriteMasters(FB_INDEX_C),
            axilWriteSlave  => axilWriteSlaves(FB_INDEX_C),
            axilRdTrig      => '0',  -- Optional trigger signal synchronous to axilClk
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

    -- Synchronize checksum registers from data to axil process
    U_SyncVecChecks : entity surf.SynchronizerVector
        generic map (
            TPD_G   => TPD_G,
            WIDTH_G => 33)
        port map (
            clk     => axilClk,
            dataIn  => checksSyncIn,
            dataOut => checksSyncOut);

    checksSyncIn(15 downto 0)  <= dataR.checksRec;
    checksSyncIn(31 downto 16) <= dataR.checksLoc;
    checksSyncIn(32)           <= dataR.checksMismatch;
    checksRecSync              <= checksSyncOut(15 downto 0);
    checksLocSync              <= checksSyncOut(31 downto 16);
    checksMismatchSync         <= checksSyncOut(32);

    -- Synchronize checksum registers from data to axil process
    U_SyncChecksMismatchClr : entity surf.SynchronizerOneShot
        generic map (
            TPD_G => TPD_G)
        port map (
            clk     => clk,
            dataIn  => checksMismatchClr,
            dataOut => checksMismatchClrSync);

    dataComb : process(dataR, dataValid, data, dataK, dataFrameRxLast, checksMismatchClrSync)
        variable dataVar : slv(7 downto 0);
        variable v       : DataRegType;
    begin
        -- Latch the current value
        v := dataR;

        -- Reset strobes
        v.recDone := '0';
        v.writeEn := '0';               -- Default to no write

        -- Clear checksum mismatch flag if requested
        if checksMismatchClrSync = '1' then
            v.checksMismatch := '0';
        end if;

        if dataValid = '1' then         -- Do nothing if data invalid
            dataVar := data;

            -- State machine only required if SD turned on.
            -- SD_EN might as well be a register but if so one must ensure
            -- reset after writing to it to ensure re-align.
            if SD_EN_G then
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
                            -- align K is always DB. So set isSd to 0 for the 
                            -- next cycle.
                            v.isSd      := '0';
                            -- Should always be 1 after initial start K
                            -- received. Consider setting back to 0 if e.g.
                            -- checksums fail (indicating misalignment)?
                            v.alignDone := '1';

                            -- Reset the locally computed of the checksum
                            v.checksLoc := (others => '1');

                            -- Preset counter
                            -- Move to receive state
                            v.state := RECEIVE_S;
                        end if;
                    when RECEIVE_S =>
                        -- Check for transmission end K or buffer full.
                        if (dataK = '1' and data = SD_END_K) or (dataFrameRxLast = '1') then
                            if dataFrameRxLast = '0' then
                                -- Strobe receive done to let the buffer know we are done
                                -- but only if it not already knows (i.e. buffer full).
                                v.recDone := '1';
                            end if;

                            -- Reset segment latched flag
                            v.segLatched := '0';
                            if CHECKS_EN_G then
                                -- Receive and check the checksums
                                v.state := CHECKS_S;
                            else
                                -- Move back to idle to wait for next start K
                                v.state := IDLE_S;
                            end if;
                        -- Otherwise, if data is SD, record it into buffer.
                        -- There should be no K characters here per the protocol but
                        -- check that the flag is zero just in case...(?)
                        elsif (dataR.isSd = '1') and (dataK = '0') then
                            if dataR.segLatched = '0' then
                                -- First byte indicates the segment
                                -- TODO: I *think* the segment byte does not count into the number
                                -- of received bytes.
                                v.seg        := data(6 downto 0);
                                v.segLatched := '1';
                            else
                                v.sdData  := data;  -- Set data
                                v.writeEn := '1';   -- Enable write to buffer

                                -- Compute checksum if enabled
                                if CHECKS_EN_G then
                                    -- Subtract data (8 bit) from the checksum register (16 bit)
                                    v.checksLoc := v.checksLoc - data;
                                end if;
                            end if;
                        end if;
                    when CHECKS_S =>
                        -- TODO(?): Checksums will never work when the buffer is smaller than
                        -- the amount of received data. I guess we don't really care here...
                        if dataR.checksRecByteStat /= b"11" then
                            -- Receive the checksum
                            if dataR.isSd = '1' then
                                -- LSB comes first, MSB comes second
                                if dataR.checksRecByteStat(0) = '0' then
                                    v.checksRec(7 downto 0) := data;
                                    v.checksRecByteStat(0)  := '1';
                                elsif dataR.checksRecByteStat(1) = '0' then
                                    v.checksRec(15 downto 8) := data;
                                    v.checksRecByteStat(1)   := '1';
                                end if;
                            end if;
                        else
                            -- Check the checksum
                            if dataR.checksRec /= dataR.checksLoc then
                                -- Set checksum mismatch flag. This is a sticky flag which has
                                -- to be cleared by the user over the axil register interface.
                                v.checksMismatch := '1';
                            end if;
                            -- Reset MSB/LSB received flags
                            v.checksRecByteStat := (others => '0');
                            -- Move back to idle to wait for next start K
                            v.state             := IDLE_S;
                        end if;
                end case;

                -- Data is either DB or SD but DB arrives also when there is no
                -- SD transmission ongoing. TODO(?): Maybe all is DB when there
                -- is no SD transmission ongoing??? A but at least from ILA
                -- debug it seems like every second two bytes are 0 unless
                -- transmission ongoing so probably not.
                if not (dataR.isSd = '1') then
                    v.distrBus := data;
                end if;
            else
                -- If SD disabled, all transmissions are DB and we don't have
                -- to care about alignment or states
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


    axilComb : process(axilR, axilReadMasters(REG_INDEX_C), axilWriteMasters(REG_INDEX_C), axilRst,
                       dataR.state, checksRecSync, checksLocSync, checksMismatchSync)
        variable v      : AxilRegType;
        variable axilEp : AxiLiteEndpointType;
    begin
        -- Latch the current value
        v := axilR;

        -- Reset strobes
        v.softTrig          := '0';
        v.checksMismatchClr := '0';

        ------------------------
        -- AXI-Lite Transactions
        ------------------------

        -- Determine the transaction type
        axiSlaveWaitTxn(axilEp, axilWriteMasters(REG_INDEX_C), axilReadMasters(REG_INDEX_C), v.axilWriteSlave, v.axilReadSlave);

        axiSlaveRegisterR(axilEp, x"0", 0, axilR.stateReg);
        axiSlaveRegister (axilEp, x"4", 0, v.softTrig);
        axiSlaveRegisterR(axilEp, x"8", 0, checksRecSync);
        axiSlaveRegisterR(axilEp, x"8", 16, checksLocSync);
        axiSlaveRegisterR(axilEp, x"C", 0, checksMismatchSync);
        axiSlaveRegister (axilEp, x"C", 1, v.checksMismatchClr);

        -- Close the transaction
        axiSlaveDefault(axilEp, v.axilWriteSlave, v.axilReadSlave, AXI_RESP_DECERR_C);

        ----------------------------------------------------------------------

        -- Update state register
        -- Surely I'll get away with this...
        v.stateReg := conv_std_logic_vector(StateType'pos(dataR.state), axilR.stateReg'length);

        -- Outputs
        axilReadSlaves(REG_INDEX_C)  <= axilR.axilReadSlave;
        axilWriteSlaves(REG_INDEX_C) <= axilR.axilWriteSlave;
        checksMismatchClr            <= axilR.checksMismatchClr;

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
