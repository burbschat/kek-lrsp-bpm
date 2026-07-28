library ieee;
use ieee.std_logic_1164.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiLitePkg.all;

entity EvrGtyCoreWrapper is

    generic (
        TPD_G            : time    := 1 ns;
        RX_LANE_IDX_G    : integer := 0;
        TX_LANE_IDX_G    : integer := 0;
        AXIL_BASE_ADDR_G : slv(31 downto 0));
    port (
        stableClk : in  sl;
        stableRst : in  sl;
        qpll1Lock : out sl;

        -- GTY FPGA IO
        gtRefClk : in  sl;  -- Use Dedicated clock pin for transceiver
        gtRxP    : in  slv(3 downto 0);
        gtRxN    : in  slv(3 downto 0);
        gtTxP    : out slv(3 downto 0);
        gtTxN    : out slv(3 downto 0);

        gtPowerGood : out sl;

        -- Rx ports
        rxResetDatapath : in  sl;
        rxResetUsrClk   : in  sl;
        rxUsrClk        : out sl;
        rxUsrClkActive  : out sl;
        rxUsrClkSrcClk  : out sl;
        rxResetDone     : out sl;
        rxData          : out slv(15 downto 0);
        rxDataK         : out slv(1 downto 0);
        rxDispErr       : out slv(1 downto 0);
        rxDecErr        : out slv(1 downto 0);
        rxPolarity      : in  sl;
        rx8b10bEn       : in  sl := '1';  -- High to enable 8b10b decoding, may disable for testing
        rxCommaDetEn    : in  sl := '1';
        rxMCommaAlignEn : in  sl := '1';  -- Minus comma alignemnt enable
        rxPCommaAlignEn : in  sl := '1';  -- Plus comma alignemnt enable
        rxCdrStable     : out sl;

        rxByteIsAligned : out sl;
        rxByteRealign   : out sl;
        rxCommaDet      : out sl;
        rxPmaResetDone  : out sl;

        -- Tx Ports
        txResetDatapath : in  sl;
        txResetUsrClk   : in  sl;
        txUsrClk        : out sl;
        txUsrClkActive  : out sl;
        txUsrClkSrcClk  : out sl;
        txResetDone     : out sl;
        txData          : in  slv(15 downto 0);
        txDataK         : in  slv(1 downto 0);
        txPolarity      : in  sl;
        tx8b10bEn       : in  sl := '1';  -- High to enable 8b10b decoding, may disable for testing
        txPmaResetDone  : out sl;
        -- txPrgDivResetDone : out sl;

        -- Loopback mode for testing, see UG578
        -- Wont work with separate lanes I think...
        -- loopback : in slv(2 downto 0);

        -- AXI-Lite DRP interface
        axilClk         : in  sl                     := '0';
        axilRst         : in  sl                     := '0';
        axilReadMaster  : in  AxiLiteReadMasterType  := AXI_LITE_READ_MASTER_INIT_C;
        axilReadSlave   : out AxiLiteReadSlaveType;
        axilWriteMaster : in  AxiLiteWriteMasterType := AXI_LITE_WRITE_MASTER_INIT_C;
        axilWriteSlave  : out AxiLiteWriteSlaveType
        );

end entity EvrGtyCoreWrapper;

