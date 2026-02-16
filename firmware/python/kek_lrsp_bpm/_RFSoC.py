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

import axi_soc_ultra_plus_core  as socCore
import kek_lrsp_bpm as rfsoc

class RFSoC(pr.Device):
    def __init__(self, *args, sampleRate=5.0E+9, **kwargs):
        super().__init__(*args, **kwargs)

        self.add(socCore.AxiSocCore(
            offset      = 0x0000_0000,
            numDmaLanes = 3,
            # expand      = True,
        ))

        self.add(rfsoc.Application(
            offset     = 0xA000_0000,
            sampleRate = sampleRate,  # Units of Hz, depends on PLL config
            expand     = True,
            enabled    = False,  # Do not configure until after DSP clock stable
        ))
