library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.numeric_std.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;
use surf.AxiLitePkg.all;

library work;
use work.AppPkg.all;

library unisim;
use unisim.vcomponents.all;

-- Description:
-- Wrapper around GTY IP core (GT Wizard) to receive serial data stream
-- transmitted from event master over optical fiber and do the 8b10b
-- decoding etc. to provide just the serial data contents to downstream
-- logic.

-- Notes:
-- > Keep EVR Decoder as separate entity to allow use with other transceivers
--   as the transceiver details are likely to depend on the used hardware.

entity EvrGty is
    generic (
        TPD_G            : time    := 1 ns;
        STABLE_CLK_F_HZ  : integer := 156250000;  -- Used to time resets
        AXIL_BASE_ADDR_G : slv(31 downto 0);
        AXIL_BASE_BOT_G  : natural range 1 to 32;
        RX_LANE_IDX_G    : integer := 0;
        TX_LANE_IDX_G    : integer := 0
        );
    port (
        -- GT Clocking
        stableClk       : in  sl;       -- GT needs a stable clock to "boot up"
        stableRst       : in  sl;
        resetGt         : in  sl;
        gtRefClk        : in  sl;
        -- GT Serial IO
        evrGtTxP        : out slv(3 downto 0);
        evrGtTxN        : out slv(3 downto 0);
        evrGtRxP        : in  slv(3 downto 0);
        evrGtRxN        : in  slv(3 downto 0);
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

        -- QSFP transceiver control signals
        qsfpModSelL : out sl;           -- Pull low for access over i2c!
        qsfpResetL  : out sl;
        qsfpModPrsL : in  sl;
        qsfpIntL    : in  sl;
        qsfpLpMode  : out sl;

        -- Serial data out
        usrClk   : out sl;  -- user clock (rx data interface syncrhonous to this clock)
        data     : out slv(15 downto 0);
        gtyReady : out sl;  -- Held low until GTY ready (running and aligned and qsfp present if not ignored)
        dataK    : out slv(1 downto 0);
        dispErr  : out slv(1 downto 0);
        decErr   : out slv(1 downto 0);

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

    constant EVR_REG_INDEX_C  : natural := 0;  -- Registers defined in this file, if possible no offset
    constant AXIL_DRP_INDEX_C : natural := 1;

    constant NUM_AXIL_MASTERS_C : positive := 2;

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

    signal resetGtSync : sl;
    signal gtReset     : sl;

    signal gtRxUserResetSync : sl;
    signal gtTxUserResetSync : sl;

    signal rxResetDone : sl;
    signal txResetDone : sl;

    signal rxUsrClk : sl;
    signal txUsrClk : sl;

    signal rxUsrClkActive : sl;
    signal txUsrClkActive : sl;

    signal qpll1Locked : sl;            -- Locked signal of QPLL1 in GT IP Core

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

    signal dummySdTrigSync : sl;

    -- Enable for ILA debugging
    -- attribute keep       : string;
    -- attribute mark_debug : string;
    --
    -- attribute keep of qpll1Locked : signal is "true";
    -- attribute keep of resetGtSync : signal is "true";
    -- attribute keep of gtReset     : signal is "true";
    --
    -- attribute keep of rxData          : signal is "true";
    -- attribute keep of rxDataK         : signal is "true";
    -- attribute keep of rxUsrClk        : signal is "true";
    -- attribute keep of rxResetDone     : signal is "true";
    -- attribute keep of rxDispErr       : signal is "true";
    -- attribute keep of rxDecErr        : signal is "true";
    -- attribute keep of rxByteIsAligned : signal is "true";
    -- attribute keep of rxByteRealign   : signal is "true";
    -- attribute keep of rxCommaDet      : signal is "true";
    -- attribute keep of rxPmaResetDone  : signal is "true";
    --
    -- attribute keep of rxCdrStable : signal is "true";
    --
    -- attribute keep of txData         : signal is "true";
    -- attribute keep of txDataK        : signal is "true";
    -- attribute keep of txUsrClk       : signal is "true";
    -- attribute keep of txResetDone    : signal is "true";
    -- attribute keep of txPmaResetDone : signal is "true";
    --
    -- attribute keep of txUsrClkActive : signal is "true";
    -- attribute keep of rxUsrClkActive : signal is "true";
    --
    -- attribute mark_debug of qpll1Locked : signal is "true";
    -- attribute mark_debug of resetGtSync : signal is "true";
    -- attribute mark_debug of gtReset     : signal is "true";
    --
    -- attribute mark_debug of rxData          : signal is "true";
    -- attribute mark_debug of rxDataK         : signal is "true";
    -- attribute mark_debug of rxUsrClk        : signal is "true";
    -- -- attribute mark_debug of rxUsrClkMmcmLocked : signal is "true";
    -- attribute mark_debug of rxResetDone     : signal is "true";
    -- attribute mark_debug of rxDispErr       : signal is "true";
    -- attribute mark_debug of rxDecErr        : signal is "true";
    -- attribute mark_debug of rxByteIsAligned : signal is "true";
    -- attribute mark_debug of rxByteRealign   : signal is "true";
    -- attribute mark_debug of rxCommaDet      : signal is "true";
    -- attribute mark_debug of rxPmaResetDone  : signal is "true";
    --
    -- attribute mark_debug of rxCdrStable : signal is "true";
    --
    -- attribute mark_debug of txData         : signal is "true";
    -- attribute mark_debug of txDataK        : signal is "true";
    -- attribute mark_debug of txUsrClk       : signal is "true";
    -- -- attribute mark_debug of txUsrClkMmcmLocked : signal is "true";
    -- attribute mark_debug of txResetDone    : signal is "true";
    -- attribute mark_debug of txPmaResetDone : signal is "true";
    --
    -- attribute mark_debug of txUsrClkActive : signal is "true";
    -- attribute mark_debug of rxUsrClkActive : signal is "true";

    type EvrTxModeType is (
        RX_MIRROR,  -- Mirror rx 'as is' to tx (including commas)
        DUMMY,                          -- Transmit dummy data and commas
        SILENT                          -- Transmit nothing at all
        );

    type RegType is record
        qsfpModSelL      : sl;          -- Pull low for access over i2c!
        qsfpResetL       : sl;
        qsfpLpMode       : sl;
        ignoreQsfpModPrs : sl;

        -- Software resets (write only registers)
        softRst   : sl;
        rxSoftRst : sl;
        txSoftRst : sl;

        -- Reset related signals
        tx8b10bEn  : sl;
        txPolarity : sl;

        rx8b10bEn  : sl;
        rxPolarity : sl;

        rxCommaDetEn    : sl;
        rxMCommaAlignEn : sl;
        rxPCommaAlignEn : sl;

        -- Dummy EV bits transmissions
        evrTxMode        : evrTxModeType;
        evrTxModeReg     : slv(7 downto 0);
        dummyEvData      : slv(7 downto 0);
        dummyEvDataComma : slv(7 downto 0);

        -- Dummy DbSd bits transmissions
        dummySdTrig : sl;
        dummySdData : slv(31 downto 0);  -- TODO: Use axi ram for larger buffer
        dummySdSeg  : slv(7 downto 0);

        -- loopback : slv(2 downto 0);

        axilReadSlave  : AxiLiteReadSlaveType;
        axilWriteSlave : AxiLiteWriteSlaveType;
    end record RegType;

    constant REG_INIT_C : RegType := (
        -- QSFP control signals
        -- Pull this signal low for access over i2c (address 0x50 as specified in
        -- SFF-8636)! If I do not pull this low, there is still some EEPROM I can
        -- write to/read from??? Not sure what is going on there...
        qsfpModSelL      => '0',        -- Default is selected!
        qsfpResetL       => '1',
        qsfpLpMode       => '0',        -- Default is NOT low power
        ignoreQsfpModPrs => '0',

        -- Software resets (write only registers)
        softRst   => '0',
        rxSoftRst => '0',
        txSoftRst => '0',

        -- Reset related signals
        tx8b10bEn  => '1',
        txPolarity => '0',  -- Set 1 to invert polarity (diff. pair swap)

        rx8b10bEn  => '1',
        rxPolarity => '0',  -- Set 1 to invert polarity (diff. pair swap)

        rxCommaDetEn    => '1',
        rxMCommaAlignEn => '1',
        rxPCommaAlignEn => '1',

        -- Dummy EV bits transmissions
        evrTxMode        => SILENT,
        evrTxModeReg     => (others => '0'),  -- Same es evrTxMode but as slv (required for register mapping)
        dummyEvData      => x"50",  -- Dummy data to transmit when no comma is transmitted
        dummyEvDataComma => x"BC",  -- Comma to insert when transmitting dummy data for testing

        -- Dummy DbSd bits transmissions
        dummySdTrig => '0',
        dummySdData => x"76543210",
        dummySdSeg  => (others => '0'),

        -- loopback => "000",              -- 0b000 is normal operation

        axilReadSlave  => AXI_LITE_READ_SLAVE_INIT_C,
        axilWriteSlave => AXI_LITE_WRITE_SLAVE_INIT_C);


    type TxDummySdStateType is (
        IDLE_S,
        LEAD_S,
        SEG_S,
        TX_S,
        TRAIL_S);

    type TxDummyRegType is record
        txData        : slv(15 downto 0);
        txDataK       : slv(1 downto 0);
        transmitComma : sl;
        sdState       : TxDummySdStateType;
        sdCycleCount  : slv(31 downto 0);
    end record TxDummyRegType;

    constant TX_DUMMY_REG_INIT_C : TxDummyRegType := (
        txData        => (others => '0'),
        txDataK       => (others => '0'),
        transmitComma => '0',
        sdState       => IDLE_S,
        sdCycleCount  => (others => '0'));


    signal r   : RegType := REG_INIT_C;
    signal rin : RegType;

    signal txDummyR   : TxDummyRegType := TX_DUMMY_REG_INIT_C;
    signal txDummyRin : TxDummyRegType;

begin
    -- Serial data outputs
    usrClk   <= rxUsrClk;
    data     <= rxData;
    dataK    <= rxDataK;
    dispErr  <= rxDispErr;
    decErr   <= rxDecErr;
    -- Use ready signal to hold decoder in reset until gty ready.
    -- QSFP present can be ignored for e.g. testing without QSFP module.
    gtyReady <= rxResetDone and rxByteIsAligned and (not qsfpModPrsL or r.ignoreQsfpModPrs);

    evrRxResetDone <= rxResetDone;
    evrTxResetDone <= txResetDone;

    gtReset <= resetGtSync or stableRst;

    -- Drive QSFP transceiver controls *output* signals according to registers
    qsfpModSelL <= r.qsfpModSelL;
    -- TODO: Do or with GT reset?
    qsfpResetL  <= r.qsfpResetL;  -- QSPF reset (not the same as GTY reset!)
    qsfpLpMode  <= r.qsfpLpMode;

    -- Sync async reset and soft reset (axil clock domain) to stableClk
    U_RstGtSync : entity surf.PwrUpRst
        generic map (
            TPD_G      => TPD_G,
            DURATION_G => STABLE_CLK_F_HZ * 1)  -- 1 sec pulse
        port map (
            arst   => resetGt or r.softRst,     -- [in]
            clk    => stableClk,                -- [in]
            rstOut => resetGtSync);             -- [out]

    -- Sync evrRxResetAsync or rxSoftRst to stableClk and tie to gtRxUserResetSync
    U_RstSync_Rx : entity surf.PwrUpRst
        generic map (
            TPD_G      => TPD_G,
            DURATION_G => STABLE_CLK_F_HZ * 1)         -- 1 sec pulse
        port map (
            arst   => evrRxResetAsync or r.rxSoftRst,  -- [in]
            clk    => stableClk,                       -- [in]
            rstOut => gtRxUserResetSync);              -- [out]

    -- Sync evrTxResetAsync or txSoftRst to stableClk and tie to gtTxUserResetSync
    U_RstSync_Tx : entity surf.PwrUpRst
        generic map (
            TPD_G      => TPD_G,
            DURATION_G => STABLE_CLK_F_HZ * 1)         -- 1 sec pulse
        port map (
            arst   => evrTxResetAsync or r.txSoftRst,  -- [in]
            clk    => stableClk,                       -- [in]
            rstOut => gtTxUserResetSync);              -- [out]

    -- Output (recovered and buffered) signal clocks. Event codes/shared bus
    -- also synchronous to this clock.
    evrRxUsrClk <= rxUsrClk;
    evrTxUsrClk <= txUsrClk;

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
            TPD_G            => TPD_G,
            RX_LANE_IDX_G    => RX_LANE_IDX_G,
            TX_LANE_IDX_G    => TX_LANE_IDX_G,
            AXIL_BASE_ADDR_G => AXIL_CONFIG_C(AXIL_DRP_INDEX_C).baseAddr)
        port map(
            stableClk => stableClk,  -- The core expects this to be < usrclk but it still seems to work fine with 156.25 which is > userclk
            stableRst => gtReset,
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
            -- loopback => r.loopback,  -- "000" -> normal operation (see UG578)

            -- AXI-Lite DRP interface
            axilClk         => axilClk,
            axilRst         => axilRst,
            axilReadMaster  => axilReadMasters(AXIL_DRP_INDEX_C),
            axilReadSlave   => axilReadSlaves(AXIL_DRP_INDEX_C),
            axilWriteMaster => axilWriteMasters(AXIL_DRP_INDEX_C),
            axilWriteSlave  => axilWriteSlaves(AXIL_DRP_INDEX_C));


    ---------------------
    -- Register Interface
    ---------------------

    comb : process (
        axilReadMasters(EVR_REG_INDEX_C), axilWriteMasters(EVR_REG_INDEX_C), r,
        qsfpModPrsL,  -- Not sure if this is the smartes way to 'mirror' some signals to registers...
        qsfpIntL,
        txResetDone,
        txPmaResetDone,
        txUsrClkActive,
        rxResetDone,
        rxPmaResetDone,
        rxUsrClkActive,
        rxCdrStable,
        rxDispErr,
        rxDecErr,
        rxByteIsAligned,
        rxByteRealign,
        rxCommaDet,
        resetGtSync,
        gtRxUserResetSync,
        gtTxUserResetSync
        ) is
        variable v      : RegType;
        variable axilEp : AxiLiteEndPointType;
    begin

        -- Latch the current value
        v := r;

        -- Reset strobes
        v.softRst     := '0';
        v.rxSoftRst   := '0';
        v.txSoftRst   := '0';
        v.dummySdTrig := '0';

        ----------------------------------------------------------------------
        --                AXI-Lite Register Logic
        ----------------------------------------------------------------------

        -- Determine the transaction type
        axiSlaveWaitTxn(axilEp, axilWriteMasters(EVR_REG_INDEX_C), axilReadMasters(EVR_REG_INDEX_C), v.axilWriteSlave, v.axilReadSlave);

        -------------------------
        -- Map the read registers
        -------------------------

        axiSlaveRegister (axilEp, x"00", 0, v.qsfpModSelL);
        axiSlaveRegister (axilEp, x"00", 1, v.qsfpResetL);
        axiSlaveRegisterR(axilEp, x"00", 2, qsfpModPrsL);
        axiSlaveRegisterR(axilEp, x"00", 3, qsfpIntL);
        axiSlaveRegister (axilEp, x"00", 4, v.qsfpLpMode);  -- Transmitter low power request line state
        axiSlaveRegister (axilEp, x"00", 5, v.ignoreQsfpModPrs);  -- If set, ignore mod prs signal in ready logic

        axiSlaveRegister (axilEp, x"00", 16, v.softRst);  -- Full GTY software reset (write only)
        axiSlaveRegister (axilEp, x"00", 17, v.rxSoftRst);  -- RX only software reset (write only)
        axiSlaveRegister (axilEp, x"00", 18, v.txSoftRst);  -- TX only software reset (write only)
        axiSlaveRegisterR(axilEp, x"00", 19, resetGtSync);  -- Readback of long reset pulse
        axiSlaveRegisterR(axilEp, x"00", 20, gtRxUserResetSync);  -- Readback of long reset pulse
        axiSlaveRegisterR(axilEp, x"00", 21, gtTxUserResetSync);  -- Readback of long reset pulse

        axiSlaveRegisterR(axilEp, x"04", 0, txResetDone);
        axiSlaveRegisterR(axilEp, x"04", 1, txPmaResetDone);
        axiSlaveRegisterR(axilEp, x"04", 2, txUsrClkActive);  -- User interface TX clock ready, i.e. ready to transmit
        axiSlaveRegister (axilEp, x"04", 3, v.tx8b10bEn);  -- TX 8b10b decode enable
        axiSlaveRegister (axilEp, x"04", 4, v.txPolarity);  -- GTY TX polarity

        axiSlaveRegisterR(axilEp, x"08", 0, rxResetDone);
        axiSlaveRegisterR(axilEp, x"08", 1, rxPmaResetDone);
        axiSlaveRegisterR(axilEp, x"08", 2, rxUsrClkActive);  -- User interface RX clock ready, i.e. ready to transmit
        axiSlaveRegister (axilEp, x"08", 3, v.rx8b10bEn);  -- RX 8b10b decode enable
        axiSlaveRegister (axilEp, x"08", 4, v.rxPolarity);  -- GTY RX polarity

        axiSlaveRegisterR(axilEp, x"0c", 0, rxCdrStable);
        axiSlaveRegisterR(axilEp, x"0c", 1, rxDispErr);   -- Two bit register
        axiSlaveRegisterR(axilEp, x"0c", 3, rxDecErr);    -- Two bit register
        axiSlaveRegisterR(axilEp, x"0c", 5, rxByteIsAligned);  -- Signals bytes are aligned
        axiSlaveRegisterR(axilEp, x"0c", 6, rxByteRealign);  -- Strobed on byte realign
        axiSlaveRegisterR(axilEp, x"0c", 7, rxCommaDet);  -- Strobed on comma detected
        axiSlaveRegister (axilEp, x"0c", 8, v.rxCommaDetEn);  -- GTY RX comma detection enable
        axiSlaveRegister (axilEp, x"0c", 9, v.rxMCommaAlignEn);  -- GTY RX align on minus comma enable
        axiSlaveRegister (axilEp, x"0c", 10, v.rxPCommaAlignEn);  -- GTY RX align on plus comma enable
        v.evrTxModeReg := conv_std_logic_vector(evrTxModeType'pos(r.evrTxMode), r.evrTxModeReg'length);

        axiSlaveRegister (axilEp, x"10", 0, v.evrTxModeReg);  -- Mode for transmitting
        axiSlaveRegister (axilEp, x"10", 8, v.dummyEvData);  -- Dummy data to transmit for testing
        axiSlaveRegister (axilEp, x"10", 16, v.dummyEvDataComma);  -- Comma to insert when transmitting dummy data for testing

        axiSlaveRegister (axilEp, x"14", 0, v.dummySdData);  -- 4 bytes of data for dummy SD transmission
        axiSlaveRegister (axilEp, x"18", 0, v.dummySdSeg);   -- Segment byte
        axiSlaveRegister (axilEp, x"1c", 0, v.dummySdTrig);  -- Software trigger dummy SD transmission

        -- axiSlaveRegister (axilEp, x"14", 0, v.loopback);  -- GTY loopback mode

        -- Closeout the transaction
        axiSlaveDefault(axilEp, v.axilWriteSlave, v.axilReadSlave, AXI_RESP_DECERR_C);

        ----------------------------------------------------------------------

        -- Outputs

        -- Re-assign evrTxMode according to the value in v to update if there was a write to the corresponding register
        v.evrTxMode := evrTxModeType'val(conv_integer(v.evrTxModeReg));

        axilWriteSlaves(EVR_REG_INDEX_C) <= r.axilWriteSlave;
        axilReadSlaves(EVR_REG_INDEX_C)  <= r.axilReadSlave;

        -- Register the variable for next clock cycle
        rin <= v;

    end process comb;

    seq : process (axilClk) is
    begin
        if rising_edge(axilClk) then
            r <= rin after TPD_G;
        end if;
    end process seq;


    ----------------------
    -- Transmit processing
    ----------------------
    -- TODO: Consider refactoring into a separate Evm (event master) module?

    U_dummySdTrigSync : entity surf.SynchronizerOneShot
        generic map(
            TPD_G => TPD_G)
        port map(
            clk     => txUsrClk,
            dataIn  => r.dummySdTrig,
            dataOut => dummySdTrigSync);

    -- Generate some test data
    -- Dont really care about synchronization for most registers as they should
    -- be stable for many clocks...
    txDummyComb : process(txDummyR, r, gtReset, txResetDone, dummySdTrigSync)
        variable v : TxDummyRegType;
    begin

        -- Latch the current value
        v := txDummyR;

        -- Reset strobes
        v.txData  := (others => '0');
        v.txDataK := (others => '0');

        -- Set event or comma in lower byte
        if gtReset = '1' or txResetDone /= '1' or r.evrTxMode = SILENT then
            -- Pull all lines low if reset asserted or tx not yet ready or TX set to silent
            v.txData  := (others => '0');
            v.txDataK := (others => '0');
        elsif r.evrTxMode = DUMMY then
            -- Transmit dummy data with a comma every other tranmission
            if txDummyR.transmitComma = '1' then
                v.txData(7 downto 0) := r.dummyEvDataComma;  -- Comma in lower 8 bits
                v.txDataK(0)         := '1';  -- Lower byte is comma
                v.transmitComma      := '0';  -- Move to send only data state
            else
                v.txData(7 downto 0) := r.dummyEvData;
                v.txDataK(0)         := '0';  -- Now commas here
                v.transmitComma      := '1';  -- Move to send data + comma state
            end if;
        elsif r.evrTxMode = RX_MIRROR then
        -- TODO: This would require a fifo between rx/tx. Implement this if it is really necessary.
        end if;

        -- Dummy SD transmission
        case txDummyR.sdState is
            when IDLE_S =>
                -- Initiate dummy transmission if triggered
                if dummySdTrigSync = '1' then
                    v.sdState := LEAD_S;
                end if;
            when LEAD_S =>
                -- Transmit start byte
                v.txData(15 downto 8) := x"1C";
                v.txDataK(1)          := '1';
                -- Transmit segment byte next
                v.sdState             := SEG_S;
            when SEG_S =>
                -- Transmit the segment byte
                v.txData(15 downto 8) := r.dummySdSeg;
                v.txDataK(1)          := '0';
                -- Preset counter (transmit 32 / 8 = 4 bytes of dummy data), but only
                -- transmit every second cycle.
                -- Could omit the -1 to get one cycle of DB after the end byte.
                v.sdCycleCount        := toSlv(4*2-1, 32);
                -- Start transmitting data
                v.sdState             := TX_S;
            when TX_S =>
                -- TODO: For now buffer has fixed length to fit one 32 bit AXI register.
                -- Add AXI RAM for larger buffers (later).
                -- Transmit only every second (counter even) cycle
                if txDummyR.sdCycleCount(0) = '0' then
                    v.txData(15 downto 8) := r.dummySdData(conv_integer(txDummyR.sdCycleCount)*8+7 downto conv_integer(txDummyR.sdCycleCount)*8);
                    v.txDataK(1)          := '0';
                else
                -- TODO: Add DB data?
                end if;
                v.sdCycleCount := txDummyR.sdCycleCount - 1;
                if txDummyR.sdCycleCount = 0 then
                    v.sdState := TRAIL_S;
                end if;
            when TRAIL_S =>
                -- Transmit end byte
                v.txData(15 downto 8) := x"3C";
                v.txDataK(1)          := '1';
                -- TODO: Implement trailing checksum bytes
                -- Return to idle
                v.sdState             := IDLE_S;
        end case;

        -- Outputs
        txData  <= txDummyR.txData;
        txDataK <= txDummyR.txDataK;

        -- Register the variable for next clock cycle
        txDummyRin <= v;

    end process txDummyComb;


    txDummySeq : process (txUsrClk) is
    begin
        if rising_edge(txUsrClk) then
            txDummyR <= txDummyRin after TPD_G;
        end if;
    end process txDummySeq;

end architecture mapping;
