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

entity EvrGty is
    generic (
        TPD_G              : time    := 1 ns;
        STABLE_CLK_F_HZ    : integer := 156250000;  -- Used to time resets
        ----------------------------------------------------------------------------------------------
        -- EVR Settings
        ----------------------------------------------------------------------------------------------
        TX_POLARITY_G      : sl      := '0';
        RX_POLARITY_G      : sl      := '0';
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

    signal resetGtSync : sl;
    signal gtHardReset : sl;

    signal gtRxUserResetSync : sl;
    signal gtTxUserResetSync : sl;

    signal rxResetDone : sl;
    signal txResetDone : sl;

    signal rxOutClk : sl;
    signal txOutClk : sl;

    signal rxOutClkBuff : sl;
    signal txOutClkBuff : sl;

    signal rxUsrClk           : sl;
    signal txUsrClk           : sl;
    signal rxUsrClkMmcm       : sl;     -- MMCM buffered clock
    signal txUsrClkMmcm       : sl;
    signal rxUsrClkMmcmLocked : sl;     -- MMCM locked signal
    signal txUsrClkMmcmLocked : sl;

    signal qpll1Locked : sl;            -- Locked signal of QPLL1 in GT IP Core

    -- TODO: Use those as input to the decoder
    signal rxData    : slv(15 downto 0);
    signal rxDataK   : slv(1 downto 0);
    signal rxDispErr : slv(1 downto 0);
    signal rxDecErr  : slv(1 downto 0);

    signal txData  : slv(15 downto 0);
    signal txDataK : slv(1 downto 0);

    attribute keep       : string;
    attribute mark_debug : string;

    attribute keep of qpll1Locked        : signal is "true";
    attribute keep of resetGtSync        : signal is "true";
    attribute keep of gtHardReset        : signal is "true";
    attribute keep of rxData             : signal is "true";
    attribute keep of rxDataK            : signal is "true";
    attribute keep of rxUsrClk           : signal is "true";
    attribute keep of rxUsrClkMmcmLocked : signal is "true";
    attribute keep of rxResetDone        : signal is "true";
    attribute keep of rxDispErr          : signal is "true";
    attribute keep of rxDecErr           : signal is "true";
    attribute keep of txData             : signal is "true";
    attribute keep of txDataK            : signal is "true";
    attribute keep of txUsrClk           : signal is "true";
    attribute keep of txUsrClkMmcmLocked : signal is "true";
    attribute keep of txResetDone        : signal is "true";

    attribute mark_debug of qpll1Locked        : signal is "true";
    attribute mark_debug of resetGtSync        : signal is "true";
    attribute mark_debug of gtHardReset        : signal is "true";
    attribute mark_debug of rxData             : signal is "true";
    attribute mark_debug of rxDataK            : signal is "true";
    attribute mark_debug of rxUsrClk           : signal is "true";
    attribute mark_debug of rxUsrClkMmcmLocked : signal is "true";
    attribute mark_debug of rxResetDone        : signal is "true";
    attribute mark_debug of rxDispErr          : signal is "true";
    attribute mark_debug of rxDecErr           : signal is "true";
    attribute mark_debug of txData             : signal is "true";
    attribute mark_debug of txDataK            : signal is "true";
    attribute mark_debug of txUsrClk           : signal is "true";
    attribute mark_debug of txUsrClkMmcmLocked : signal is "true";
    attribute mark_debug of txResetDone        : signal is "true";

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

    U_BUFG_GT_RxOutClk : BUFG_GT
        port map (
            I       => rxOutClk,        -- 1-bit input: Buffer
            O       => rxOutClkBuff,    -- 1-bit output: Buffer
            CE      => '1',             -- 1-bit input: Buffer enable
            CEMASK  => '0',             -- 1-bit input: CE Mask
            CLR     => '0',             -- 1-bit input: Asynchronous clear
            CLRMASK => '0',             -- 1-bit input: CLR Mask
            DIV     => "000"            -- 3-bit input: Dynamic divide Value
            );

    U_BUFG_GT_TxOutClk : BUFG_GT
        port map (
            I       => txOutClk,        -- 1-bit input: Buffer
            O       => txOutClkBuff,    -- 1-bit output: Buffer
            CE      => '1',             -- 1-bit input: Buffer enable
            CEMASK  => '0',             -- 1-bit input: CE Mask
            CLR     => '0',             -- 1-bit input: Asynchronous clear
            CLRMASK => '0',             -- 1-bit input: CLR Mask
            DIV     => "000"            -- 3-bit input: Dynamic divide Value
            );


    -- Loop recovered clocks back for the user interface
    rxUsrClk <= rxOutClkBuff;
    txUsrClk <= txOutClkBuff;

    -- Output (recovered and buffered) signal clocks. Event codes/shared bus
    -- also synchronous to this clock.
    evrRxUsrClk <= rxUsrClkMmcm;
    evrTxUsrClk <= txUsrClkMmcm;

    U_TxMirrorGen : if TX_MIRROR_ENABLE_G generate
        -- Mirror rx to TX 'as is' for to allow for event receiver daisy chaining
        txData  <= rxData;
        txDataK <= rxDataK;             -- Don't forget the K character flags!
    end generate U_TxMirrorGen;


    -- MMCM (PLL sufficient?) to detect stable user clock of transceiver
    U_RXUSRCLK_PLL : entity surf.ClockManagerUltraScale
        generic map(
            TPD_G              => TPD_G,
            TYPE_G             => "MMCM",
            INPUT_BUFG_G       => true,
            FB_BUFG_G          => true,
            RST_IN_POLARITY_G  => '1',
            NUM_CLOCKS_G       => 1,
            -- MMCM attributes
            BANDWIDTH_G        => "OPTIMIZED",
            CLKIN_PERIOD_G     => 6.4,  -- 156.25MHz (Actually ignored in synthesis???)
            DIVCLK_DIVIDE_G    => 1,    -- 156.25MHz = 156.25MHz/1
            CLKFBOUT_MULT_F_G  => 10.0,  -- 1562.5MHz = 10.0 x 156.25MHz (see DS925 for vco range)
            CLKOUT0_DIVIDE_F_G => 10.0)  -- 156.25MHz = 1562.5MHz/10.0
        port map(
            -- Clock Input
            clkIn     => rxUsrClk,
            rstIn     => gtHardReset,
            -- Clock Outputs
            locked    => rxUsrClkMmcmLocked,
            clkOut(0) => rxUsrClkMmcm,
            -- Reset Outputs
            rstOut(0) => open);

    U_TXUSRCLK_PLL : entity surf.ClockManagerUltraScale
        generic map(
            TPD_G              => TPD_G,
            TYPE_G             => "MMCM",
            INPUT_BUFG_G       => true,
            FB_BUFG_G          => true,
            RST_IN_POLARITY_G  => '1',
            NUM_CLOCKS_G       => 1,
            -- MMCM attributes
            BANDWIDTH_G        => "OPTIMIZED",
            CLKIN_PERIOD_G     => 6.4,  -- 156.25MHz (Actually ignored in synthesis???)
            DIVCLK_DIVIDE_G    => 1,    -- 156.25MHz = 156.25MHz/1
            CLKFBOUT_MULT_F_G  => 10.0,  -- 1562.5MHz = 10.0 x 156.25MHz (see DS925 for vco range)
            CLKOUT0_DIVIDE_F_G => 10.0)  -- 156.25MHz = 1562.5MHz/10.0
        port map(
            -- Clock Input
            clkIn     => txUsrClk,
            rstIn     => gtHardReset,
            -- Clock Outputs
            locked    => txUsrClkMmcmLocked,
            clkOut(0) => txUsrClkMmcm,
            -- Reset Outputs
            rstOut(0) => open);

    --------------------------
    -- Wrapper for GTY IP core
    --------------------------
    U_EvrGtyCoreWrapper : entity work.EvrGtyCoreWrapper
        generic map(
            TPD_G => TPD_G
            )
        port map(
            stableClk       => stableClk,
            stableRst       => gtHardReset,
            qpll1Lock       => qpll1Locked,
            gtRefClk        => gtRefClk,
            gtRxP           => evrGtRxP,
            gtRxN           => evrGtRxN,
            gtTxP           => evrGtTxP,
            gtTxN           => evrGtTxN,
            rxReset         => gtRxUserResetSync,
            rxUsrClk        => rxUsrClkMmcm,  -- Probably does not matter if rxUsrClkMmcm or rxUsrClk directly?
            -- TODO: I think we must assert UsrClkActive to complete reset
            -- procedure, i.e. ResetDone will never be asserted before
            -- UsrClkActive is asserted.
            -- rxUsrClkActive  => evrRxMmcmLocked,  -- Put MMCM in the module locking on gtRefClk?!
            rxUsrClkActive  => rxUsrClkMmcmLocked and qpll1Locked,  -- Assume clock stable if MMCM locked
            rxResetDone     => rxResetDone,
            rxData          => rxData,  -- Not yet connected to anything!
            rxDataK         => rxDataK,
            rxDispErr       => rxDispErr,  -- Disparity error flags (one per byte)
            rxDecErr        => rxDecErr,   -- Decode error flags (one per byte)
            rxPolarity      => RX_POLARITY_G,
            rxOutClk        => rxOutClk,
            txReset         => gtTxUserResetSync,
            txUsrClk        => txUsrClkMmcm,
            -- TODO: I think we must assert UsrClkActive to complete reset
            -- procedure, i.e. ResetDone will never be asserted before
            -- UsrClkActive is asserted.
            -- txUsrClkActive  => evrTxMmcmLocked,
            txUsrClkActive  => txUsrClkMmcmLocked and qpll1Locked,  -- Assume clock stable if reset done
            txResetDone     => txResetDone,
            txData          => txData,  -- Not yet connected to anything!
            txDataK         => txDataK,
            txPolarity      => TX_POLARITY_G,
            txOutClk        => txOutClk,
            -- Loopback makes no sense as only TX->RX is possible and we do not
            -- actually generate anything to trasnmit, only mirror RX->TX.
            loopback        => "001",  -- "000" -> normal operation (see PG182)
            axilClk         => axilClk,
            axilRst         => axilRst,
            axilReadMaster  => axilReadMaster,
            axilReadSlave   => axilReadSlave,
            axilWriteMaster => axilWriteMaster,
            axilWriteSlave  => axilWriteSlave
            );

    -- Generate some test data
    TX_DUMMY_DATA : process(txUsrClkMmcm)
        variable switch : boolean;

        constant K28_5      : std_logic_vector(7 downto 0) := x"BC";  -- K28.5 comma
        constant DUMMY_DATA : std_logic_vector(7 downto 0) := x"50";
    begin
        if rising_edge(txUsrClkMmcm) then
            -- Pull all lines low if reset asserted or tx not yet ready
            if gtHardReset = '1' or txResetDone /= '1' then
                txData  <= (others => '0');
                txDataK <= (others => '0');
            elsif switch = true then
                txData  <= DUMMY_DATA & K28_5;  -- Comma in lower 8 bits
                txDataK <= "01";        -- Lower byte is comma
                switch  := false;       -- Move to send only data state
            else
                txData  <= DUMMY_DATA & DUMMY_DATA;
                txDataK <= "00";        -- Now commas here
                switch  := true;        -- Move to send data + comma state
            end if;
        end if;
    end process TX_DUMMY_DATA;

end architecture mapping;
