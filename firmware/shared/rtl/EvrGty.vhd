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
        evrTxMmcmLocked : in  sl;
        -- Rx clocking
        evrRxResetAsync : in  sl;
        evrRxResetDone  : out sl;
        evrRxUsrClk     : out sl;  -- user clock  = recovered clock (rx data sync. to this)
        evrRxMmcmLocked : in  sl;
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

    signal gtRxUserResetSync : sl;
    signal gtTxUserResetSync : sl;

    signal rxResetDone : sl;
    signal txResetDone : sl;

    signal rxOutClk : sl;
    signal txOutClk : sl;

    signal rxOutClkBuff : sl;
    signal txOutClkBuff : sl;

    signal rxUsrClk : sl;
    signal txUsrClk : sl;

    -- TODO: Use those as input to the decoder
    signal rxData    : slv(15 downto 0);
    signal rxDataK   : slv(1 downto 0);
    signal rxDispErr : slv(1 downto 0);
    signal rxDecErr  : slv(1 downto 0);

    signal txData  : slv(15 downto 0);
    signal txDataK : slv(1 downto 0);

begin

    evrRxResetDone <= rxResetDone;
    evrTxResetDone <= txResetDone;

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
    evrRxUsrClk <= rxUsrClk;
    evrTxUsrClk <= txUsrClk;

    U_TxMirrorGen : if TX_MIRROR_ENABLE_G generate
        -- Mirror rx to TX 'as is' for to allow for event receiver daisy chaining
        txData  <= rxData;
        txDataK <= rxDataK;             -- Don't forget the K character flags!
    end generate U_TxMirrorGen;

    --------------------------
    -- Wrapper for GTY IP core
    --------------------------
    U_EvrGtyCoreWrapper : entity work.EvrGtyCoreWrapper
        generic map(
            TPD_G => TPD_G
            )
        port map(
            stableClk       => stableClk,
            stableRst       => stableRst,
            gtRefClk        => gtRefClk,
            gtRxP           => evrGtRxP,
            gtRxN           => evrGtRxN,
            gtTxP           => evrGtTxP,
            gtTxN           => evrGtTxN,
            rxReset         => gtRxUserResetSync,
            rxUsrClk        => rxUsrClk,
            rxUsrClkActive  => evrRxMmcmLocked,  -- Put MMCM in the module locking on gtRefClk?!
            rxResetDone     => rxResetDone,
            rxData          => rxData,  -- Not yet connected to anything!
            rxDataK         => rxDataK,
            rxDispErr       => rxDispErr,  -- Disparity error flags (one per byte)
            rxDecErr        => rxDecErr,   -- Decode error flags (one per byte)
            rxPolarity      => RX_POLARITY_G,
            rxOutClk        => rxOutClk,
            txReset         => gtTxUserResetSync,
            txUsrClk        => txUsrClk,
            txUsrClkActive  => evrTxMmcmLocked,
            txResetDone     => txResetDone,
            txData          => txData,  -- Not yet connected to anything!
            txDataK         => txDataK,
            txPolarity      => TX_POLARITY_G,
            txOutClk        => txOutClk,
            -- Loopback makes no sense as only TX->RX is possible and we do not
            -- actually generate anything to trasnmit, only mirror.
            loopback        => "000",  -- "000" -> normal operation (see PG182)
            axilClk         => axilClk,
            axilRst         => axilRst,
            axilReadMaster  => axilReadMaster,
            axilReadSlave   => axilReadSlave,
            axilWriteMaster => axilWriteMaster,
            axilWriteSlave  => axilWriteSlave
            );

end architecture mapping;
