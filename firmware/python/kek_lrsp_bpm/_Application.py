# -----------------------------------------------------------------------------
# This file is part of the 'kek-lrsp-bpm'. It is subject to
# the license terms in the LICENSE.txt file found in the top-level directory
# of this distribution and at:
#    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
# No part of the 'kek-lrsp-bpm', including this file, may be
# copied, modified, propagated, or distributed except according to the terms
# contained in the LICENSE.txt file.
# -----------------------------------------------------------------------------

import pyrogue as pr
import kek_lrsp_bpm as rfsoc

import axi_soc_ultra_plus_core.rfsoc_utility as rfsoc_utility

class Application(pr.Device):
    def __init__(
        self,
        *args,
        sampleRate=5.0e9,  # Units of Hz, depends on PLL config
        **kwargs,
    ):
        super().__init__(*args, **kwargs)

        # Supersample rate (samples per dac clock)
        ssr = 16  # Must match SAMPLE_PER_CYCLE_G config

        self.add(rfsoc_utility.AppRingBuffer(
            name     = "AppRingBufferLive",
            offset   = 0x00_000000,
            numAdcCh = 4, # Must match NUM_ADC_CH_G config
            numDacCh = 2, # Must match NUM_DAC_CH_G config
            # expand   = True,
        ))

        # Here four channels are interlevaed into one stream to ensure
        # synchronization between channels. One must de-interleave those later
        # manually.
        self.add(rfsoc_utility.AppRingBuffer(
            name     = "AppRingBuffer",
            offset   = 0x0100_0000,
            numAdcCh = 1, # Must match NUM_ADC_CH_G config
            numDacCh = 0, # Must match NUM_DAC_CH_G config
            # expand   = True,
        ))

        self.add(rfsoc_utility.SigGen(
            name         = 'DacSigGen',
            offset       = 0x0200_0000,
            numCh        = 2,  # Must match NUM_CH_G config
            ramWidth     = 10, # Must match RAM_ADDR_WIDTH_G config
            smplPerCycle = ssr, # Must match SAMPLE_PER_CYCLE_G config
            # expand       = True,
        ))

        self.add(rfsoc_utility.SigGenLoader(
            name         = 'DacSigGenLoader',
            DacSigGen    = self.DacSigGen,
            numCh        = 2,  # Must match NUM_CH_G config
            ramWidth     = 10, # Must match RAM_ADDR_WIDTH_G config
            smplPerCycle = ssr, # Must match SAMPLE_PER_CYCLE_G config
            sampleRate   = sampleRate,  # Units of Hz
            # Seems like this module may produce very short buffers depending
            # on the set frequency. This leads to very few points in FFT
            # display.
            defaultFreq  = sampleRate/40,  # Should divide sampleRate
            expand       = True,
        ))

        self.add(rfsoc.ReadoutCtrl(
            offset      = 0x0300_0000,
            sampleRate  = sampleRate,
            SSR         = ssr,
            expand      = True,
        ))

        self.add(rfsoc.EvrDecoder(
            offset     = 0x0400_0000,
            n_trgs     = 4,
        ))

    def startupInit(self):
        # Disable frame rate limit
        self.AppRingBuffer.RateLimiter.MaxFrameRate.set(0x0)
