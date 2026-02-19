-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Top Level Firmware Target
-------------------------------------------------------------------------------
-- This file is part of 'kek-lrsp-bpm'.
-- It is subject to the license terms in the LICENSE.txt file found in the
-- top-level directory of this distribution and at:
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
-- No part of 'kek-lrsp-bpm', including this file,
-- may be copied, modified, propagated, or distributed except according to
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;
use surf.AxiLitePkg.all;

library work;
use work.AppPkg.all;

library axi_soc_ultra_plus_core;
use axi_soc_ultra_plus_core.AxiSocUltraPlusPkg.all;

library unisim;
use unisim.vcomponents.all;

entity KekLrspBpmBt is
   generic (
      TPD_G        : time := 1 ns;
      BUILD_INFO_G : BuildInfoType);
   port (
      -- System Ports
      userLed     : out   slv(3 downto 0);
      -- Trigger Inputs
      irigTrigOut : inout sl;  -- Trigger input from 1PPS SMA (via schmitt trigger)
      irigCompOut : inout sl;  -- Trigger input from 1PPS SMA (via comparator)
      -- RF DATA CONVERTER Ports
      adcClkP     : in    slv(1 downto 0);
      adcClkN     : in    slv(1 downto 0);
      adcP        : in    slv(7 downto 0);
      adcN        : in    slv(7 downto 0);
      dacClkP     : in    slv(1 downto 0);
      dacClkN     : in    slv(1 downto 0);
      dacP        : out   slv(7 downto 0);
      dacN        : out   slv(7 downto 0);
      sysRefP     : in    sl;
      sysRefN     : in    sl;
      plClkP      : in    sl;
      plClkN      : in    sl;
      plSysRefP   : in    sl;
      plSysRefN   : in    sl;
      -- SYSMON Ports
      vPIn        : in    sl;
      vNIn        : in    sl;
      -- QSFP ports
      qsfpRefClkP : in    sl;           -- On dedicated GT ref clock pins
      qsfpRefClkN : in    sl;
      qsfpSysClkP : in    sl;           -- On ordinary clock pins
      qsfpSysClkN : in    sl;
      qsfpGtTxP   : out   slv(3 downto 0);
      qsfpGtTxN   : out   slv(3 downto 0);
      qsfpGtRxP   : in    slv(3 downto 0);
      qsfpGtRxN   : in    slv(3 downto 0)
      );
end KekLrspBpmBt;

architecture top_level of KekLrspBpmBt is

   constant HW_INDEX_C   : natural := 0;
   constant RFDC_INDEX_C : natural := 1;
   constant APP_INDEX_C  : natural := 2;
   constant GT_INDEX_C   : natural := 3;

   constant NUM_AXIL_MASTERS_C : positive := 4;

   constant AXIL_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL_MASTERS_C-1 downto 0) := genAxiLiteConfig(NUM_AXIL_MASTERS_C, APP_ADDR_OFFSET_C, 31, 28);

   signal dmaClk          : sl;
   signal dmaRst          : sl;
   signal dmaBuffGrpPause : slv(7 downto 0);
   signal dmaObMasters    : AxiStreamMasterArray(DMA_SIZE_C-1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);
   signal dmaObSlaves     : AxiStreamSlaveArray(DMA_SIZE_C-1 downto 0)  := (others => AXI_STREAM_SLAVE_FORCE_C);
   signal dmaIbMasters    : AxiStreamMasterArray(DMA_SIZE_C-1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);
   signal dmaIbSlaves     : AxiStreamSlaveArray(DMA_SIZE_C-1 downto 0)  := (others => AXI_STREAM_SLAVE_FORCE_C);

   signal axilClk         : sl;
   signal axilRst         : sl;
   signal axilWriteMaster : AxiLiteWriteMasterType;
   signal axilWriteSlave  : AxiLiteWriteSlaveType;
   signal axilReadMaster  : AxiLiteReadMasterType;
   signal axilReadSlave   : AxiLiteReadSlaveType;

   signal axilReadMasters  : AxiLiteReadMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
   signal axilReadSlaves   : AxiLiteReadSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0)  := (others => AXI_LITE_READ_SLAVE_EMPTY_DECERR_C);
   signal axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
   signal axilWriteSlaves  : AxiLiteWriteSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0) := (others => AXI_LITE_WRITE_SLAVE_EMPTY_DECERR_C);

   signal dspClk : sl;
   signal dspRst : sl;
   signal dspAdc : Slv256Array(3 downto 0);
   signal dspDac : Slv256Array(1 downto 0);

   signal qsfpRefClk     : sl;
   signal qsfpRefClkCopy : sl;

   signal qsfpSysClk : sl;

   signal xvcClk156 : sl;
   signal xvcRst156 : sl;

