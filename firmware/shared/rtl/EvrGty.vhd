library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;
use surf.AxiLitePkg.all;

library work;
use work.AppPkg.all;

library unisim;
use unisim.vcomponents.all;

-- Notes:
-- > Consider adding EVR Decoder as part of this entity and only expose event
--   code/shared bus + generic to enable/disable mirroring. Mirroring should be
--   handeled in this entity, not the decoder.
-- > Keep EVR Decoder as separate entity to allow use with other transceivers.
-- > Could not get the thing to work with external clock network. Perhaps that
--   was the issue. Now try with clock network in the IP core...

entity EvrGty is
    generic (
        TPD_G           : time    := 1 ns;
        STABLE_CLK_F_HZ : integer := 156250000;  -- Used to time resets

        AXIL_BASE_ADDR_G : slv(31 downto 0);
        AXIL_BASE_BOT_G  : natural range 1 to 32;

        ----------------------------------------------------------------------------------------------
        -- EVR Settings
        ----------------------------------------------------------------------------------------------
        TX_MIRROR_ENABLE_G : boolean := true
        );
    port (
        -- GT Clocking
        stableClk       : in  sl;       -- GT needs a stable clock to "boot up"
        stableRst       : in  sl;
        resetGt         : in  sl;
        gtRefClk        : in  sl;
        -- GT Serial IO
        evrGtTxP        : out sl;
        evrGtTxN        : out sl;
        evrGtRxP        : in  sl;
        evrGtRxN        : in  sl;
        -- Tx clocking
        evrTxResetAsync : in  sl;
        evrTxResetDone  : out sl;
        evrTxUsrClk     : out sl;  -- user clock = recovered clock (tx data sync. to this)
        -- evrTxMmcmLocked : in  sl;
        -- Rx clocking
        evrRxResetAsync : in  sl;
        evrRxResetDone  : out sl;
        evrRxUsrClk     : out sl;  -- user clock  = recovered clock (rx data sync. to this)
        -- evrRxMmcmLocked : in  sl;
        -- Transceiver control signals
        trxRequestLP    : out sl;       -- Request transceiver low power mode
        -- AXI-Lite DRP interface
        axilClk         : in  sl                     := '0';
        axilRst         : in  sl                     := '0';
        axilReadMaster  : in  AxiLiteReadMasterType  := AXI_LITE_READ_MASTER_INIT_C;
        axilReadSlave   : out AxiLiteReadSlaveType;
        axilWriteMaster : in  AxiLiteWriteMasterType := AXI_LITE_WRITE_MASTER_INIT_C;
        axilWriteSlave  : out AxiLiteWriteSlaveType
        );
end entity EvrGty;

