library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;
use surf.AxiLitePkg.all;
use surf.SsiPkg.all;

-- Notes:
-- Buffer size/segmentation:
-- 128 segments, 16 bytes per segment
-- Total segmented buffer (maximally): 128 × 16 = 2048 bytes (2 KiB).
--
-- Read during frame receive:
-- Not guarded currently so read during receive could happen leading to
-- partially updated frame. Should not be a problem in practice though.
-- Technically possible to hold off axis transmission until ongoing frame
-- receive is done. For new frame during ongoing axis transmission only
-- (simple) option seems to be to discard it.


entity EvrSdBuffer is
   generic (
      TPD_G               : time                    := 1 ns;
      RST_POLARITY_G      : sl                      := '1';  -- '1' for active HIGH reset, '0' for active LOW reset
      RST_ASYNC_G         : boolean                 := false;
      SYNTH_MODE_G        : string                  := "inferred";
      MEMORY_TYPE_G       : string                  := "block";
      COMMON_CLK_G        : boolean                 := false;  -- true if dataClk=axilClk
      DATA_BYTES_G        : positive range 1 to 256 := 16;  -- RAM word size/bytes per transmission
      RAM_ADDR_WIDTH_G    : positive range 1 to 256 := 7;  -- 2048 bytes maximally.
      -- AXI Stream Configurations
      INT_PIPE_STAGES_G   : natural                 := 1;
      PIPE_STAGES_G       : natural                 := 1;
      GEN_SYNC_FIFO_G     : boolean                 := false;
      FIFO_MEMORY_TYPE_G  : string                  := "block";
      FIFO_ADDR_WIDTH_G   : positive                := 9;
      AXI_STREAM_CONFIG_G : AxiStreamConfigType);
   port (
      -- Data to store in frame buffer (dataClk domain)
      dataClk         : in  sl;
      dataRst         : in  sl              := '0';
      dataValid       : in  sl              := '1';
      dataValue       : in  slv(8*DATA_BYTES_G-1 downto 0);
      dataSegIdx      : in  slv(6 downto 0) := (others => '0');  -- Segment sets where in the buffer to start the write
      dataFrameTxLast : in  sl              := '0';  -- Signal end of frame
      dataFrameRxLast : out sl              := '0';  -- Indicate currently at last word without delay
      dataFrameRxDone : out sl              := '0';  -- Asserted on end of frame (due to dataFrameTxLast or buffer full)
      dataRdTrig      : in  sl;  -- Readout trigger synchronous to dataClk
      -- AXI-Lite interface (axilClk domain)
      axilClk         : in  sl;
      axilRst         : in  sl;
      axilReadMaster  : in  AxiLiteReadMasterType;
      axilReadSlave   : out AxiLiteReadSlaveType;
      axilWriteMaster : in  AxiLiteWriteMasterType;
      axilWriteSlave  : out AxiLiteWriteSlaveType;
      axilRdTrig      : in  sl;  -- Readout trigger synchronous to axilClk
      -- AXI-Stream Interface (axisClk domain)
      axisClk         : in  sl;
      axisRst         : in  sl;
      axisMaster      : out AxiStreamMasterType;
      axisSlave       : in  AxiStreamSlaveType);
end entity EvrSdBuffer;