architecture mapping of EvrGtyCoreWrapper is

    component EvrGtyCore
        port (
            gtwiz_userclk_tx_reset_in          : in  std_logic_vector(0 downto 0);
            gtwiz_userclk_tx_srcclk_out        : out std_logic_vector(0 downto 0);
            gtwiz_userclk_tx_usrclk_out        : out std_logic_vector(0 downto 0);
            gtwiz_userclk_tx_usrclk2_out       : out std_logic_vector(0 downto 0);
            gtwiz_userclk_tx_active_out        : out std_logic_vector(0 downto 0);
            gtwiz_userclk_rx_reset_in          : in  std_logic_vector(0 downto 0);
            gtwiz_userclk_rx_srcclk_out        : out std_logic_vector(0 downto 0);
            gtwiz_userclk_rx_usrclk_out        : out std_logic_vector(0 downto 0);
            gtwiz_userclk_rx_usrclk2_out       : out std_logic_vector(0 downto 0);
            gtwiz_userclk_rx_active_out        : out std_logic_vector(0 downto 0);
            gtwiz_reset_clk_freerun_in         : in  std_logic_vector(0 downto 0);
            gtwiz_reset_all_in                 : in  std_logic_vector(0 downto 0);
            gtwiz_reset_tx_pll_and_datapath_in : in  std_logic_vector(0 downto 0);
            gtwiz_reset_tx_datapath_in         : in  std_logic_vector(0 downto 0);
            gtwiz_reset_rx_pll_and_datapath_in : in  std_logic_vector(0 downto 0);
            gtwiz_reset_rx_datapath_in         : in  std_logic_vector(0 downto 0);
            gtwiz_reset_rx_cdr_stable_out      : out std_logic_vector(0 downto 0);
            gtwiz_reset_tx_done_out            : out std_logic_vector(0 downto 0);
            gtwiz_reset_rx_done_out            : out std_logic_vector(0 downto 0);
            gtwiz_userdata_tx_in               : in  std_logic_vector(63 downto 0);
            gtwiz_userdata_rx_out              : out std_logic_vector(63 downto 0);
            gtrefclk01_in                      : in  std_logic_vector(0 downto 0);
            qpll1lock_out                      : out std_logic_vector(0 downto 0);
            qpll1outclk_out                    : out std_logic_vector(0 downto 0);
            qpll1outrefclk_out                 : out std_logic_vector(0 downto 0);
            drpaddr_in                         : in  std_logic_vector(39 downto 0);
            drpclk_in                          : in  std_logic_vector(3 downto 0);
            drpdi_in                           : in  std_logic_vector(63 downto 0);
            drpen_in                           : in  std_logic_vector(3 downto 0);
            drpwe_in                           : in  std_logic_vector(3 downto 0);
            gtyrxn_in                          : in  std_logic_vector(3 downto 0);
            gtyrxp_in                          : in  std_logic_vector(3 downto 0);
            loopback_in                        : in  std_logic_vector(11 downto 0);
            rx8b10ben_in                       : in  std_logic_vector(3 downto 0);
            rxcommadeten_in                    : in  std_logic_vector(3 downto 0);
            rxmcommaalignen_in                 : in  std_logic_vector(3 downto 0);
            rxpcommaalignen_in                 : in  std_logic_vector(3 downto 0);
            rxpolarity_in                      : in  std_logic_vector(3 downto 0);
            tx8b10ben_in                       : in  std_logic_vector(3 downto 0);
            txctrl0_in                         : in  std_logic_vector(63 downto 0);
            txctrl1_in                         : in  std_logic_vector(63 downto 0);
            txctrl2_in                         : in  std_logic_vector(31 downto 0);
            txpolarity_in                      : in  std_logic_vector(3 downto 0);
            drpdo_out                          : out std_logic_vector(63 downto 0);
            drprdy_out                         : out std_logic_vector(3 downto 0);
            gtpowergood_out                    : out std_logic_vector(3 downto 0);
            gtytxn_out                         : out std_logic_vector(3 downto 0);
            gtytxp_out                         : out std_logic_vector(3 downto 0);
            rxbyteisaligned_out                : out std_logic_vector(3 downto 0);
            rxbyterealign_out                  : out std_logic_vector(3 downto 0);
            rxcommadet_out                     : out std_logic_vector(3 downto 0);
            rxctrl0_out                        : out std_logic_vector(63 downto 0);
            rxctrl1_out                        : out std_logic_vector(63 downto 0);
            rxctrl2_out                        : out std_logic_vector(31 downto 0);
            rxctrl3_out                        : out std_logic_vector(31 downto 0);
            rxpmaresetdone_out                 : out std_logic_vector(3 downto 0);
            txpmaresetdone_out                 : out std_logic_vector(3 downto 0)
            );
    end component;

    constant N_LANES_C : natural := 4;

    -- DRP signals
    signal drpAddr : slv(10 * N_LANES_C-1 downto 0);
    signal drpDi   : slv(16 * N_LANES_C-1 downto 0);
    signal drpDo   : slv(16 * N_LANES_C-1 downto 0);
    signal drpEn   : slv(N_LANES_C-1 downto 0);
    signal drpWe   : slv(N_LANES_C-1 downto 0);
    signal drpRdy  : slv(N_LANES_C-1 downto 0);

    -- 10 bit address DRP translated to AXI-Lite requires 12 bit AXI-Lite address,
    -- thus set addrBits to 12. We have at most two DRP interfaces so one bit is
    -- sufficient to set the subspace, thus set baseBot to 12+1=13.
    constant AXIL_CONFIG_C : AxiLiteCrossbarMasterConfigArray(1 downto 0) := genAxiLiteConfig(2, AXIL_BASE_ADDR_G, 13, 12);

    signal axilReadMasters  : AxiLiteReadMasterArray(1 downto 0);
    signal axilReadSlaves   : AxiLiteReadSlaveArray(1 downto 0)  := (others => AXI_LITE_READ_SLAVE_EMPTY_DECERR_C);
    signal axilWriteMasters : AxiLiteWriteMasterArray(1 downto 0);
    signal axilWriteSlaves  : AxiLiteWriteSlaveArray(1 downto 0) := (others => AXI_LITE_WRITE_SLAVE_EMPTY_DECERR_C);

    signal dummy0_6  : slv(5 downto 0);
    signal dummy1_14 : slv(13 downto 0);
    signal dummy2_14 : slv(13 downto 0);

    signal gtwiz_userdata_tx_in_all  : slv(63 downto 0) := (others => '0');
    signal gtwiz_userdata_rx_out_all : slv(63 downto 0) := (others => '0');
    signal gtyrxn_in_all             : slv(3 downto 0)  := (others => '0');
    signal gtyrxp_in_all             : slv(3 downto 0)  := (others => '0');
    signal loopback_in_all           : slv(11 downto 0) := (others => '0');
    signal rx8b10ben_in_all          : slv(3 downto 0)  := (others => '0');
    signal rxcommadeten_in_all       : slv(3 downto 0)  := (others => '0');
    signal rxmcommaalignen_in_all    : slv(3 downto 0)  := (others => '0');
    signal rxpcommaalignen_in_all    : slv(3 downto 0)  := (others => '0');
    signal rxpolarity_in_all         : slv(3 downto 0)  := (others => '0');
    signal tx8b10ben_in_all          : slv(3 downto 0)  := (others => '0');
    signal txctrl0_in_all            : slv(63 downto 0) := (others => '0');
    signal txctrl1_in_all            : slv(63 downto 0) := (others => '0');
    signal txpolarity_in_all         : slv(3 downto 0)  := (others => '0');
    signal gtpowergood_out_all       : slv(3 downto 0)  := (others => '0');
    signal gtytxn_out_all            : slv(3 downto 0)  := (others => '0');
    signal gtytxp_out_all            : slv(3 downto 0)  := (others => '0');
    signal rxbyteisaligned_out_all   : slv(3 downto 0)  := (others => '0');
    signal rxbyterealign_out_all     : slv(3 downto 0)  := (others => '0');
    signal rxcommadet_out_all        : slv(3 downto 0)  := (others => '0');
    signal rxctrl0_out_all           : slv(63 downto 0) := (others => '0');
    signal rxctrl1_out_all           : slv(63 downto 0) := (others => '0');
    signal rxctrl3_out_all           : slv(31 downto 0) := (others => '0');
    signal rxpmaresetdone_out_all    : slv(3 downto 0)  := (others => '0');
    signal txpmaresetdone_out_all    : slv(3 downto 0)  := (others => '0');


    signal txctrl2_all : slv(31 downto 0);  -- Use signal to set unused lanes ctrl signals to 0

    signal gtPowerGoodRxInt : sl;
    signal gtPowerGoodTxInt : sl;

