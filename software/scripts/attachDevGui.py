import setupLibPaths # setup the runtime PYTHONPATH paths

import os
import argparse
import axi_soc_ultra_plus_core.rfsoc_utility.pydm


def main():

    # Set the argument parser
    parser = argparse.ArgumentParser()

    # Add arguments
    parser.add_argument(
        "--serverList",
        type     = str,
        required = False,
        default  = 'localhost:9099',
        help     = "ZeroMQ server's hostname or IP address:port",
    )

    parser.add_argument(
        "--appType",
        type     = str,
        required = False,
        default  = 'stripline',
        help     = "Sets the application type (bor or stripline)",
    )

    # Get the arguments
    args = parser.parse_args()

    top_level = os.path.realpath(__file__).split("software")[0]

    axi_soc_ultra_plus_core.rfsoc_utility.pydm.runPyDM(
        serverList=args.serverList,
        ui=f"{top_level}/firmware/python/kek_lrsp_bpm/gui/DevGuiTop.py",
        sizeX=800,
        sizeY=800,
    )


if __name__ == "__main__":
    main()
