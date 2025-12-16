# -----------------------------------------------------------------------------
# This file is part of the 'kek-lrsp-bpm'. It is subject to
# the license terms in the LICENSE.txt file found in the top-level directory
# of this distribution and at:
#    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
# No part of the 'kek-lrsp-bpm', including this file, may be
# copied, modified, propagated, or distributed except according to the terms
# contained in the LICENSE.txt file.
# -----------------------------------------------------------------------------

import time

import rogue
import rogue.interfaces.stream as stream
import rogue.utilities.fileio
import rogue.hardware.axi
import rogue.interfaces.memory

import pyrogue as pr
import pyrogue.protocols
import pyrogue.utilities.fileio
import pyrogue.utilities.prbs

import kek_lrsp_bpm as rfsoc
import axi_soc_ultra_plus_core.rfsoc_utility as rfsoc_utility
import axi_soc_ultra_plus_core.hardware.RealDigitalRfSoC4x2 as rfsoc_hw
import axi_soc_ultra_plus_core as soc_core

rogue.Version.minVersion("6.5.0")


class Root(pr.Root):
    def __init__(
        self,
        ip="10.0.0.10",  # ETH Host Name (or IP address)
        top_level="",
        defaultFile="",
        lmkConfig="config/lmk/HexRegisterValues_CLKin0-125MHz_CLKin1-10MHz.txt",
        lmxConfig="config/lmx/HexRegisterValues.txt",
        signalMapsIndexFile="config/SignalMaps/SignalMapsIndex.json",
        sampleRate=5.0e9,  # Units of Hz, depends on PLL config
        zmqSrvPort=9099,  # Set to zero if dynamic (instead of static)
        **kwargs,
    ):
        super().__init__(timeout=5.0, **kwargs)

        #################################################################

        self.zmqServer = pyrogue.interfaces.ZmqServer(root=self, addr="127.0.0.1", port=zmqSrvPort)
        self.addInterface(self.zmqServer)

        #################################################################

        # Local Variables
        self.top_level = top_level
        if self.top_level != "":
            self.defaultFile = f"{top_level}/{defaultFile}"
            self.lmkConfig = f"{top_level}/{lmkConfig}"
            self.lmxConfig = f"{top_level}/{lmxConfig}"
            self.signalMapsIndexFile = f"{top_level}/{signalMapsIndexFile}"
        else:
            self.defaultFile = defaultFile
            self.lmkConfig = lmkConfig
            self.lmxConfig = lmxConfig
            self.signalMapsIndexFile = signalMapsIndexFile

        # File writer
        self.dataWriter = pr.utilities.fileio.StreamWriter(name="DataWriter")
        self.add(self.dataWriter)

        ##################################################################################
        ##                              Register Access
        ##################################################################################

        if ip != None:
            # Check if we can ping the device and TCP socket not open
            soc_core.connectionTest(ip)
            # Start a TCP Bridge Client, Connect remote server at 'ethReg' ports 9000 & 9001.
            self.memMap = rogue.interfaces.memory.TcpClient(ip, 9000)
        else:
            self.memMap = rogue.hardware.axi.AxiMemMap("/dev/axi_memory_map")

        # Add RfSoC4x2 PS hardware control
        self.add(
            rfsoc_hw.Hardware(
                memBase=self.memMap,
            )
        )

        # Add the RFDC API interface
        self.memRfdc = rogue.interfaces.memory.TcpClient(ip, 9002)
        self.add(
            rfsoc_utility.Rfdc(
                memBase=self.memRfdc,
            )
        )

        # Added the RFSoC device
        self.add(
            rfsoc.RFSoC(
                memBase=self.memMap,
                offset=0x04_0000_0000,  # Full 40-bit address space
                sampleRate=sampleRate,
                expand=True,
            )
        )

        ##################################################################################
        ##                              Data Path
        ##################################################################################

        # Create rogue stream arrays
        if ip != None:
            self.ringBufferAdcLive = [stream.TcpClient(ip, 10000 + 2 * (i + 0)) for i in range(4)]
            self.ringBufferDacLive = [stream.TcpClient(ip, 10000 + 2 * (i + 16)) for i in range(2)]
            self.ringBufferAdc = stream.TcpClient(ip, 10000 + 2 * (0 + 4))  # No DACs required here, interleaved into one stream
        else:
            self.ringBufferAdcLive = [rogue.hardware.axi.AxiStreamDma("/dev/axi_stream_dma_0", i + 0, True) for i in range(4)]
            self.ringBufferDacLive = [rogue.hardware.axi.AxiStreamDma("/dev/axi_stream_dma_0", 16 + i, True) for i in range(2)]
            self.ringBufferAdc = rogue.hardware.axi.AxiStreamDma("/dev/axi_stream_dma_0", 0 + 4, True)  # No DACs required here, interleaved into one stream
        self.adcLiveDropFifo = [pr.interfaces.stream.Fifo(name=f"AdcLiveDropFifo[{i}]", maxDepth=1) for i in range(4)]  # Drop if more than 1 frame in FIFO
        self.dacLiveDropFifo = [pr.interfaces.stream.Fifo(name=f"DacLiveDropFifo[{i}]", maxDepth=1) for i in range(2)]  # Drop if more than 1 frame in FIFO
        self.adcDropFifo = [pr.interfaces.stream.Fifo(name=f"AdcDropFifo[{i}]", maxDepth=1) for i in range(4)]  # Drop if more than 1 frame in FIFO
        self.posCalcDropFifo = pr.interfaces.stream.Fifo(name=f"PosCalcDropFifo", maxDepth=1)  # Drop if more than 1 frame in FIFO
        self.adcLiveProcessor = [rfsoc_utility.RingBufferProcessor(name=f"AdcLiveProcessor[{i}]", sampleRate=sampleRate) for i in range(4)]
        # DAC SR is set to same as ADC SR in firmware (RFDC IP core)
        self.dacLiveProcessor = [rfsoc_utility.RingBufferProcessor(name=f"DacLiveProcessor[{i}]", sampleRate=sampleRate) for i in range(2)]
        self.adcProcessor = [rfsoc_utility.RingBufferProcessor(name=f"AdcProcessor[{i}]", sampleRate=sampleRate) for i in range(4)]

        self.posCalcProc = rfsoc.SoftwarePosCalcProcessor(
            name="SoftwarePositionCalculation",
            sampleRate=sampleRate,
            signalMapIndexFile=self.signalMapsIndexFile,  # Default value, can be changed dynamically
            bufferDepth=2**10 * 16,  # TODO: Make dynamic!
            nWindows=5,
            hidden=False,
        )

        # Connect the rogue stream arrays: ADC Ring Buffer Paths
        for i in range(4):
            # self.ringBufferAdcLive[i] >> self.dataWriter.getChannel(i+0)  # TODO: Maybe we don't need this anymore
            self.ringBufferAdcLive[i] >> self.adcLiveDropFifo[i] >> self.adcLiveProcessor[i]
            self.add(self.adcLiveProcessor[i])
            self.add(self.adcProcessor[i])

        self.ringBufferAdc >> self.dataWriter.getChannel(0 + 4)  # Use same channel numbers as axis TDEST for consistency

        # Position calculation streams are connected later after initializing
        # the fitter.
        self.add(self.posCalcDropFifo)
        self.add(self.posCalcProc)

        # Connect the rogue stream arrays: DAC Ring Buffer Path
        for i in range(2):
            self.ringBufferDacLive[i] >> self.dataWriter.getChannel(i + 16)
            self.ringBufferDacLive[i] >> self.dacLiveDropFifo[i] >> self.dacLiveProcessor[i]
            self.add(self.dacLiveProcessor[i])

    ##################################################################################

    def start(self, **kwargs):
        super(Root, self).start(**kwargs)

        # Useful pointers
        dacSigGen = self.RFSoC.Application.DacSigGen

        print("Issuing a reset to the user logic")
        self.RFSoC.AxiSocCore.UserRst()

        # Initialize the LMK/LMX Clock chips
        self.Hardware.InitClock(lmkConfig=self.lmkConfig, lmxConfig=[self.lmxConfig])

        print("Wait for DSP Clock to be stable")
        self.RFSoC.AxiSocCore.DspRstWait()

        # Enable application after DSP clock stable has been configured
        self.RFSoC.Application.enable.set(True)
        self.ReadAll()

        # Initialize the RF Data Converter
        self.Rfdc.Init()

        # MTS Sync the RF Data Converter
        self.Rfdc.Mts.AdcTiles.set(0x5)
        self.Rfdc.Mts.DacTiles.set(0x5)
        self.Rfdc.Mts.AdcRefTile.set(0x2)
        self.Rfdc.Mts.DacRefTile.set(0x2)
        self.Rfdc.Mts.SysRefConfig.set(1)
        self.Rfdc.Mts.SyncAdcTiles()
        self.Rfdc.Mts.SyncDacTiles()

        # Load the Default YAML file
        print(f"Loading path={self.defaultFile} Default Configuration File...")
        self.LoadConfig(self.defaultFile)
        self.ReadAll()

        # Load the waveform data into DacSigGen
        csvFile = dacSigGen.CsvFilePath.get()
        if csvFile != "":
            if self.top_level != "":
                dacSigGen.CsvFilePath.set(f"{self.top_level}/{csvFile}")
            dacSigGen.LoadCsvFile()
        else:
            self.RFSoC.Application.DacSigGenLoader.LoadSingleTones()

        # Initial loading of position computation related data like poly
        # coeffs, signal maps etc.
        self.posCalcProc.startupInit()

        # Connect position calculation. Do so after initializing the fitter to
        # avoid the fitter being called with default values which would arrive
        # through the stream if already set up.
        self.ringBufferAdc >> self.posCalcDropFifo >> self.posCalcProc

        # The main ring buffer requires some setup, namely removing rate limit
        self.RFSoC.Application.startupInit()

        # Unhide all nodes recursively
        def unhide_recursive(dev):
            # print("called for ", dev, hasattr(dev, "hidden"), hasattr(dev, "_nodes"))
            if dev.inGroup("Hidden"):
                # print("unhide")
                dev.removeFromGroup("Hidden")
            if hasattr(dev, "_nodes"):
                # print("recursive call")
                for node_name, node_pointer in dev._nodes.items():
                    unhide_recursive(node_pointer)

        unhide_recursive(self)

    ##################################################################################
