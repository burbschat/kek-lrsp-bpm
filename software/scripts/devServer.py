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
from serverUtils import LMK_CONFIGS, get_injplike_pvmap, get_sr_lmkconfig

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

    parser.add_argument(
        "--zmqLocalOnly",
        type     = argBool,
        required = False,
        default  = True,
        help     = "Set False to allow ZMQ access from other than localhost.",
    )

    parser.add_argument(
        "--pllConfig",
        type     = str,
        required = False,
        choices  = list(LMK_CONFIGS.keys()),
        default  = "default",
        help     = f"Select one of available PLL configs: {list(LMK_CONFIGS.keys())}",
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
        default  = 0,
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

    lmk_config_file, sampleRate = get_sr_lmkconfig(args.pllConfig)

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
        print(f"Set {nWindows} windows according to passed command line argument value.")
    else:
        print(f"Inferred {nWindows} windows for BPM type {args.bpmType}.")

    with kek_lrsp_bpm.Root(
        ip              = args.ip,
        bpmType         = args.bpmType,
        hardDisableFit  = args.bpmType == "bt",  # BT only requires poly
        hardDisablePoly = False,
        pollEn          = args.pollEn,
        initRead        = args.initRead,
        defaultFile     = args.defaultFile,
        lmkConfig       = lmk_config_file,
        sampleRate      = sampleRate,
        zmqSrvPort      = args.zmqSrvPort,
        nWindows        = nWindows,
        epicsPrefix     = args.epicsPrefix,
        getPvMap        = get_injplike_pvmap,
        zmqLocalOnly    = args.zmqLocalOnly,
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
