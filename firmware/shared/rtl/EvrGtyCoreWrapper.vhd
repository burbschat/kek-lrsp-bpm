library ieee;
use ieee.std_logic_1164.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiLitePkg.all;

entity EvrGtyCoreWrapper is

    generic (
        TPD_G : time := 1 ns);

    port (
        stableClk : in  sl;
        stableRst : in  sl;
        qpll1Lock : out sl;

        -- GTY FPGA IO
        gtRefClk : in  sl;  -- Use Dedicated clock pin for transceiver
        gtRxP    : in  sl;
        gtRxN    : in  sl;
        gtTxP    : out sl;
        gtTxN    : out sl;

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
        loopback : in slv(2 downto 0);

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
            gtwiz_userdata_tx_in               : in  std_logic_vector(15 downto 0);
            gtwiz_userdata_rx_out              : out std_logic_vector(15 downto 0);
            gtrefclk01_in                      : in  std_logic_vector(0 downto 0);
            qpll1lock_out                      : out std_logic_vector(0 downto 0);
            qpll1outclk_out                    : out std_logic_vector(0 downto 0);
            qpll1outrefclk_out                 : out std_logic_vector(0 downto 0);
            drpaddr_in                         : in  std_logic_vector(9 downto 0);
            drpclk_in                          : in  std_logic_vector(0 downto 0);
            drpdi_in                           : in  std_logic_vector(15 downto 0);
            drpen_in                           : in  std_logic_vector(0 downto 0);
            drpwe_in                           : in  std_logic_vector(0 downto 0);
            gtyrxn_in                          : in  std_logic_vector(0 downto 0);
            gtyrxp_in                          : in  std_logic_vector(0 downto 0);
            loopback_in                        : in  std_logic_vector(2 downto 0);
            rx8b10ben_in                       : in  std_logic_vector(0 downto 0);
            rxcommadeten_in                    : in  std_logic_vector(0 downto 0);
            rxmcommaalignen_in                 : in  std_logic_vector(0 downto 0);
            rxpcommaalignen_in                 : in  std_logic_vector(0 downto 0);
            rxpolarity_in                      : in  std_logic_vector(0 downto 0);
            tx8b10ben_in                       : in  std_logic_vector(0 downto 0);
            txctrl0_in                         : in  std_logic_vector(15 downto 0);
            txctrl1_in                         : in  std_logic_vector(15 downto 0);
            txctrl2_in                         : in  std_logic_vector(7 downto 0);
            txpolarity_in                      : in  std_logic_vector(0 downto 0);
            drpdo_out                          : out std_logic_vector(15 downto 0);
            drprdy_out                         : out std_logic_vector(0 downto 0);
            gtpowergood_out                    : out std_logic_vector(0 downto 0);
            gtytxn_out                         : out std_logic_vector(0 downto 0);
            gtytxp_out                         : out std_logic_vector(0 downto 0);
            rxbyteisaligned_out                : out std_logic_vector(0 downto 0);
            rxbyterealign_out                  : out std_logic_vector(0 downto 0);
            rxcommadet_out                     : out std_logic_vector(0 downto 0);
            rxctrl0_out                        : out std_logic_vector(15 downto 0);
            rxctrl1_out                        : out std_logic_vector(15 downto 0);
            rxctrl2_out                        : out std_logic_vector(7 downto 0);
            rxctrl3_out                        : out std_logic_vector(7 downto 0);
            rxpmaresetdone_out                 : out std_logic_vector(0 downto 0);
            txpmaresetdone_out                 : out std_logic_vector(0 downto 0)
            );
    end component;

    -- DRP signals
    signal drpAddr : slv(9 downto 0);
    signal drpDi   : slv(15 downto 0);
    signal drpDo   : slv(15 downto 0);
    signal drpEn   : sl;
    signal drpWe   : sl;
    signal drpRdy  : sl;

    signal dummy0_6  : slv(5 downto 0);
    signal dummy1_14 : slv(13 downto 0);
    signal dummy2_14 : slv(13 downto 0);

    signal txctrl2 : slv(7 downto 0);

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

            gtwiz_userdata_tx_in  => txData,
            gtwiz_userdata_rx_out => rxData,

            drpclk_in(0)  => stableClk,
            drpaddr_in    => drpAddr,
            drpdi_in      => drpDi,
            drpen_in(0)   => drpEn,
            drpwe_in(0)   => drpWe,
            drpdo_out     => drpDo,
            drprdy_out(0) => drpRdy,

            gtrefclk01_in(0)   => gtRefClk,
            qpll1lock_out(0)   => qpll1Lock,
            qpll1outclk_out    => open,
            qpll1outrefclk_out => open,

            gtyrxn_in(0) => gtRxN,
            gtyrxp_in(0) => gtRxP,
            loopback_in  => loopback,

            rx8b10ben_in(0)       => rx8b10bEn,
            rxcommadeten_in(0)    => rxCommaDetEn,
            rxmcommaalignen_in(0) => rxMCommaAlignEn,
            rxpcommaalignen_in(0) => rxPCommaAlignEn,

            rxpolarity_in(0)                => rxPolarity,
            gtwiz_userclk_rx_usrclk_out(0)  => rxUsrClk,
            gtwiz_userclk_rx_usrclk2_out(0) => open,

            gtytxn_out(0) => gtTxN,
            gtytxp_out(0) => gtTxP,

            tx8b10ben_in(0) => tx8b10bEn,
            -- Only need lower 16 bits as user data width is set to 16 bit in the IP core anyways
            txctrl0_in      => X"0000",
            txctrl1_in      => X"0000",
            txctrl2_in      => txctrl2,

            txpolarity_in(0)                => txPolarity,
            gtwiz_userclk_tx_usrclk_out(0)  => txUsrClk,
            gtwiz_userclk_tx_usrclk2_out(0) => open,

            rxctrl0_out(1 downto 0)  => rxDataK,  -- RX K character flag (16 bit width -> 16/8 = 2 flags)
            rxctrl0_out(15 downto 2) => dummy1_14,
            rxctrl1_out(1 downto 0)  => rxDispErr,
            rxctrl1_out(15 downto 2) => dummy2_14,
            rxctrl2_out              => open,
            rxctrl3_out(1 downto 0)  => rxDecErr,
            rxctrl3_out(7 downto 2)  => dummy0_6,

            gtpowergood_out(0)     => gtPowerGood,
            rxbyteisaligned_out(0) => rxByteIsAligned,
            rxbyterealign_out(0)   => rxByteRealign,
            rxcommadet_out(0)      => rxCommaDet,
            rxpmaresetdone_out(0)  => rxPmaResetDone,
            txpmaresetdone_out(0)  => txPmaResetDone
            );

    txctrl2 <= "000000" & txDataK;  -- TX K character flag (16 bit width -> 16/8 = 2 flags)


    U_AxiLiteToDrp_1 : entity surf.AxiLiteToDrp
        generic map (
            TPD_G            => TPD_G,
            COMMON_CLK_G     => false,
            EN_ARBITRATION_G => false,
            ADDR_WIDTH_G     => 10,
            DATA_WIDTH_G     => 16)
        port map (
            axilClk         => axilClk,          -- [in]
            axilRst         => axilRst,          -- [in]
            axilReadMaster  => axilReadMaster,   -- [in]
            axilReadSlave   => axilReadSlave,    -- [out]
            axilWriteMaster => axilWriteMaster,  -- [in]
            axilWriteSlave  => axilWriteSlave,   -- [out]
            drpClk          => stableClk,        -- [in]
            drpRst          => stableRst,        -- [in]
            drpReq          => open,             -- [out]
            drpRdy          => drpRdy,           -- [in]
            drpEn           => drpEn,            -- [out]
            drpWe           => drpWe,            -- [out]
            drpUsrRst       => open,             -- [out]
            drpAddr         => drpAddr,          -- [out]
            drpDi           => drpDi,            -- [out]
            drpDo           => drpDo);           -- [in]

end architecture mapping;