architecture mapping of EvrGty is

    constant AXIL_TEST_INDEX_C : natural := 0;
    constant AXIL_DRP_INDEX_C  : natural := 1;
    constant EVR_REG_INDEX_C   : natural := 2;

    constant NUM_AXIL_MASTERS_C : positive := 3;

    signal axilReadMasters  : AxiLiteReadMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
    signal axilReadSlaves   : AxiLiteReadSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0)  := (others => AXI_LITE_READ_SLAVE_EMPTY_DECERR_C);
    signal axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
    signal axilWriteSlaves  : AxiLiteWriteSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0) := (others => AXI_LITE_WRITE_SLAVE_EMPTY_DECERR_C);

    -- Address bits must be equal to or more than the number of address bits
    -- for DRP interface to ensure acessability of full DRP address space.
    -- Note that DRP has 16 bit words while Axil has 8 bit words.
    -- Translation works as drp_addr = axil_addr >> 2 (shift by 2 bits).
    -- Seems like the DRP address is technically 10 bits so 12 address bits
    -- suffice, but for now use 16 as we have the room to do so.
    constant AXIL_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL_MASTERS_C-1 downto 0) := genAxiLiteConfig(NUM_AXIL_MASTERS_C, AXIL_BASE_ADDR_G, AXIL_BASE_BOT_G, 16);

    -- Aliases for axil signals for EVR_REG_INDEX_C
    -- signal axilRegReadMaster  : AxiLiteReadMasterType  := AXI_LITE_READ_MASTER_INIT_C;
    -- signal axilRegReadSlave   : AxiLiteReadSlaveType;
    -- signal axilRegWriteMaster : AxiLiteWriteMasterType := AXI_LITE_WRITE_MASTER_INIT_C;
    -- signal axilRegWriteSlave  : AxiLiteWriteSlaveType;

    signal resetGtSync : sl;
    signal gtHardReset : sl;

    signal gtRxUserResetSync : sl;
    signal gtTxUserResetSync : sl;

    signal rxResetDone : sl;
    signal txResetDone : sl;

    signal rxUsrClk : sl;
    signal txUsrClk : sl;
    -- signal rxUsrClkMmcm       : sl;     -- MMCM buffered clock
    -- signal txUsrClkMmcm       : sl;
    -- signal rxUsrClkMmcmLocked : sl;     -- MMCM locked signal
    -- signal txUsrClkMmcmLocked : sl;

    signal rxUsrClkActive : sl;
    signal txUsrClkActive : sl;

    signal qpll1Locked : sl;            -- Locked signal of QPLL1 in GT IP Core

    -- TODO: Use those as input to the decoder
    signal rxData    : slv(15 downto 0);
    signal rxDataK   : slv(1 downto 0);
    signal rxDispErr : slv(1 downto 0);
    signal rxDecErr  : slv(1 downto 0);

    signal txData  : slv(15 downto 0);
    signal txDataK : slv(1 downto 0);

    signal rxByteIsAligned : sl;
    signal rxByteRealign   : sl;
    signal rxCommaDet      : sl;
    signal rxPmaResetDone  : sl;

    signal txPmaResetDone : sl;

    signal rxCdrStable : sl;

    attribute keep       : string;
    attribute mark_debug : string;

    attribute keep of qpll1Locked : signal is "true";
    attribute keep of resetGtSync : signal is "true";
    attribute keep of gtHardReset : signal is "true";

    attribute keep of rxData          : signal is "true";
    attribute keep of rxDataK         : signal is "true";
    attribute keep of rxUsrClk        : signal is "true";
    -- attribute keep of rxUsrClkMmcmLocked : signal is "true";
    attribute keep of rxResetDone     : signal is "true";
    attribute keep of rxDispErr       : signal is "true";
    attribute keep of rxDecErr        : signal is "true";
    attribute keep of rxByteIsAligned : signal is "true";
    attribute keep of rxByteRealign   : signal is "true";
    attribute keep of rxCommaDet      : signal is "true";
    attribute keep of rxPmaResetDone  : signal is "true";

    attribute keep of rxCdrStable : signal is "true";

    attribute keep of txData         : signal is "true";
    attribute keep of txDataK        : signal is "true";
    attribute keep of txUsrClk       : signal is "true";
    -- attribute keep of txUsrClkMmcmLocked : signal is "true";
    attribute keep of txResetDone    : signal is "true";
    attribute keep of txPmaResetDone : signal is "true";

    attribute keep of txUsrClkActive : signal is "true";
    attribute keep of rxUsrClkActive : signal is "true";

    attribute mark_debug of qpll1Locked : signal is "true";
    attribute mark_debug of resetGtSync : signal is "true";
    attribute mark_debug of gtHardReset : signal is "true";

    attribute mark_debug of rxData          : signal is "true";
    attribute mark_debug of rxDataK         : signal is "true";
    attribute mark_debug of rxUsrClk        : signal is "true";
    -- attribute mark_debug of rxUsrClkMmcmLocked : signal is "true";
    attribute mark_debug of rxResetDone     : signal is "true";
    attribute mark_debug of rxDispErr       : signal is "true";
    attribute mark_debug of rxDecErr        : signal is "true";
    attribute mark_debug of rxByteIsAligned : signal is "true";
    attribute mark_debug of rxByteRealign   : signal is "true";
    attribute mark_debug of rxCommaDet      : signal is "true";
    attribute mark_debug of rxPmaResetDone  : signal is "true";

    attribute mark_debug of rxCdrStable : signal is "true";

    attribute mark_debug of txData         : signal is "true";
    attribute mark_debug of txDataK        : signal is "true";
    attribute mark_debug of txUsrClk       : signal is "true";
    -- attribute mark_debug of txUsrClkMmcmLocked : signal is "true";
    attribute mark_debug of txResetDone    : signal is "true";
    attribute mark_debug of txPmaResetDone : signal is "true";

    attribute mark_debug of txUsrClkActive : signal is "true";
    attribute mark_debug of rxUsrClkActive : signal is "true";


    type RegType is record
        loopback        : slv(2 downto 0);
        dummyData       : slv(7 downto 0);
        dummyDataComma  : slv(7 downto 0);
        trxRequestLP    : sl;
        txPolarity      : sl;
        rxPolarity      : sl;
        tx8b10bEn       : sl;
        rx8b10bEn       : sl;
        rxCommaDetEn    : sl;
        rxMCommaAlignEn : sl;
        rxPCommaAlignEn : sl;
        axilReadSlave   : AxiLiteReadSlaveType;
        axilWriteSlave  : AxiLiteWriteSlaveType;
    end record RegType;

    constant REG_INIT_C : RegType := (
        loopback        => "000",       -- 0b000 is normal operation
        dummyData       => x"50",  -- Dummy data to transmit when no comma is transmitted
        dummyDataComma  => x"BC",  -- Comma to insert when transmitting dummy data for testing
        trxRequestLP    => '0',         -- Default is NOT low power
        txPolarity      => '0',
        rxPolarity      => '0',
        tx8b10bEn       => '1',
        rx8b10bEn       => '1',
        rxCommaDetEn    => '1',
        rxMCommaAlignEn => '1',
        rxPCommaAlignEn => '1',
        axilReadSlave   => AXI_LITE_READ_SLAVE_INIT_C,
        axilWriteSlave  => AXI_LITE_WRITE_SLAVE_INIT_C);

    signal r   : RegType := REG_INIT_C;
    signal rin : RegType;

