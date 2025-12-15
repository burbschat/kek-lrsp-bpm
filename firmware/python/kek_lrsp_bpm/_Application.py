#-----------------------------------------------------------------------------
# This file is part of the 'kek-lrsp-bpm'. It is subject to
# the license terms in the LICENSE.txt file found in the top-level directory
# of this distribution and at:
#    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
# No part of the 'kek-lrsp-bpm', including this file, may be
# copied, modified, propagated, or distributed except according to the terms
# contained in the LICENSE.txt file.
#-----------------------------------------------------------------------------

import pyrogue as pr
import kek_lrsp_bpm as rfsoc

import axi_soc_ultra_plus_core.rfsoc_utility as rfsoc_utility

class Application(pr.Device):
    def __init__(self,**kwargs):
        super().__init__(**kwargs)

        self.sampleRateGHz = 0.509*8  # TODO: Put exact value!
        self.ssr = 16 # Supersample rate (samples per dac clock)

        self.add(rfsoc_utility.AppRingBuffer(
            name     = "AppRingBufferLive",
            offset   = 0x00_000000,
            numAdcCh = 4, # Must match NUM_ADC_CH_G config
            numDacCh = 2, # Must match NUM_DAC_CH_G config
            # expand   = True,
        ))

        self.add(rfsoc_utility.AppRingBuffer(
            name     = "AppRingBuffer",
            offset   = 0x01_000000,
            numAdcCh = 4, # Must match NUM_ADC_CH_G config
            numDacCh = 0, # Must match NUM_DAC_CH_G config
            # expand   = True,
        ))

        self.add(rfsoc_utility.SigGen(
            name         = 'DacSigGen',
            offset       = 0x02_000000,
            numCh        = 2,  # Must match NUM_CH_G config
            ramWidth     = 10, # Must match RAM_ADDR_WIDTH_G config
            smplPerCycle = 16, # Must match SAMPLE_PER_CYCLE_G config
            # expand       = True,
        ))

        self.add(rfsoc_utility.SigGenLoader(
            name         = 'DacSigGenLoader',
            DacSigGen    = self.DacSigGen,
            numCh        = 2,  # Must match NUM_CH_G config
            ramWidth     = 10, # Must match RAM_ADDR_WIDTH_G config
            smplPerCycle = 16, # Must match SAMPLE_PER_CYCLE_G config
            sampleRate   = 5.0E+9, # Units of Hz
            expand       = True,
        ))

        self.add(rfsoc.ReadoutCtrl(
            offset      = 0x03_000000,
            sampleRate  = self.sampleRateGHz,
            SSR         = self.ssr,
            expand      = True,
        ))