architecture rtl of EvrSdBuffer is

   -- One segment appears to be 16 byte. 
   constant SEG_BYTES_C : positive := 16;

   constant AXIS_CONFIG_C : AxiStreamConfigType := ssiAxiStreamConfig(
      dataBytes => DATA_BYTES_G,
      tKeepMode => TKEEP_FIXED_C,
      tUserMode => TUSER_FIRST_LAST_C,
      tDestBits => 0,
      tUserBits => 2,
      tIdBits   => 0);

   ------------------------------
   -- Stream clock domain signals
   ------------------------------
   signal ramRdData : slv(8*DATA_BYTES_G-1 downto 0);

   type DataTrigStateType is (
      IDLE_S,
      WAIT_S);

   type DataRegType is record
      ramWrEn         : sl;
      rdSetupDone     : sl;
      ramWrAddr       : slv(RAM_ADDR_WIDTH_G-1 downto 0);
      ramWrAddrNext   : slv(RAM_ADDR_WIDTH_G-1 downto 0);
      ramWrData       : slv(8*DATA_BYTES_G-1 downto 0);
      dataFrameTxLast : sl;
      dataFrameRxBusy : sl;
      dataFrameRxDone : sl;
      dataTrigState   : DataTrigStateType;
   end record;

   constant DATA_REG_INIT_C : DataRegType := (
      ramWrEn         => '0',
      rdSetupDone     => '0',
      ramWrAddr       => (others => '0'),
      ramWrAddrNext   => (others => '0'),
      ramWrData       => (others => '0'),
      dataFrameTxLast => '0',
      dataFrameRxBusy => '0',
      dataFrameRxDone => '0',
      dataTrigState   => IDLE_S);

   signal dataR   : DataRegType := DATA_REG_INIT_C;
   signal dataRin : DataRegType;

   --------------------------------
   -- AXI-Lite clock domain signals
   --------------------------------
   type AxisStateType is (
      IDLE_S,
      DONE_S,
      MOVE_S);

   type AxilRegType is record
      softTrig       : sl;
      rdReq          : sl;
      ramRdAddr      : slv(RAM_ADDR_WIDTH_G-1 downto 0);
      rdMoveDone     : sl;
      rdEn           : slv(2 downto 0);
      axilReadSlave  : AxiLiteReadSlaveType;
      axilWriteSlave : AxiLiteWriteSlaveType;
      txMaster       : AxiStreamMasterType;
      axisState      : AxisStateType;
      axisStateIdx   : slv(1 downto 0);
   end record;

   constant AXIL_REG_INIT_C : AxilRegType := (
      softTrig       => '0',
      rdReq          => '0',
      ramRdAddr      => (others => '0'),
      rdMoveDone     => '0',
      rdEn           => "000",
      axilReadSlave  => AXI_LITE_READ_SLAVE_INIT_C,
      axilWriteSlave => AXI_LITE_WRITE_SLAVE_INIT_C,
      txMaster       => axiStreamMasterInit(AXIS_CONFIG_C),
      axisState      => IDLE_S,
      axisStateIdx   => (others => '0'));

   signal axilR   : AxilRegType := AXIL_REG_INIT_C;
   signal axilRin : AxilRegType;

   signal axilRstSync : sl;
   signal dataRstSync : sl;

   signal rdSetupDoneSync     : sl;
   signal dataFrameRxBusySync : sl;
   signal rdMoveDoneSync      : sl;

   signal dataToAxilSyncIn  : slv(1 downto 0);
   signal dataToAxilSyncOut : slv(1 downto 0);
   signal axilToDataSyncIn  : slv(1 downto 0);
   signal axilToDataSyncOut : slv(1 downto 0);

   signal rdReqSync : sl;

   signal txSlave : AxiStreamSlaveType;