begin

    evrRxResetDone <= rxResetDone;
    evrTxResetDone <= txResetDone;

    gtHardReset <= resetGtSync or stableRst;

    U_RstGtSync : entity surf.PwrUpRst
        generic map (
            TPD_G      => TPD_G,
            DURATION_G => STABLE_CLK_F_HZ * 1)  -- 1 sec pulse
        port map (
            arst   => resetGt,                  -- [in]
            clk    => stableClk,                -- [in]
            rstOut => resetGtSync);             -- [out]

    -- Sync evrRxResetAsync to stableClk and tie to gtRxUserResetSync
    U_RstSync_Rx : entity surf.PwrUpRst
        generic map (
            TPD_G      => TPD_G,
            DURATION_G => STABLE_CLK_F_HZ * 1)  -- 1 sec pulse
        port map (
            arst   => evrRxResetAsync,          -- [in]
            clk    => stableClk,                -- [in]
            rstOut => gtRxUserResetSync);       -- [out]

    -- Sync evrTxResetAsync to stableClk and tie to gtTxUserResetSync
    U_RstSync_Tx : entity surf.PwrUpRst
        generic map (
            TPD_G      => TPD_G,
            DURATION_G => STABLE_CLK_F_HZ * 1)  -- 1 sec pulse
        port map (
            arst   => evrTxResetAsync,          -- [in]
            clk    => stableClk,                -- [in]
            rstOut => gtTxUserResetSync);       -- [out]

    -- Output (recovered and buffered) signal clocks. Event codes/shared bus
    -- also synchronous to this clock.
    evrRxUsrClk <= rxUsrClk;
    evrTxUsrClk <= txUsrClk;

    -- U_TxMirrorGen : if TX_MIRROR_ENABLE_G generate
    --     -- Mirror rx to TX 'as is' for to allow for event receiver daisy chaining
    --     txData  <= rxData;
    --     txDataK <= rxDataK;             -- Don't forget the K character flags!
    -- end generate U_TxMirrorGen;


    -- MMCM (PLL sufficient?) to detect stable user clock of transceiver
    -- U_RXUSRCLK_PLL : entity surf.ClockManagerUltraScale
    --     generic map(
    --         TPD_G              => TPD_G,
    --         TYPE_G             => "MMCM",
    --         INPUT_BUFG_G       => true,
    --         FB_BUFG_G          => true,
    --         RST_IN_POLARITY_G  => '1',
    --         NUM_CLOCKS_G       => 1,
    --         -- MMCM attributes
    --         BANDWIDTH_G        => "OPTIMIZED",
    --         CLKIN_PERIOD_G     => 6.4,  -- 156.25MHz (Actually ignored in synthesis???)
    --         DIVCLK_DIVIDE_G    => 1,    -- 156.25MHz = 156.25MHz/1
    --         CLKFBOUT_MULT_F_G  => 10.0,  -- 1562.5MHz = 10.0 x 156.25MHz (see DS925 for vco range)
    --         CLKOUT0_DIVIDE_F_G => 10.0)  -- 156.25MHz = 1562.5MHz/10.0
    --     port map(
    --         -- Clock Input
    --         clkIn     => rxUsrClk,
    --         rstIn     => gtHardReset,
    --         -- Clock Outputs
    --         locked    => rxUsrClkMmcmLocked,
    --         clkOut(0) => rxUsrClkMmcm,
    --         -- Reset Outputs
    --         rstOut(0) => open);
    --
    -- U_TXUSRCLK_PLL : entity surf.ClockManagerUltraScale
    --     generic map(
    --         TPD_G              => TPD_G,
    --         TYPE_G             => "MMCM",
    --         INPUT_BUFG_G       => true,
    --         FB_BUFG_G          => true,
    --         RST_IN_POLARITY_G  => '1',
    --         NUM_CLOCKS_G       => 1,
    --         -- MMCM attributes
    --         BANDWIDTH_G        => "OPTIMIZED",
    --         CLKIN_PERIOD_G     => 6.4,  -- 156.25MHz (Actually ignored in synthesis???)
    --         DIVCLK_DIVIDE_G    => 1,    -- 156.25MHz = 156.25MHz/1
    --         CLKFBOUT_MULT_F_G  => 10.0,  -- 1562.5MHz = 10.0 x 156.25MHz (see DS925 for vco range)
    --         CLKOUT0_DIVIDE_F_G => 10.0)  -- 156.25MHz = 1562.5MHz/10.0
    --     port map(
    --         -- Clock Input
    --         clkIn     => txUsrClk,
    --         rstIn     => gtHardReset,
    --         -- Clock Outputs
    --         locked    => txUsrClkMmcmLocked,
    --         clkOut(0) => txUsrClkMmcm,
    --         -- Reset Outputs
    --         rstOut(0) => open);


    ---------------------
    -- AXI-Lite Crossbar
    ---------------------
    -- Must route axil->DRP address space and general register access separately
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


    --------------------------
    -- Wrapper for GTY IP core
    --------------------------

    U_EvrGtyCoreWrapper : entity work.EvrGtyCoreWrapper
        generic map(
            TPD_G => TPD_G
            )
        port map(
            stableClk => stableClk,
            stableRst => gtHardReset,
            qpll1Lock => qpll1Locked,

            -- GTY FPGA IO
            gtRefClk => gtRefClk,  -- Use Dedicated clock pin for transceiver
            gtRxP    => evrGtRxP,
            gtRxN    => evrGtRxN,
            gtTxP    => evrGtTxP,
            gtTxN    => evrGtTxN,

            -- gtPowerGood => open,

            -- Rx ports
            rxResetDatapath => gtRxUserResetSync,
            rxResetUsrClk   => gtRxUserResetSync,
            rxUsrClk        => rxUsrClk,
            rxUsrClkActive  => rxUsrClkActive,
            -- rxUsrClkSrcClk  => open, -- Mirror of clock used to derive userclock (?)
            rxResetDone     => rxResetDone,
            rxData          => rxData,  -- Not yet connected to anything!
            rxDataK         => rxDataK,
            rxDispErr       => rxDispErr,  -- Disparity error flags (one per byte)
            rxDecErr        => rxDecErr,   -- Decode error flags (one per byte)
            rxPolarity      => r.rxPolarity,
            rx8b10bEn       => r.rx8b10bEn,
            rxCommaDetEn    => r.rxCommaDetEn,
            rxMCommaAlignEn => r.rxMCommaAlignEn,
            rxPCommaAlignEn => r.rxPCommaAlignEn,
            rxCdrStable     => rxCdrStable,

            rxByteIsAligned => rxByteIsAligned,
            rxByteRealign   => rxByteRealign,
            rxCommaDet      => rxCommaDet,
            rxPmaResetDone  => rxPmaResetDone,

            -- Tx ports
            txResetDatapath => gtTxUserResetSync,
            txResetUsrClk   => gtTxUserResetSync,
            txUsrClk        => txUsrClk,
            txUsrClkActive  => txUsrClkActive,
            -- txUsrClkSrcClk => open, -- Mirror of clock used to derive userclock (?)
            txResetDone     => txResetDone,
            txData          => txData,  -- Not yet connected to anything!
            txDataK         => txDataK,
            txPolarity      => r.txPolarity,
            tx8b10bEn       => r.tx8b10bEn,
            txPmaResetDone  => txPmaResetDone,

            -- Loopback mode for testing, see UG578
            loopback => r.loopback,  -- "000" -> normal operation (see UG578)

            -- AXI-Lite DRP interface
            axilClk         => axilClk,
            axilRst         => axilRst,
            axilReadMaster  => axilReadMasters(AXIL_DRP_INDEX_C),
            axilReadSlave   => axilReadSlaves(AXIL_DRP_INDEX_C),
            axilWriteMaster => axilWriteMasters(AXIL_DRP_INDEX_C),
            axilWriteSlave  => axilWriteSlaves(AXIL_DRP_INDEX_C)
            );

    -- Generate some test data
    TX_DUMMY_DATA : process(txUsrClk)
        variable switch : boolean;
    begin
        if rising_edge(txUsrClk) then
            -- Pull all lines low if reset asserted or tx not yet ready
            if gtHardReset = '1' or txResetDone /= '1' then
                txData  <= (others => '0');
                txDataK <= (others => '0');
            elsif switch = true then
                txData  <= r.dummyData & r.dummyDataComma;  -- Comma in lower 8 bits
                txDataK <= "01";        -- Lower byte is comma
                switch  := false;       -- Move to send only data state
            else
                txData  <= r.dummyData & r.dummyData;
                txDataK <= "00";        -- Now commas here
                switch  := true;        -- Move to send data + comma state
            end if;
        end if;
    end process TX_DUMMY_DATA;

    -- Some static registers for testing
    U_AXIL_TEST_REG : entity work.AxilTestRegister
        port map(
            axilClk         => axilClk,
            axilReadMaster  => axilReadMasters(AXIL_TEST_INDEX_C),
            axilReadSlave   => axilReadSlaves(AXIL_TEST_INDEX_C),
            axilWriteMaster => axilWriteMasters(AXIL_TEST_INDEX_C),
            axilWriteSlave  => axilWriteSlaves(AXIL_TEST_INDEX_C)
            );

    comb : process (axilReadMasters(EVR_REG_INDEX_C), axilWriteMasters(EVR_REG_INDEX_C), r) is
        variable v      : RegType;
        variable axilEp : AxiLiteEndPointType;
    begin

        -- Latch the current value
        v := r;

        ----------------------------------------------------------------------
        --                AXI-Lite Register Logic
        ----------------------------------------------------------------------

        -- Determine the transaction type
        axiSlaveWaitTxn(axilEp, axilWriteMasters(EVR_REG_INDEX_C), axilReadMasters(EVR_REG_INDEX_C), v.axilWriteSlave, v.axilReadSlave);

        -------------------------
        -- Map the read registers
        -------------------------

        axiSlaveRegister (axilEp, x"00", 0, v.loopback);   -- GTY loopback mode
        axiSlaveRegister (axilEp, x"04", 0, v.dummyData);  -- Dummy data to transmit for testing
        axiSlaveRegister (axilEp, x"08", 0, v.dummyDataComma);  -- Comma to insert when transmitting dummy data for testing
        axiSlaveRegister (axilEp, x"0a", 0, v.trxRequestLP);  -- Transmitter low power request line state
        axiSlaveRegister (axilEp, x"0c", 0, v.txPolarity);  -- GTY TX polarity
        axiSlaveRegister (axilEp, x"0c", 1, v.rxPolarity);  -- GTY RX polarity

        axiSlaveRegister (axilEp, x"10", 0, v.tx8b10bEn);  -- TX 8b10b decode enable
        axiSlaveRegister (axilEp, x"10", 1, v.rx8b10bEn);  -- RX 8b10b decode enable
        axiSlaveRegister (axilEp, x"14", 0, v.rxCommaDetEn);  -- GTY RX comma detection enable
        axiSlaveRegister (axilEp, x"14", 2, v.rxMCommaAlignEn);  -- GTY RX align on minus comma enable
        axiSlaveRegister (axilEp, x"14", 3, v.rxPCommaAlignEn);  -- GTY RX align on plus comma enable

        -- Closeout the transaction
        axiSlaveDefault(axilEp, v.axilWriteSlave, v.axilReadSlave, AXI_RESP_DECERR_C);

        ----------------------------------------------------------------------

        -- Outputs
        axilWriteSlaves(EVR_REG_INDEX_C) <= r.axilWriteSlave;
        axilReadSlaves(EVR_REG_INDEX_C)  <= r.axilReadSlave;
        trxRequestLP                     <= v.trxRequestLP;

        -- Register the variable for next clock cycle
        rin <= v;

    end process comb;

    seq : process (axilClk) is
    begin
        if rising_edge(axilClk) then
            r <= rin after TPD_G;
        end if;
    end process seq;

end architecture mapping;
