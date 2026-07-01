#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# This file is part of the 'kek-lrsp-bpm'. It is subject to
# the license terms in the LICENSE.txt file found in the top-level directory
# of this distribution and at:
#    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
# No part of the 'kek-lrsp-bpm', including this file, may be
# copied, modified, propagated, or distributed except according to the terms
# contained in the LICENSE.txt file.
# -----------------------------------------------------------------------------
import setupLibPaths
import kek_lrsp_bpm

import os
import sys
import argparse
import importlib
import rogue
import pyrogue
import axi_soc_ultra_plus_core.rfsoc_utility.pydm

if __name__ == "__main__":

    #################################################################

    # Set the argument parser
    parser = argparse.ArgumentParser()

    # Convert str to bool
    argBool = lambda s: s.lower() in ['true', 't', 'yes', '1']

    # Add arguments
    parser.add_argument(
        "--ip",
        type     = str,
        required = True,
        help     = "ETH Host Name (or IP address)",
    )

    parser.add_argument(
        "--pollEn",
        type     = argBool,
        required = False,
        default  = True,
        help     = "Enable auto-polling",
    )

    parser.add_argument(
        "--initRead",
        type     = argBool,
        required = False,
        default  = True,
        help     = "Enable read all variables at start",
    )

    parser.add_argument(
        "--defaultFile",
        type     = str,
        required = False,
        # default  = None,
        default  = "config/defaults.yml",
        help     = "Sets the default YAML configuration file to be loaded at the root.start()",
    )

    parser.add_argument(
        "--epicsPrefix",
        type     = str,
        required = False,
        default  = None,   # IOC is only initialized when value is other than None
        help     = "Prefix for EPICS CA IOC PVs. If not specified IOC will be disabled.",
    )

    # TODO: Not sure how close the RFDC PLL config frequencies should be to the
    # actual sample rate. If problems with e.g. spurs are encountered, perhaps
    # try adjusting the RFDC IP cores config. However I do not believe that
    # this matters much as all the dividers etc. in the PLLs should be the
    # same. Or does it?
    lmk_configs = {
        "default": {"file": "config/lmk/HexRegisterValues_CLKin0-125MHz_CLKin1-10MHz.txt", "out_f_MHz": 500},
        # Below are fractional PLL configs which make it pretty much impossible
        # to configure for use of both the internal 10MHz oscillator and
        # external clock signal. The former is therefore not usable with those.
        # This is required as the LMK on the RFSoC4x2 does not allow to simply
        # bypass the PLL and use the clock signal directly.
        "skbrf": {"file": "config/lmk/HexRegisterValues_CLKin0-508MHz89Approx.txt", "out_f_MHz": 508.89},
        "linacrf": {"file": "config/lmk/HexRegisterValues_CLKin0-114MHz24Approx.txt", "out_f_MHz": 514.08},
        "linacrf_half": {"file": "config/lmk/HexRegisterValues_CLKin0-57MHz12Approx.txt", "out_f_MHz": 514.08},
        "oc520": {"file": "config/lmk/HexRegisterValues_CLKin0-125MHz_CLKin1-10MHz_OC520MHz.txt", "out_f_MHz": 520},
    }

    parser.add_argument(
        "--pllConfig",
        type     = str,
        required = False,
        choices  = list(lmk_configs.keys()),
        default  = "default",
        help     = f"Select one of available PLL configs: {list(lmk_configs.keys())}",
    )

    parser.add_argument(
        "--guiType",
        type     = str,
        required = False,
        default  = "PyDM",
        help     = "Sets the GUI type (PyDM or None)",
    )

    parser.add_argument(
        "--bpmType",
        type     = str,
        required = True,  # Force explicit delcaration here!
        default  = "bt",
        choices  = ["bt", "injp"],
        help     = "Sets the bpm type (bt or injp)",
    )

    parser.add_argument(
        "--zmqSrvPort",
        type     = int,
        required = False,
        default  = 9099,
        help     = "Zeromq server port (set to zero if you want it dynamic)",
    )

    parser.add_argument(
        "--nWindows",
        required = False,
        type     = int,
        default  = None,
        help     = "Number of windows. Set to None to use the default value for given BPM type.",
    )

    # Get the arguments
    args = parser.parse_args()

    #################################################################

    print(f"Using the '{args.pllConfig}' PLL config.")
    lmk_config_file = lmk_configs[args.pllConfig]["file"]
    # ADC/DAC(?) sampling rate is reference clock times eight and thus depends
    # on PLL config! Multiplier defined in RFDC IP core config's PLL settings.
    refclock_freq = lmk_configs[args.pllConfig]["out_f_MHz"] * 1e6  # in Hz
    # Multiplication factor must match RfDC IP core config!
    # With 10 + lock on 509 we are thus actually overclocking (a little bit)
    sampleRate = refclock_freq * 10  # in Hz

    print(f"ADC sample rate is: {sampleRate/1e9} GHz")

    # Set number of windows. For BT number of windows may depend on the readout
    # location, so allow manual setting using command line argument.
    nWindows = 1  # Default: 1 window
    if args.bpmType == "injp":
        nWindows = 2
    elif args.bpmType == "bt":
        nWindows = 5

    # nWindows takes precedence if set.
    if args.nWindows is not None:
        nWindows = args.nWindows
        print(f"Set {nWindows} according to passed command line argument.")
    else:
        print(f"Inferred {nWindows} windows for BPM type {args.bpmType}.")

    with kek_lrsp_bpm.Root(
        ip          = args.ip,
        bpmType     = args.bpmType,
        pollEn      = args.pollEn,
        initRead    = args.initRead,
        defaultFile = args.defaultFile,
        lmkConfig   = lmk_config_file,
        sampleRate  = sampleRate,
        zmqSrvPort  = args.zmqSrvPort,
        nWindows    = nWindows,
        epicsPrefix = args.epicsPrefix,
    ) as root:

        ######################
        # Development PyDM GUI
        ######################
        if (args.guiType == 'PyDM'):
            top_level = os.path.realpath(__file__).split('software')[0]  # Not pretty but works for now
            axi_soc_ultra_plus_core.rfsoc_utility.pydm.runPyDM(
                serverList = root.zmqServer.address,
                ui       = f'{top_level}/firmware/python/kek_lrsp_bpm/gui/GuiTop.py',
                sizeX    = 800,
                sizeY    = 800,
                numAdcCh = 4,
                numDacCh = 2,
            )

        #################
        # No GUI
        #################
        elif (args.guiType == 'None'):
            print("Running without GUI...")
            pyrogue.waitCntrlC()

        ####################
        # Undefined GUI type
        ####################
        else:
            raise ValueError("Invalid GUI type (%s)" % (args.guiType) )

    #################################################################