begin

   assert RAM_ADDR_WIDTH_G <= log2(2048 / DATA_BYTES_G)
                              report "RAM_ADDR_WIDTH_G must be smaller than log2(2048 / DATA_BYTES_G) to limit total buffer size to 2048 byte"
                              severity failure;

   assert (SEG_BYTES_C mod DATA_BYTES_G) = 0
      report "DATA_BYTES_G must divide segment size"
      severity failure;

   ----------------------
   -- Instantiate the RAM
   ----------------------

   GEN_XPM : if (SYNTH_MODE_G = "xpm") generate
      U_Ram : entity surf.SimpleDualPortRamXpm
         generic map (
            TPD_G          => TPD_G,
            RST_POLARITY_G => RST_POLARITY_G,
            COMMON_CLK_G   => COMMON_CLK_G,
            MEMORY_TYPE_G  => MEMORY_TYPE_G,
            READ_LATENCY_G => 2,
            DATA_WIDTH_G   => 8*DATA_BYTES_G,
            ADDR_WIDTH_G   => RAM_ADDR_WIDTH_G)
         port map (
            -- Port A
            clka   => dataClk,
            wea(0) => dataR.ramWrEn,
            addra  => dataR.ramWrAddr,
            dina   => dataR.ramWrData,
            -- Port B
            clkb   => axilClk,
            addrb  => axilR.ramRdAddr,
            doutb  => ramRdData);
   end generate;

   GEN_ALTERA : if (SYNTH_MODE_G = "altera_mf") generate
      U_Ram : entity surf.SimpleDualPortRamAlteraMf
         generic map (
            TPD_G          => TPD_G,
            RST_POLARITY_G => RST_POLARITY_G,
            COMMON_CLK_G   => COMMON_CLK_G,
            MEMORY_TYPE_G  => MEMORY_TYPE_G,
            READ_LATENCY_G => 2,
            DATA_WIDTH_G   => 8*DATA_BYTES_G,
            ADDR_WIDTH_G   => RAM_ADDR_WIDTH_G)
         port map (
            -- Port A
            clka   => dataClk,
            wea(0) => dataR.ramWrEn,
            addra  => dataR.ramWrAddr,
            dina   => dataR.ramWrData,
            -- Port B
            clkb   => axilClk,
            addrb  => axilR.ramRdAddr,
            doutb  => ramRdData);
   end generate;

   GEN_INFERRED : if (SYNTH_MODE_G = "inferred") generate
      U_Ram : entity surf.SimpleDualPortRam
         generic map (
            TPD_G          => TPD_G,
            RST_POLARITY_G => RST_POLARITY_G,
            RST_ASYNC_G    => RST_ASYNC_G,
            MEMORY_TYPE_G  => MEMORY_TYPE_G,
            DOB_REG_G      => true,
            DATA_WIDTH_G   => 8*DATA_BYTES_G,
            ADDR_WIDTH_G   => RAM_ADDR_WIDTH_G)
         port map (
            -- Port A
            clka  => dataClk,
            wea   => dataR.ramWrEn,
            addra => dataR.ramWrAddr,
            dina  => dataR.ramWrData,
            -- Port B
            clkb  => axilClk,
            addrb => axilR.ramRdAddr,
            doutb => ramRdData);
   end generate;

   ----------------------------
   -- Synchronize reset signals
   ----------------------------

   U_RstSync_axilRst : entity surf.RstSync
      generic map (
         TPD_G          => TPD_G,
         IN_POLARITY_G  => RST_POLARITY_G,
         OUT_POLARITY_G => RST_POLARITY_G)
      port map (
         clk      => dataClk,
         asyncRst => axilRst,
         syncRst  => axilRstSync);

   U_RstSync_dataRst : entity surf.RstSync
      generic map (
         TPD_G          => TPD_G,
         IN_POLARITY_G  => RST_POLARITY_G,
         OUT_POLARITY_G => RST_POLARITY_G)
      port map (
         clk      => axilClk,
         asyncRst => dataRst,
         syncRst  => dataRstSync);

   -----------------------------
   -- Data process (data inputs)
   -----------------------------

   dataComb : process (dataR, dataRst, axilRstSync, dataValid, dataValue, dataFrameTxLast,
                       rdReqSync, dataRdTrig, rdMoveDoneSync, dataSegIdx) is
      variable v          : DataRegType;
      variable addrOffset : integer;
   begin
      -- Latch the current value
      v := dataR;

      -- Reset strobes
      v.ramWrEn         := '0';
      v.dataFrameRxDone := '0';

      -- Register data value to help with making timing
      v.ramWrData       := dataValue;
      v.dataFrameTxLast := dataFrameTxLast;

      -- Check if last frame was the final frame or if the buffer is full.
      if (dataR.dataFrameTxLast = '1') or (dataR.ramWrAddr = 2**RAM_ADDR_WIDTH_G - 1) then
         v.ramWrAddr     := (others => '0');
         v.ramWrAddrNext := (others => '0');

         -- Signal frame receive done and new frame available for readout.
         -- The next write can actually proceed in the same cycle as this signal
         -- is asserted in.
         v.dataFrameRxDone := '1';

         -- Reset busy flag
         v.dataFrameRxBusy := '0';

      end if;

      -- Only write if data valid.
      if (dataValid = '1') then
         -- If first transmission of frame, start at the segment offset.
         -- One segment appears to be 16 byte. Do the arithmetic to cover case of
         -- different data width from the transceiver.
         if v.dataFrameRxBusy = '0' then
            addrOffset      := conv_integer(dataSegIdx) * SEG_BYTES_C / DATA_BYTES_G;
            v.ramWrAddrNext := toSlv(addrOffset, RAM_ADDR_WIDTH_G);
         end if;

         -- Set busy flag
         v.dataFrameRxBusy := '1';

         -- Strobe write enable
         v.ramWrEn := '1';

         -- Increment write address. Reference v, not r as this might have
         -- been reset by the frame end condition above.
         v.ramWrAddr     := v.ramWrAddrNext;  -- Mini-pipeline
         v.ramWrAddrNext := v.ramWrAddrNext + 1;

      end if;

      case dataR.dataTrigState is
         when IDLE_S =>
            -- Wait for readout request
            if (rdReqSync = '1') or (dataRdTrig = '1') then
               -- Assert setup done signal
               v.rdSetupDone   := '1';
               -- Wait until axil process done moving data
               v.dataTrigState := WAIT_S;
            end if;
         when WAIT_S =>
            -- Wait until the axil process completes readout
            if (rdMoveDoneSync = '1') then
               v.rdSetupDone := '0';
            end if;
            -- Only return to idle on once the move done signal is de-asserted
            -- again to avoid immediately transitioning to wait state again.
            if (v.rdSetupDone = '0') and (rdMoveDoneSync = '0') then
               v.dataTrigState := IDLE_S;
            end if;
      end case;


      -- Outputs
      dataFrameRxDone <= dataR.dataFrameRxDone;

      -- Indicate currently at last address without delay due to register
      if v.ramWrAddr = 2**RAM_ADDR_WIDTH_G - 1 then
         dataFrameRxLast <= '1';
      else
         dataFrameRxLast <= '0';
      end if;

      -- Synchronous Reset
      if (RST_ASYNC_G = false and dataRst = RST_POLARITY_G) or (axilRstSync = '1') then
         v := DATA_REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      dataRin <= v;

   end process;

   dataSeq : process (dataClk, dataRst) is
   begin
      if (RST_ASYNC_G) and (dataRst = RST_POLARITY_G) then
         dataR <= DATA_REG_INIT_C after TPD_G;
      elsif rising_edge(dataClk) then
         dataR <= dataRin after TPD_G;
      end if;
   end process;


   -------------------------------------------------------------
   -- Synchronization of signals between data/AXI-lite processes
   -------------------------------------------------------------

   -- Synchronize from data to axil process
   U_SyncVec_dataToAxil : entity surf.SynchronizerVector
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         WIDTH_G        => 2)
      port map (
         clk     => axilClk,
         dataIn  => dataToAxilSyncIn,
         dataOut => dataToAxilSyncOut);

   dataToAxilSyncIn(0) <= dataR.rdSetupDone;
   dataToAxilSyncIn(1) <= dataR.dataFrameRxBusy;
   rdSetupDoneSync     <= dataToAxilSyncOut(0);
   dataFrameRxBusySync <= dataToAxilSyncOut(1);

   -- Synchronize from axil to data process
   U_SyncVec_axilToData : entity surf.SynchronizerVector
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         WIDTH_G        => 2)
      port map (
         clk     => dataClk,
         dataIn  => axilToDataSyncIn,
         dataOut => axilToDataSyncOut);

   axilToDataSyncIn(0) <= axilR.rdReq;
   axilToDataSyncIn(1) <= axilR.rdMoveDone;
   rdReqSync           <= axilToDataSyncOut(0);
   rdMoveDoneSync      <= axilToDataSyncOut(1);

   -------------------------------
   -- Main AXI-Lite/Stream process
   -------------------------------

   axiComb : process (axilR, axilReadMaster, axilRst, dataRstSync, axilWriteMaster,
                      ramRdData, rdSetupDoneSync, dataFrameRxBusySync, txSlave,
                      axilRdTrig) is
      variable v      : AxilRegType;
      variable axilEp : AxiLiteEndpointType;
   begin
      -- Latch the current value
      v := axilR;

      -- Reset strobes
      v.softTrig := '0';

      ------------------------
      -- AXI-Lite Transactions
      ------------------------

      -- Determine the transaction type
      axiSlaveWaitTxn(axilEp, axilWriteMaster, axilReadMaster, v.axilWriteSlave, v.axilReadSlave);

      -- ADDR_WIDTH_G is restricted to maximally 32 so final address always
      -- fits in 32 bit register.
      axiSlaveRegisterR(axilEp, x"0", 0, axilR.axisStateIdx);
      axiSlaveRegisterR(axilEp, x"0", 8, dataFrameRxBusySync);
      axiSlaveRegisterR(axilEp, x"4", 0, toSlv(RAM_ADDR_WIDTH_G, 8));
      axiSlaveRegisterR(axilEp, x"4", 8, toSlv(DATA_BYTES_G, 8));
      axiSlaveRegister (axilEp, x"8", 0, v.softTrig);

      -- Close the transaction
      axiSlaveDefault(axilEp, v.axilWriteSlave, v.axilReadSlave, AXI_RESP_DECERR_C);

      ------------------------
      -- AXI-Stream
      ------------------------

      -- Update Shift Register.
      -- Required to match the read delay of the ram.
      v.rdEn(0) := '0';
      v.rdEn(1) := axilR.rdEn(0);
      v.rdEn(2) := axilR.rdEn(1);

      -- AXI Stream Flow Control
      if (txSlave.tReady = '1') then
         v.txMaster := axiStreamMasterInit(AXIS_CONFIG_C);
      end if;

      case axilR.axisState is
         ----------------------------------------------------------------------
         when IDLE_S =>
            v.axisStateIdx := "00";

            -- Check for trigger signals synchronous to axil clock
            if (v.softTrig = '1') or (axilRdTrig = '1') then
               -- Issue a read request, keep asserted until data process
               -- signals ready to make sure the data process caches it.
               v.rdReq := '1';
            end if;

            if (rdSetupDoneSync = '1') then
               -- Reset read address
               v.ramRdAddr := (others => '0');
               -- Reset read request signal in case it was set
               v.rdReq     := '0';

               -- Queue up the first read by writing to shift register
               v.rdEn(0)   := '1';
               -- Start moving data
               v.axisState := MOVE_S;
            end if;
         ----------------------------------------------------------------------
         when DONE_S =>
            v.axisStateIdx := "01";
            -- Signal done
            v.rdMoveDone   := '1';
            -- Wait until lowered, signaling that data process received move done
            -- and is ready for next trigger
            if (rdSetupDoneSync = '0') then
               -- Lower done signal and return to idle
               v.rdMoveDone := '0';
               v.axisState  := IDLE_S;
            end if;
         ----------------------------------------------------------------------
         when MOVE_S =>
            v.axisStateIdx := "10";

            -- Check if ready to move data
            if (v.txMaster.tValid = '0') and (axilR.rdEn = 0) then

               -- Send the data
               v.txMaster.tValid                           := '1';
               v.txMaster.tData(8*DATA_BYTES_G-1 downto 0) := ramRdData;

               -- Check for Start Of Frame (SOF)
               if (axilR.ramRdAddr = 0) then

                  -- Set the SOF bit
                  ssiSetUserSof(AXIS_CONFIG_C, v.txMaster, '1');

               end if;

               -- Check for end of buffer, i.e. the last address.
               if (axilR.ramRdAddr = 2**RAM_ADDR_WIDTH_G - 1) then

                  -- Set the EOF bit
                  v.txMaster.tLast := '1';

                  -- Transmission completed, move signal move done to data proc
                  v.axisState := DONE_S;

               else
                  -- Increment the read address
                  v.ramRdAddr := axilR.ramRdAddr + 1;
               end if;

            end if;
      ----------------------------------------------------------------------
      end case;

      -- Check for external data reset
      if (dataRstSync = '1') then
         -- Return to idle
         v.axisState := IDLE_S;
      end if;

      -- Check for change in address
      if (axilR.ramRdAddr /= v.ramRdAddr) then
         -- Queue up the next read by writing to shift register
         v.rdEn(0) := '1';
      end if;

      -- Outputs
      axilReadSlave  <= axilR.axilReadSlave;
      axilWriteSlave <= axilR.axilWriteSlave;

      -- Synchronous Reset
      if (RST_ASYNC_G = false and axilRst = RST_POLARITY_G) then
         v := AXIL_REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      axilRin <= v;

   end process;

   axiSeq : process (axilClk, axilRst) is
   begin
      if (RST_ASYNC_G) and (axilRst = RST_POLARITY_G) then
         axilR <= AXIL_REG_INIT_C after TPD_G;
      elsif rising_edge(axilClk) then
         axilR <= axilRin after TPD_G;
      end if;
   end process;

   -----------------------------------------------------------
   -- TX fifo for transition from AXI-Lite to AXI-Stream clock
   -----------------------------------------------------------

   TX_FIFO : entity surf.AxiStreamFifoV2
      generic map (
         -- General Configurations
         TPD_G               => TPD_G,
         RST_POLARITY_G      => RST_POLARITY_G,
         RST_ASYNC_G         => RST_ASYNC_G,
         INT_PIPE_STAGES_G   => INT_PIPE_STAGES_G,
         PIPE_STAGES_G       => PIPE_STAGES_G,
         SLAVE_READY_EN_G    => true,
         -- FIFO configurations
         SYNTH_MODE_G        => SYNTH_MODE_G,
         MEMORY_TYPE_G       => FIFO_MEMORY_TYPE_G,
         GEN_SYNC_FIFO_G     => GEN_SYNC_FIFO_G,
         FIFO_ADDR_WIDTH_G   => FIFO_ADDR_WIDTH_G,
         -- AXI Stream Port Configurations
         SLAVE_AXI_CONFIG_G  => AXIS_CONFIG_C,
         MASTER_AXI_CONFIG_G => AXI_STREAM_CONFIG_G)
      port map (
         -- Slave Port
         sAxisClk    => axilClk,
         sAxisRst    => axilRst,
         sAxisMaster => axilR.txMaster,
         sAxisSlave  => txSlave,
         -- Master Port
         mAxisClk    => axisClk,
         mAxisRst    => axisRst,
         mAxisMaster => axisMaster,
         mAxisSlave  => axisSlave);

end architecture rtl;