begin

   userLed(0) <= not(axilRst);
   userLed(1) <= not(dmaRst);
   userLed(2) <= not(dspRst);
   userLed(3) <= '1';

   -- This did not work. Not sure why and it's difficult to debug the debugging tool...
   -- TODO: Consider using a PLL (MMCM) for qsfpSysClk as well?
   -- U_XVC_PLL : entity surf.ClockManagerUltraScale
   --    generic map(
   --       TPD_G              => TPD_G,
   --       TYPE_G             => "MMCM",
   --       INPUT_BUFG_G       => true,
   --       FB_BUFG_G          => true,
   --       RST_IN_POLARITY_G  => '1',
   --       NUM_CLOCKS_G       => 1,
   --       -- MMCM attributes
   --       BANDWIDTH_G        => "OPTIMIZED",
   --       CLKIN_PERIOD_G     => 4.0,     -- 250MHz (Actually ignored in synthesis???)
   --       DIVCLK_DIVIDE_G    => 10,      -- 25.0MHz = 250MHz/10
   --       CLKFBOUT_MULT_F_G  => 48.4375,  -- 1210.9375MHz = 48.4375 x 25.0MHz (see DS925 for vco range)
   --       CLKOUT0_DIVIDE_F_G => 7.75)    -- 156.25MHz = 1210.9375MHz/7.75
   --    port map(
   --       -- Clock Input
   --       clkIn     => axilClk,  -- In this firmware axiClk should be 250MHz
   --       rstIn     => axilRst,
   --       -- Clock Outputs
   --       clkOut(0) => xvcClk156,
   --       -- Reset Outputs
   --       rstOut(0) => xvcRst156);

   -- MMCM won't take my CLKIN so use 156.25 available from oscillator on board
   xvcClk156 <= qsfpSysClk;
   xvcRst156 <= '0';  -- Simply set to zero (for testing only)

   -----------------------
   -- Common Platform Core
   -----------------------
   U_Core : entity axi_soc_ultra_plus_core.AxiSocUltraPlusCore
      generic map (
         TPD_G             => TPD_G,
         BUILD_INFO_G      => BUILD_INFO_G,
         EXT_AXIL_MASTER_G => false,
         DMA_SIZE_G        => DMA_SIZE_C)
      port map (
         ------------------------
         --  Top Level Interfaces
         ------------------------
         -- DSP Clock and Reset Monitoring
         dspClk          => dspClk,
         dspRst          => dspRst,
         -- AUX Clock and Reset
         auxClk          => axilClk,
         auxRst          => axilRst,
         -- DMA Interfaces  (dmaClk domain)
         dmaClk          => dmaClk,
         dmaRst          => dmaRst,
         dmaBuffGrpPause => dmaBuffGrpPause,
         dmaObMasters    => dmaObMasters,
         dmaObSlaves     => dmaObSlaves,
         dmaIbMasters    => dmaIbMasters,
         dmaIbSlaves     => dmaIbSlaves,
         -- Application AXI-Lite Interfaces [0x80000000:0xFFFFFFFF] (appClk domain)
         appClk          => axilClk,
         appRst          => axilRst,
         appReadMaster   => axilReadMaster,
         appReadSlave    => axilReadSlave,
         appWriteMaster  => axilWriteMaster,
         appWriteSlave   => axilWriteSlave,
         -- SYSMON Ports
         vPIn            => vPIn,
         vNIn            => vNIn);

   ---------------------
   -- AXI-Lite Crossbar
   ---------------------
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

   --------------------
   -- RF DATA CONVERTER
   --------------------
   U_RFDC : entity work.RfDataConverter
      generic map (
         TPD_G            => TPD_G,
         AXIL_BASE_ADDR_G => AXIL_CONFIG_C(RFDC_INDEX_C).baseAddr)
      port map (
         -- RF DATA CONVERTER Ports
         adcClkP         => adcClkP,
         adcClkN         => adcClkN,
         adcP            => adcP,
         adcN            => adcN,
         dacClkP         => dacClkP,
         dacClkN         => dacClkN,
         dacP            => dacP,
         dacN            => dacN,
         sysRefP         => sysRefP,
         sysRefN         => sysRefN,
         plClkP          => plClkP,
         plClkN          => plClkN,
         plSysRefP       => plSysRefP,
         plSysRefN       => plSysRefN,
         -- ADC/DAC Interface (dspClk domain)
         dspClk          => dspClk,
         dspRst          => dspRst,
         dspAdc          => dspAdc,
         dspDac          => dspDac,
         -- AXI-Lite Interface (axilClk domain)
         axilClk         => axilClk,
         axilRst         => axilRst,
         axilWriteMaster => axilWriteMasters(RFDC_INDEX_C),
         axilWriteSlave  => axilWriteSlaves(RFDC_INDEX_C),
         axilReadMaster  => axilReadMasters(RFDC_INDEX_C),
         axilReadSlave   => axilReadSlaves(RFDC_INDEX_C));

   -- GTY Transceiver reference clock
   U_qsfpRefClk : IBUFDS_GTE4           -- For US: GTE3, for US+: GTE4
      generic map (
         REFCLK_EN_TX_PATH  => '0',  -- Reserved. This attribute must always be set to 1'b0.
         REFCLK_HROW_CK_SEL => "00",    -- 2'b00: ODIV2 = O
         REFCLK_ICNTL_RX    => "00")
      port map (
         I     => qsfpRefClkP,
         IB    => qsfpRefClkN,
         CEB   => '0',                  -- Active low clock enable signal
         ODIV2 => qsfpRefClkCopy,
         O     => qsfpRefClk);

   -- Transceiver reference clock. This should always be active and stable,
   -- which it should be as the input is referenced to a free running
   -- oscillator on the RFSoC 4x2 board (IC32).
   U_qsfpSysClk : IBUFDS
      port map (
         I  => qsfpSysClkP,
         IB => qsfpSysClkN,
         O  => qsfpSysClk);

   U_EvrGty : entity work.EvrGty
      generic map(
         TPD_G              => TPD_G,
         STABLE_CLK_F_HZ    => 156250000,  -- 156.250 MHz
         TX_MIRROR_ENABLE_G => false
         )
      port map(
         stableClk       => qsfpSysClk,
         stableRst       => '0',
         resetGt         => axilRst,
         gtRefClk        => qsfpRefClk,
         evrGtTxP        => qsfpGtTxP(0),
         evrGtTxN        => qsfpGtTxN(0),
         evrGtRxP        => qsfpGtRxP(0),
         evrGtRxN        => qsfpGtRxN(0),
         evrTxResetAsync => '0',
         evrTxResetDone  => open,
         evrTxUsrClk     => open,
         evrRxResetAsync => '0',
         evrRxResetDone  => open,
         evrRxUsrClk     => open,
         axilClk         => axilClk,
         axilRst         => axilRst,
         axilReadMaster  => axilReadMasters(GT_INDEX_C),
         axilReadSlave   => axilReadSlaves(GT_INDEX_C),
         axilWriteMaster => axilWriteMasters(GT_INDEX_C),
         axilWriteSlave  => axilWriteSlaves(GT_INDEX_C)
         );

   --------------
   -- Application
   --------------
   U_App : entity work.Application
      generic map (
         TPD_G            => TPD_G,
         AXIL_BASE_ADDR_G => AXIL_CONFIG_C(APP_INDEX_C).baseAddr)
      port map (
         -- DMA Interface (dmaClk domain)
         dmaClk          => dmaClk,
         dmaRst          => dmaRst,
         dmaIbMaster     => dmaIbMasters(0),
         dmaIbSlave      => dmaIbSlaves(0),
         -- Trigger Inputs
         trigsIn(0)      => irigTrigOut,
         trigsIn(1)      => irigCompOut,
         -- ADC/DAC Interface (dspClk domain)
         dspClk          => dspClk,
         dspRst          => dspRst,
         dspAdc          => dspAdc,
         dspDac          => dspDac,
         -- AXI-Lite Interface (axilClk domain)
         axilClk         => axilClk,
         axilRst         => axilRst,
         axilWriteMaster => axilWriteMasters(APP_INDEX_C),
         axilWriteSlave  => axilWriteSlaves(APP_INDEX_C),
         axilReadMaster  => axilReadMasters(APP_INDEX_C),
         axilReadSlave   => axilReadSlaves(APP_INDEX_C));

   ----------------------
   --- Loopback Debugging
   ----------------------
   dmaIbMasters(1) <= dmaObMasters(1);
   dmaObSlaves(1)  <= dmaIbSlaves(1);

   -------------
   -- XVC Module
   -------------
   U_XVC : entity surf.DmaXvcWrapper
      generic map (
         TPD_G             => TPD_G,
         DMA_AXIS_CONFIG_G => DMA_AXIS_CONFIG_C)
      port map (
         -- 156.25MHz XVC Clock/Reset (xvcClk156 domain)
         xvcClk156   => xvcClk156,
         xvcRst156   => xvcRst156,
         -- DMA Interface (dmaClk domain)
         dmaClk      => dmaClk,
         dmaRst      => dmaRst,
         dmaObMaster => dmaObMasters(2),
         dmaObSlave  => dmaObSlaves(2),
         dmaIbMaster => dmaIbMasters(2),
         dmaIbSlave  => dmaIbSlaves(2));

end top_level;
