-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Application Module
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
use surf.SsiPkg.all;

library work;
use work.AppPkg.all;

library axi_soc_ultra_plus_core;
use axi_soc_ultra_plus_core.AxiSocUltraPlusPkg.all;

entity Application is
   generic (
      TPD_G            : time := 1 ns;
      AXIL_BASE_ADDR_G : slv(31 downto 0));
   port (
      -- DMA Interface (dmaClk domain)
      dmaClk          : in  sl;
      dmaRst          : in  sl;
      dmaIbMaster     : out AxiStreamMasterType;
      dmaIbSlave      : in  AxiStreamSlaveType;
      -- ADC/DAC Interface (dspClk domain)
      dspClk          : in  sl;
      dspRst          : in  sl;
      dspAdc          : in  Slv256Array(3 downto 0);
      dspDac          : out Slv256Array(1 downto 0);
      -- AXI-Lite Interface (axilClk domain)
      axilClk         : in  sl;
      axilRst         : in  sl;
      axilWriteMaster : in  AxiLiteWriteMasterType;
      axilWriteSlave  : out AxiLiteWriteSlaveType;
      axilReadMaster  : in  AxiLiteReadMasterType;
      axilReadSlave   : out AxiLiteReadSlaveType);
end Application;

architecture mapping of Application is

   constant NUM_ADC_CH_C          : positive := 4;
   constant NUM_DAC_CH_C          : positive := 2;
   constant RAM_ADDR_WIDTH_C      : positive := 10;
   constant RAM_ADDR_WIDTH_LIVE_C : positive := 10;

   constant RING_INDEX_LIVE_C    : natural := 0; -- Used for axil and axis!
   constant RING_INDEX_C         : natural := 1; -- Used for axil and axis!
   constant DAC_SIG_INDEX_C      : natural := 2;
   constant READOUT_CTRL_INDEX_C : natural := 3;
   constant NUM_AXIL_MASTERS_C   : natural := 4;

   constant AXIL_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL_MASTERS_C-1 downto 0) := genAxiLiteConfig(NUM_AXIL_MASTERS_C, AXIL_BASE_ADDR_G, 28, 24);

   signal axilReadMasters  : AxiLiteReadMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
   signal axilReadSlaves   : AxiLiteReadSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0)  := (others => AXI_LITE_READ_SLAVE_EMPTY_DECERR_C);
   signal axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
   signal axilWriteSlaves  : AxiLiteWriteSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0) := (others => AXI_LITE_WRITE_SLAVE_EMPTY_DECERR_C);

   -- Axi stream for ring buffers
   signal axisMasters : AxiStreamMasterArray(1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);
   signal axisSlaves  : AxiStreamSlaveArray(1 downto 0)  := (others => AXI_STREAM_SLAVE_FORCE_C);

   signal adc      : Slv256Array(3 downto 0) := (others => (others => '0'));
   signal dac      : Slv256Array(1 downto 0) := (others => (others => '0'));
   signal loopback : Slv256Array(1 downto 0) := (others => (others => '0'));

   signal ringBufTrig : sl;

