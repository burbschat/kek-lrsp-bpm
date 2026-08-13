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
      -- Trigger Inputs
      trigsIn         : in  slv(1 downto 0);
      -- ADC/DAC Interface (dspClk domain)
      dspClk          : in  sl;
      dspRst          : in  sl;
      dspAdc          : in  Slv256Array(3 downto 0);
      dspDac          : out Slv256Array(1 downto 0);
      -- Serial from transceiver
      usrClk          : in  sl;  -- User clock (rx data interface syncrhonous to this clock)
      data            : in  slv(15 downto 0);
      gtyReady        : in  sl;  -- Held low until GTY ready (running and aligned)
      dataK           : in  slv(1 downto 0);
      dispErr         : in  slv(1 downto 0);
      decErr          : in  slv(1 downto 0);
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
   constant RAM_ADDR_WIDTH_C      : positive := 8;
   constant RAM_ADDR_WIDTH_LIVE_C : positive := 10;

   constant RING_INDEX_LIVE_C    : natural := 0;  -- Used for axil and axis!
   constant RING_INDEX_C         : natural := 1;  -- Used for axil and axis!
   constant DAC_SIG_INDEX_C      : natural := 2;
   constant READOUT_CTRL_INDEX_C : natural := 3;
   constant EVR_DEC_REG_INDEX_C  : natural := 4;
   constant NUM_AXIL_MASTERS_C   : natural := 5;

   constant NUM_AXIS_SLAVES_C : natural := 2;
   -- For EVR metadata in separate stream for testing
   -- constant NUM_AXIS_SLAVES_C : natural := 3;
   -- constant EVR_SD_INDEX_C : natural := 2;

   constant AXIS_RING_TDEST_C : slv(7 downto 0) := x"04";

   constant METAMUX_NUM_AXIS_SLAVES_C : natural := 2;  -- Data stream (ring buffer) and meatdata stream
   constant METAMUX_META_INDEX_C      : natural := 0;
   constant METAMUX_RING_INDEX_C      : natural := 1;

   constant AXIL_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL_MASTERS_C-1 downto 0) := genAxiLiteConfig(NUM_AXIL_MASTERS_C, AXIL_BASE_ADDR_G, 28, 24);

   signal axilReadMasters  : AxiLiteReadMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
   signal axilReadSlaves   : AxiLiteReadSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0)  := (others => AXI_LITE_READ_SLAVE_EMPTY_DECERR_C);
   signal axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
   signal axilWriteSlaves  : AxiLiteWriteSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0) := (others => AXI_LITE_WRITE_SLAVE_EMPTY_DECERR_C);

   -- Axi stream for ring buffers
   signal axisMasters : AxiStreamMasterArray(NUM_AXIS_SLAVES_C-1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);
   signal axisSlaves  : AxiStreamSlaveArray(NUM_AXIS_SLAVES_C-1 downto 0)  := (others => AXI_STREAM_SLAVE_FORCE_C);

   -- Axi stream signals for merging with metadata stream
   signal axisMastersMetamux : AxiStreamMasterArray(METAMUX_NUM_AXIS_SLAVES_C-1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);
   signal axisSlavesMetamux  : AxiStreamSlaveArray(METAMUX_NUM_AXIS_SLAVES_C-1 downto 0)  := (others => AXI_STREAM_SLAVE_FORCE_C);
   signal axisMasterMetamux  : AxiStreamMasterType                                        := AXI_STREAM_MASTER_INIT_C;
   signal axisSlaveMetamux   : AxiStreamSlaveType                                         := AXI_STREAM_SLAVE_FORCE_C;

   -- Stick the batched stream into another mux to set tdest which gets stripped
   -- by the batcher (only one stream but must be array type for the mux).
   signal axisMastersNodest : AxiStreamMasterArray(0 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);
   signal axisSlavesNodest  : AxiStreamSlaveArray(0 downto 0)  := (others => AXI_STREAM_SLAVE_FORCE_C);

   signal adc      : Slv256Array(3 downto 0) := (others => (others => '0'));
   signal dac      : Slv256Array(1 downto 0) := (others => (others => '0'));
   signal loopback : Slv256Array(1 downto 0) := (others => (others => '0'));

   signal adcInterleaved : slv(NUM_ADC_CH_C*256 - 1 downto 0) := (others => '0');

   signal ringBufTrig : sl;

   constant EVR_N_TRGS_C : integer := 1;
   signal evrTrgs        : slv(EVR_N_TRGS_C - 1 downto 0);

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

   -- Mux AXI streams from both ring buffers
   U_Mux : entity surf.AxiStreamMux
      generic map (
         TPD_G         => TPD_G,
         NUM_SLAVES_G  => NUM_AXIS_SLAVES_C,
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


   -- Mux AXI streams from ring buffer (not live one) with metadata to create
   -- input stream for the batcher. No reason to put TDEST here as the batcher
   -- strips them anyways.
   U_MuxMeta : entity surf.AxiStreamMux
      generic map (
         TPD_G         => TPD_G,
         NUM_SLAVES_G  => METAMUX_NUM_AXIS_SLAVES_C,
         MODE_G        => "PASSTHROUGH",
         PIPE_STAGES_G => 1)
      port map (
         -- Clock and reset
         axisClk      => dmaClk,
         axisRst      => dmaRst,
         -- Slaves
         sAxisMasters => axisMastersMetamux,
         sAxisSlaves  => axisSlavesMetamux,
         -- Master
         mAxisMaster  => axisMasterMetamux,
         mAxisSlave   => axisSlaveMetamux);

   -- Use mux simply to stick on the correct TDEST lost during batching.
   -- Is there a smarter way to do this? Driving the tdest signal directly should
   -- work but then one has to tear apart the records...
   -- Must use separate mux as the existing one shall remain in PASSTHROUGH to keep
   -- tdest from the other (live) buffers.
   -- Maybe mux is fine, perhaps I want to add another batched stream later? (maybe not)
   U_MuxMetaSetDest : entity surf.AxiStreamMux
      generic map (
         TPD_G          => TPD_G,
         NUM_SLAVES_G   => 1,
         MODE_G         => "ROUTED",
         TDEST_ROUTES_G => (
            0           => AXIS_RING_TDEST_C
            ),
         PIPE_STAGES_G  => 1)
      port map (
         -- Clock and reset
         axisClk      => dmaClk,
         axisRst      => dmaRst,
         -- Slaves
         sAxisMasters => axisMastersNodest,
         sAxisSlaves  => axisSlavesNodest,
         -- Master
         mAxisMaster  => axisMasters(RING_INDEX_C),
         mAxisSlave   => axisSlaves(RING_INDEX_C));

   -- Consider testing with AxiStreamBatcherAxil to mess with the settings if
   -- the below does not work.
   -- TODO: Just use the axil version because why not.
   AxiStreamBatcher_inst : entity surf.AxiStreamBatcher
      generic map(
         TPD_G                        => TPD_G,
         VERSION_G                    => 2,
         MAX_NUMBER_SUB_FRAMES_G      => 2,  -- Only need header + one data frame
         -- Must fit full buffer (if address width=8: 2**8 * 16 samples/cycle * 4
         -- channels * 2 byte/sample = 32768) + maximum shared data width = 2048
         -- byte.
         SUPER_FRAME_BYTE_THRESHOLD_G => 65536,  -- 2**16 suffices if address width is 8
         -- Might want to make this longer depending on whether shot ID is distributed
         -- before or after each shot.
         -- If DBSD frame buffer is empty, it will ignore a trigger. In this case
         -- data is held off by this count, so probably want to keep this small.
         -- Alternative would be to configure the buffer to always dump it
         -- complete contents. TODO: Requires PR to upstream surf.
         MAX_CLK_GAP_G                => 32,
         AXIS_CONFIG_G                => DMA_AXIS_CONFIG_C
         )
      port map(
         axisClk     => dmaClk,
         axisRst     => dmaRst,
         forceTerm   => '0',  -- Could use this to signal that a frame is complete and transmission should be terminated
         idle        => open,           -- Indicates if in idle
         -- Slave slot (stream input)
         sAxisMaster => axisMasterMetamux,
         sAxisSlave  => axisSlaveMetamux,
         -- Master slot (stream output)
         mAxisMaster => axisMastersNodest(0),
         mAxisSlave  => axisSlavesNodest(0)
         );


   -- Event receiver decoding
   U_EvrDecoder : entity work.EvrDecoder
      generic map(
         TPD_G            => TPD_G,
         SYNTH_MODE_G     => "xpm",
         N_TRGS_G         => EVR_N_TRGS_C,
         AXIL_BASE_ADDR_G => AXIL_CONFIG_C(EVR_DEC_REG_INDEX_C).baseAddr
         )
      port map(
         -- Serial data input
         clk     => usrClk,
         data    => data,
         dataK   => dataK,
         dispErr => dispErr,
         decErr  => decErr,
         rst     => not gtyReady,  -- Keep in reset until data valid (forces reset while GTY resetting)

         -- Trigger outputs
         trgs => evrTrgs,

         -- Trigger to readout most recent received shared data via AXI stream
         sdReadoutTrig => ringBufTrig,

         -- AXI-Stream Interface (axisClk domain)
         axisClk    => dmaClk,
         axisRst    => dmaRst,
         axisMaster => axisMastersMetamux(METAMUX_META_INDEX_C),
         axisSlave  => axisSlavesMetamux(METAMUX_META_INDEX_C),

         -- AXI-Lite register interface
         axilClk         => axilClk,
         axilRst         => axilRst,
         axilReadMaster  => axilReadMasters(EVR_DEC_REG_INDEX_C),
         axilReadSlave   => axilReadSlaves(EVR_DEC_REG_INDEX_C),
         axilWriteMaster => axilWriteMasters(EVR_DEC_REG_INDEX_C),
         axilWriteSlave  => axilWriteSlaves(EVR_DEC_REG_INDEX_C)
         );

   -- ADC trigger and readout control
   U_ReadoutCtrl : entity work.ReadoutCtrl
      generic map(TPD_G       => TPD_G,
                  NUM_TRIGS_G => 3)
      port map(
         -- Trigger Ports
         trigsIn         => evrTrgs(0) & trigsIn,
         trigOut         => ringBufTrig,
         -- DSP Interface
         dspClk          => dspClk,
         dspRst          => dspRst,
         -- AXI-Lite Interface (axilClk domain)
         axilClk         => axilClk,
         axilRst         => axilRst,
         axilReadMaster  => axilReadMasters(READOUT_CTRL_INDEX_C),
         axilReadSlave   => axilReadSlaves(READOUT_CTRL_INDEX_C),
         axilWriteMaster => axilWriteMasters(READOUT_CTRL_INDEX_C),
         axilWriteSlave  => axilWriteSlaves(READOUT_CTRL_INDEX_C)
         );

   -- Interleave samples into a single stream as an easy way to ensure
   -- synchronization between all four channels. This uses a maximally wide
   -- axis data bus and thus only works with up to four channels. For more
   -- channels, a different solution (e.g. frame headers) will be required.
   interleave_map : process (adc) is
   begin
      for idx in 0 to (256/16)-1 loop
         for ch in 0 to 3 loop
            adcInterleaved(idx*4*16+(ch*16+15) downto idx*4*16+(ch*16)) <= adc(ch)(idx*16+15 downto idx*16);
         end loop;
      end loop;
   end process interleave_map;

   -- TODO: IMO better to just use a AppRingBufferEngine directly.
   U_AppRingBuffer : entity axi_soc_ultra_plus_core.AppRingBuffer
      generic map (
         TPD_G                  => TPD_G,
         EN_ADC_BUFF_G          => true,
         EN_DAC_BUFF_G          => false,  -- Don't need DACs here
         NUM_ADC_CH_G           => 1,  -- Only one as interleaved into one stream
         ADC_SAMPLE_PER_CYCLE_G => SAMPLE_PER_CYCLE_C * 4,  -- Four times as many due to interleaving
         DAC_SAMPLE_PER_CYCLE_G => SAMPLE_PER_CYCLE_C,
         RAM_ADDR_WIDTH_G       => RAM_ADDR_WIDTH_C,
         AXIL_BASE_ADDR_G       => AXIL_CONFIG_C(RING_INDEX_C).baseAddr,
         -- Ensure no overlap between routes for different buffers!
         ADC_TDEST_ROUTES_G     => (
            0                   => AXIS_RING_TDEST_C,
            others              => x"FF")
         )
      port map (
         -- DMA Interface (dmaClk domain)
         dmaClk          => dmaClk,
         dmaRst          => dmaRst,
         dmaIbMaster     => axisMastersMetamux(METAMUX_RING_INDEX_C),
         dmaIbSlave      => axisSlavesMetamux(METAMUX_RING_INDEX_C),
         -- ADC/DAC Interface (dspClk domain)
         dspClk          => dspClk,
         dspRst          => dspRst,
         dspAdc0         => adcInterleaved,
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