begin

    U_EvrGtyCore : EvrGtyCore
        port map (
            gtwiz_userclk_tx_reset_in(0)   => txResetUsrClk,
            gtwiz_userclk_tx_active_out(0) => txUsrClkActive,
            gtwiz_userclk_tx_srcclk_out(0) => txUsrClkSrcClk,
            gtwiz_userclk_rx_reset_in(0)   => rxResetUsrClk,
            gtwiz_userclk_rx_active_out(0) => rxUsrClkActive,
            gtwiz_userclk_rx_srcclk_out(0) => rxUsrClkSrcClk,

            gtwiz_reset_clk_freerun_in(0) => stableClk,
            gtwiz_reset_all_in(0)         => stableRst,

            gtwiz_reset_tx_pll_and_datapath_in(0) => '0',
            gtwiz_reset_tx_datapath_in(0)         => txResetDatapath,
            gtwiz_reset_rx_pll_and_datapath_in(0) => '0',
            gtwiz_reset_rx_datapath_in(0)         => rxResetDatapath,
            gtwiz_reset_rx_cdr_stable_out(0)      => rxCdrStable,
            gtwiz_reset_tx_done_out(0)            => txResetDone,
            gtwiz_reset_rx_done_out(0)            => rxResetDone,

            gtwiz_userdata_tx_in  => gtwiz_userdata_tx_in_all,
            gtwiz_userdata_rx_out => gtwiz_userdata_rx_out_all,

            drpclk_in(0) => stableClk,
            drpclk_in(1) => stableClk,
            drpclk_in(2) => stableClk,
            drpclk_in(3) => stableClk,
            drpaddr_in   => drpAddr,
            drpdi_in     => drpDi,
            drpen_in     => drpEn,
            drpwe_in     => drpWe,
            drpdo_out    => drpDo,
            drprdy_out   => drpRdy,

            gtrefclk01_in(0)   => gtRefClk,
            qpll1lock_out(0)   => qpll1Lock,
            qpll1outclk_out    => open,
            qpll1outrefclk_out => open,

            gtyrxn_in   => gtyrxn_in_all,
            gtyrxp_in   => gtyrxp_in_all,
            loopback_in => loopback_in_all,

            rx8b10ben_in       => rx8b10ben_in_all,
            rxcommadeten_in    => rxcommadeten_in_all,
            rxmcommaalignen_in => rxmcommaalignen_in_all,
            rxpcommaalignen_in => rxpcommaalignen_in_all,

            rxpolarity_in                   => rxpolarity_in_all,
            gtwiz_userclk_rx_usrclk_out(0)  => rxUsrClk,
            gtwiz_userclk_rx_usrclk2_out(0) => open,

            gtytxn_out => gtytxn_out_all,
            gtytxp_out => gtytxp_out_all,

            tx8b10ben_in => tx8b10ben_in_all,
            -- Only need lower 16 bits as user data width is set to 16 bit in the IP core anyways
            txctrl0_in   => txctrl0_in_all,
            txctrl1_in   => txctrl1_in_all,
            txctrl2_in   => txctrl2_all,

            txpolarity_in                   => txpolarity_in_all,
            gtwiz_userclk_tx_usrclk_out(0)  => txUsrClk,
            gtwiz_userclk_tx_usrclk2_out(0) => open,

            rxctrl0_out => rxctrl0_out_all,
            rxctrl1_out => rxctrl1_out_all,
            rxctrl2_out => open,
            rxctrl3_out => rxctrl3_out_all,

            gtpowergood_out     => gtpowergood_out_all,
            rxbyteisaligned_out => rxbyteisaligned_out_all,
            rxbyterealign_out   => rxbyterealign_out_all,
            rxcommadet_out      => rxcommadet_out_all,
            rxpmaresetdone_out  => rxpmaresetdone_out_all,
            txpmaresetdone_out  => txpmaresetdone_out_all
            );

    -- Assign signals but only for the actually used lanes
    gtwiz_userdata_tx_in_all(15 + TX_LANE_IDX_G * 16 downto 0 + TX_LANE_IDX_G * 16) <= txData;

    rxData <= gtwiz_userdata_rx_out_all(15 + RX_LANE_IDX_G * 16 downto 0 + RX_LANE_IDX_G * 16);

    -- Connect only the acutally used lane
    gtyrxn_in_all(RX_LANE_IDX_G) <= gtRxN(RX_LANE_IDX_G);
    gtyrxp_in_all(RX_LANE_IDX_G) <= gtRxP(RX_LANE_IDX_G);

    loopback_in_all <= (others => '0');  -- all zeros -> normal operation

    rx8b10ben_in_all(RX_LANE_IDX_G) <= rx8b10bEn;

    rxcommadeten_in_all(RX_LANE_IDX_G) <= rxCommaDetEn;

    rxmcommaalignen_in_all(RX_LANE_IDX_G) <= rxMCommaAlignEn;

    rxpcommaalignen_in_all(RX_LANE_IDX_G) <= rxPCommaAlignEn;

    rxpolarity_in_all(RX_LANE_IDX_G) <= rxPolarity;

    tx8b10ben_in_all(TX_LANE_IDX_G) <= tx8b10bEn;

    --- txctrl0_in_all <= (others => '0');  -- Unused

    --- txctrl1_in_all <= (others => '0');  -- Unused

    -- Assign K character flag to the correct part of the control register
    txctrl2_all(7 + 8*TX_LANE_IDX_G downto 8*TX_LANE_IDX_G) <= "000000" & txDataK;  -- TX K character flag (16 bit width -> 16/8 = 2 flags)

    txpolarity_in_all(TX_LANE_IDX_G) <= txPolarity;

    gtPowerGoodRxInt <= gtpowergood_out_all(RX_LANE_IDX_G);
    gtPowerGoodTxInt <= gtpowergood_out_all(TX_LANE_IDX_G);
    gtPowerGood      <= gtPowerGoodRxInt and gtPowerGoodTxInt;

    -- Connect only the acutally used lane
    gtTxN(TX_LANE_IDX_G) <= gtytxn_out_all(TX_LANE_IDX_G);
    gtTxP(TX_LANE_IDX_G) <= gtytxp_out_all(TX_LANE_IDX_G);

    rxByteIsAligned <= rxbyteisaligned_out_all(RX_LANE_IDX_G);

    rxByteRealign <= rxbyterealign_out_all(RX_LANE_IDX_G);

    rxCommaDet <= rxcommadet_out_all(RX_LANE_IDX_G);

    rxDataK   <= rxctrl0_out_all(1 + 16 * RX_LANE_IDX_G downto 0 + 16 * RX_LANE_IDX_G);  -- RX K character flag (16 bit width -> 16/8 = 2 flags)
    dummy1_14 <= rxctrl0_out_all(15 + 16 * RX_LANE_IDX_G downto 2 + 16 * RX_LANE_IDX_G);

    rxDispErr <= rxctrl1_out_all(1 + 16 * RX_LANE_IDX_G downto 0 + 16 * RX_LANE_IDX_G);
    dummy2_14 <= rxctrl1_out_all(15 + 16 * RX_LANE_IDX_G downto 2 + 16 * RX_LANE_IDX_G);

    rxDecErr <= rxctrl3_out_all(1 + 8 * RX_LANE_IDX_G downto 0 + 8 * RX_LANE_IDX_G);
    dummy0_6 <= rxctrl3_out_all(7 + 8 * RX_LANE_IDX_G downto 2 + 8 * RX_LANE_IDX_G);

    rxPmaResetDone <= rxpmaresetdone_out_all(RX_LANE_IDX_G);

    txPmaResetDone <= txpmaresetdone_out_all(TX_LANE_IDX_G);


    -- Bridge DRP interfaces of selected lanes to AXI-Lite interface
    genAxiLiteToDrp_SameLane : if RX_LANE_IDX_G = TX_LANE_IDX_G generate
        -- Same lane used -> Map only one DRP interface of the used lane
        U_AxiLiteToDrp_RXTX : entity surf.AxiLiteToDrp
            generic map (
                TPD_G            => TPD_G,
                COMMON_CLK_G     => false,
                EN_ARBITRATION_G => false,
                ADDR_WIDTH_G     => 10,
                DATA_WIDTH_G     => 16)
            port map (
                axilClk         => axilClk,                -- [in]
                axilRst         => axilRst,                -- [in]
                axilReadMaster  => axilReadMaster,         -- [in]
                axilReadSlave   => axilReadSlave,          -- [out]
                axilWriteMaster => axilWriteMaster,        -- [in]
                axilWriteSlave  => axilWriteSlave,         -- [out]
                drpClk          => stableClk,              -- [in]
                drpRst          => stableRst,              -- [in]
                drpReq          => open,                   -- [out]
                -- Indices are the same so using either of RX/TX is fine
                drpRdy          => drpRdy(RX_LANE_IDX_G),  -- [in]
                drpEn           => drpEn(RX_LANE_IDX_G),   -- [out]
                drpWe           => drpWe(RX_LANE_IDX_G),   -- [out]
                drpUsrRst       => open,                   -- [out]
                drpAddr         => drpAddr(9 + 10 * RX_LANE_IDX_G downto 0 + 10 * RX_LANE_IDX_G),  -- [out]
                drpDi           => drpDi(15 + 16 * RX_LANE_IDX_G downto 0 + 16 * RX_LANE_IDX_G),  -- [out]
                drpDo           => drpDo(15 + 16 * RX_LANE_IDX_G downto 0 + 16 * RX_LANE_IDX_G));  -- [in]

    end generate genAxiLiteToDrp_SameLane;

    genAxiLiteToDrp_DiffLane : if RX_LANE_IDX_G /= TX_LANE_IDX_G generate
        -- Different lanes used -> Map DRP interfaces of both lanes
        U_AxiLiteToDrp_RX : entity surf.AxiLiteToDrp
            generic map (
                TPD_G            => TPD_G,
                COMMON_CLK_G     => false,
                EN_ARBITRATION_G => false,
                ADDR_WIDTH_G     => 10,
                DATA_WIDTH_G     => 16)
            port map (
                axilClk         => axilClk,                -- [in]
                axilRst         => axilRst,                -- [in]
                axilReadMaster  => axilReadMasters(0),     -- [in]
                axilReadSlave   => axilReadSlaves(0),      -- [out]
                axilWriteMaster => axilWriteMasters(0),    -- [in]
                axilWriteSlave  => axilWriteSlaves(0),     -- [out]
                drpClk          => stableClk,              -- [in]
                drpRst          => stableRst,              -- [in]
                drpReq          => open,                   -- [out]
                drpRdy          => drpRdy(RX_LANE_IDX_G),  -- [in]
                drpEn           => drpEn(RX_LANE_IDX_G),   -- [out]
                drpWe           => drpWe(RX_LANE_IDX_G),   -- [out]
                drpUsrRst       => open,                   -- [out]
                drpAddr         => drpAddr(9 + 10 * RX_LANE_IDX_G downto 0 + 10 * RX_LANE_IDX_G),  -- [out]
                drpDi           => drpDi(15 + 16 * RX_LANE_IDX_G downto 0 + 16 * RX_LANE_IDX_G),  -- [out]
                drpDo           => drpDo(15 + 16 * RX_LANE_IDX_G downto 0 + 16 * RX_LANE_IDX_G));  -- [in]

        U_AxiLiteToDrp_TX : entity surf.AxiLiteToDrp
            generic map (
                TPD_G            => TPD_G,
                COMMON_CLK_G     => false,
                EN_ARBITRATION_G => false,
                ADDR_WIDTH_G     => 10,
                DATA_WIDTH_G     => 16)
            port map (
                axilClk         => axilClk,                -- [in]
                axilRst         => axilRst,                -- [in]
                axilReadMaster  => axilReadMasters(1),     -- [in]
                axilReadSlave   => axilReadSlaves(1),      -- [out]
                axilWriteMaster => axilWriteMasters(1),    -- [in]
                axilWriteSlave  => axilWriteSlaves(1),     -- [out]
                drpClk          => stableClk,              -- [in]
                drpRst          => stableRst,              -- [in]
                drpReq          => open,                   -- [out]
                drpRdy          => drpRdy(TX_LANE_IDX_G),  -- [in]
                drpEn           => drpEn(TX_LANE_IDX_G),   -- [out]
                drpWe           => drpWe(TX_LANE_IDX_G),   -- [out]
                drpUsrRst       => open,                   -- [out]
                drpAddr         => drpAddr(9 + 10 * TX_LANE_IDX_G downto 0 + 10 * TX_LANE_IDX_G),  -- [out]
                drpDi           => drpDi(15 + 16 * TX_LANE_IDX_G downto 0 + 16 * TX_LANE_IDX_G),  -- [out]
                drpDo           => drpDo(15 + 16 * TX_LANE_IDX_G downto 0 + 16 * TX_LANE_IDX_G));  -- [in]


        U_XBAR : entity surf.AxiLiteCrossbar
            generic map (
                TPD_G              => TPD_G,
                NUM_SLAVE_SLOTS_G  => 1,
                NUM_MASTER_SLOTS_G => 2,
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
    end generate genAxiLiteToDrp_DiffLane;

end architecture mapping;