begin

   process(dspClk)
   begin
      -- Help with making timing
      if rising_edge(dspClk) then
         adc    <= dspAdc after TPD_G;
         dspDac <= dac    after TPD_G;
      end if;
   end process;

   -- Loopback
   loopback <= adc(1 downto 0);

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

   -- Mux axi streams from both ring buffers
   U_Mux : entity surf.AxiStreamMux
      generic map (
         TPD_G         => TPD_G,
         NUM_SLAVES_G  => 2,
         MODE_G        => "PASSTHROUGH",
         PIPE_STAGES_G => 1)
      port map (
         -- Clock and reset
         axisClk      => dmaClk,
         axisRst      => dmaRst,
         -- Slaves
         sAxisMasters => axisMasters,
         sAxisSlaves  => axisSlaves,
         -- Master
         mAxisMaster  => dmaIbMaster,
         mAxisSlave   => dmaIbSlave);

   U_ReadoutCtrl : entity work.ReadoutCtrl
      generic map(TPD_G => TPD_G)
      port map(
         -- Trigger Ports
         trigIn          => '0', -- TODO: PUT TRIGGER!!!
         ringBufTrigOut  => ringBufTrig,
         -- DSP Interface
         dspClk          => dspClk,
         dspRst          => dspRst,
         -- No way to use those for now. Could also use delays directly in RFDC?
         -- fineDelay       => '0',
         -- coarseDelay     => '0',
         -- AXI-Lite Interface (axilClk domain)
         axilClk         => axilClk,
         axilRst         => axilRst,
         axilReadMaster  => axilReadMasters(READOUT_CTRL_INDEX_C),
         axilReadSlave   => axilReadSlaves(READOUT_CTRL_INDEX_C),
         axilWriteMaster => axilWriteMasters(READOUT_CTRL_INDEX_C),
         axilWriteSlave  => axilWriteSlaves(READOUT_CTRL_INDEX_C)
         );

   U_AppRingBuffer : entity axi_soc_ultra_plus_core.AppRingBuffer
      generic map (
         TPD_G                  => TPD_G,
         EN_ADC_BUFF_G          => true,
         EN_DAC_BUFF_G          => false,  -- Don't need DACs here
         NUM_ADC_CH_G           => NUM_ADC_CH_C,
         ADC_SAMPLE_PER_CYCLE_G => SAMPLE_PER_CYCLE_C,
         DAC_SAMPLE_PER_CYCLE_G => SAMPLE_PER_CYCLE_C,
         RAM_ADDR_WIDTH_G       => RAM_ADDR_WIDTH_C,
         AXIL_BASE_ADDR_G       => AXIL_CONFIG_C(RING_INDEX_C).baseAddr,
         -- Ensure no overlap between routes for different buffers!
         ADC_TDEST_ROUTES_G     => (
            0                   => x"04",
            1                   => x"05",
            2                   => x"06",
            3                   => x"07",
            others              => x"FF")
         )
      port map (
         -- DMA Interface (dmaClk domain)
         dmaClk          => dmaClk,
         dmaRst          => dmaRst,
         dmaIbMaster     => axisMasters(RING_INDEX_C),
         dmaIbSlave      => axisSlaves(RING_INDEX_C),
         -- ADC/DAC Interface (dspClk domain)
         dspClk          => dspClk,
         dspRst          => dspRst,
         dspAdc0         => adc(0),
         dspAdc1         => adc(1),
         dspAdc2         => adc(2),
         dspAdc3         => adc(3),
         -- AXI-Lite Interface (axilClk domain)
         axilClk         => axilClk,
         axilRst         => axilRst,
         axilReadMaster  => axilReadMasters(RING_INDEX_C),
         axilReadSlave   => axilReadSlaves(RING_INDEX_C),
         axilWriteMaster => axilWriteMasters(RING_INDEX_C),
         axilWriteSlave  => axilWriteSlaves(RING_INDEX_C),
         -- Hardware trigger
         extTrigIn       => ringBufTrig);


   U_AppRingBufferLive : entity axi_soc_ultra_plus_core.AppRingBuffer
      generic map (
         TPD_G                  => TPD_G,
         EN_ADC_BUFF_G          => true,
         EN_DAC_BUFF_G          => true,
         NUM_ADC_CH_G           => NUM_ADC_CH_C,
         NUM_DAC_CH_G           => NUM_DAC_CH_C,
         ADC_SAMPLE_PER_CYCLE_G => SAMPLE_PER_CYCLE_C,
         DAC_SAMPLE_PER_CYCLE_G => SAMPLE_PER_CYCLE_C,
         RAM_ADDR_WIDTH_G       => RAM_ADDR_WIDTH_LIVE_C,
         AXIL_BASE_ADDR_G       => AXIL_CONFIG_C(RING_INDEX_LIVE_C).baseAddr,
         -- Ensure no overlap between routes for different buffers!
         ADC_TDEST_ROUTES_G     => (
            0                   => x"00",
            1                   => x"01",
            2                   => x"02",
            3                   => x"03",
            others              => x"FF"),
         DAC_TDEST_ROUTES_G     => (
            0                   => x"10",
            1                   => x"11",
            others              => x"FF"))
      port map (
         -- DMA Interface (dmaClk domain)
         dmaClk          => dmaClk,
         dmaRst          => dmaRst,
         dmaIbMaster     => axisMasters(RING_INDEX_LIVE_C),
         dmaIbSlave      => axisSlaves(RING_INDEX_LIVE_C),
         -- ADC/DAC Interface (dspClk domain)
         dspClk          => dspClk,
         dspRst          => dspRst,
         dspAdc0         => adc(0),
         dspAdc1         => adc(1),
         dspAdc2         => adc(2),
         dspAdc3         => adc(3),
         dspDac0         => dac(0),
         dspDac1         => dac(1),
         -- AXI-Lite Interface (axilClk domain)
         axilClk         => axilClk,
         axilRst         => axilRst,
         axilReadMaster  => axilReadMasters(RING_INDEX_LIVE_C),
         axilReadSlave   => axilReadSlaves(RING_INDEX_LIVE_C),
         axilWriteMaster => axilWriteMasters(RING_INDEX_LIVE_C),
         axilWriteSlave  => axilWriteSlaves(RING_INDEX_LIVE_C));

   U_DacSigGen : entity axi_soc_ultra_plus_core.SigGen
      generic map (
         TPD_G              => TPD_G,
         NUM_CH_G           => NUM_DAC_CH_C,
         RAM_ADDR_WIDTH_G   => RAM_ADDR_WIDTH_LIVE_C,
         SAMPLE_PER_CYCLE_G => SAMPLE_PER_CYCLE_C,
         AXIL_BASE_ADDR_G   => AXIL_CONFIG_C(DAC_SIG_INDEX_C).baseAddr)
      port map (
         -- DAC Interface (dspClk domain)
         dspClk          => dspClk,
         dspRst          => dspRst,
         dspDacIn0       => loopback(0),
         dspDacIn1       => loopback(1),
         dspDacOut0      => dac(0),
         dspDacOut1      => dac(1),
         -- AXI-Lite Interface (axilClk domain)
         axilClk         => axilClk,
         axilRst         => axilRst,
         axilReadMaster  => axilReadMasters(DAC_SIG_INDEX_C),
         axilReadSlave   => axilReadSlaves(DAC_SIG_INDEX_C),
         axilWriteMaster => axilWriteMasters(DAC_SIG_INDEX_C),
         axilWriteSlave  => axilWriteSlaves(DAC_SIG_INDEX_C));

end mapping;
