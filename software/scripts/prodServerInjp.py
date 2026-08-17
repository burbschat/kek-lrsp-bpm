#!/usr/bin/env python3

# Servers script to be used in production. Reduces number of command line
# arguments and has all usually fixed parameters defined in this script.

import setupLibPaths
import kek_lrsp_bpm

import os
import argparse
import pyrogue
from serverUtils import LMK_CONFIGS, get_injplike_pvmap, get_sr_lmkconfig

if __name__ == "__main__":

    #################################################################

    # Set the argument parser
    parser = argparse.ArgumentParser()

    # Convert str to bool
    argBool = lambda s: s.lower() in ["true", "t", "yes", "1"]

    # Add arguments
    parser.add_argument(
        "--ip",
        type=str,
        required=True,
        help="ETH Host Name (or IP address)",
    )

    parser.add_argument(
        "--ringType",
        type=str,
        required=True,
        choices=["HER", "LER"],
        help=f"Select which ring to target ('HER' or 'LER')",
    )

    parser.add_argument(
        "--disableEpics",
        type=argBool,
        required=False,
        default=False,  # IOC is only initialized when value is other than None
        help="Set to disable EPICS IOC.",
    )

    parser.add_argument(
        "--zmqLocalOnly",
        type=argBool,
        required=False,
        default=False,  # To be run in local controls network only so global access is fine
        help="Set False to allow ZMQ access from other than localhost.",
    )

    parser.add_argument(
        "--pllConfig",
        type=str,
        required=False,
        choices=list(LMK_CONFIGS.keys()),
        default="skbrf",
        help=f"Select one of available PLL configs: {list(LMK_CONFIGS.keys())}",
    )

    parser.add_argument(
        "--zmqSrvPort",
        type=int,
        required=False,
        default=None,
        help="Zeromq server port (set to zero if you want it dynamic). Defaults for HER/LER choosen if set to None.",
    )

    # Get the arguments
    args = parser.parse_args()

    #################################################################

    top_level = os.path.realpath(__file__).split("software")[0]  # Not pretty but works for now

    print(f"Using the '{args.pllConfig}' PLL config.")

    lmk_config_file, sampleRate = get_sr_lmkconfig(args.pllConfig)

    if not args.disableEpics:
        if args.ringType == "HER":
            epicsPrefix = "BMHD08:INJ"
        elif args.ringType == "LER":
            epicsPrefix = "BMLD07:INJ"
        print(f"EPICS prefix is '{epicsPrefix}'")

    if args.zmqSrvPort is None:
        if args.ringType == "HER":
            zmqSrvPort = 9099
        elif args.ringType == "LER":
            zmqSrvPort = 9103
    else:
        zmqSrvPort = args.zmqSrvPort

    print(f"ADC sample rate is: {sampleRate/1e9} GHz")

    with kek_lrsp_bpm.Root(
        ip=args.ip,
        bpmType="injp",
        hardDisableFit=False,  # Only need the fit
        hardDisablePoly=True,
        pollEn=True,
        initRead=True,
        defaultFile=f"{top_level}/software/config/defaults_{args.ringType}.yml",
        lmkConfig=lmk_config_file,
        sampleRate=sampleRate,
        zmqSrvPort=zmqSrvPort,
        nWindows=2,
        epicsPrefix=epicsPrefix,
        getPvMap=get_injplike_pvmap,
        zmqLocalOnly=args.zmqLocalOnly,
    ) as root:

        print("Running without GUI...")
        pyrogue.waitCntrlC()

    #################################################################
