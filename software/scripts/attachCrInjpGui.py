#!/usr/bin/env python3
import setupLibPaths  # setup the runtime PYTHONPATH paths

import os
import argparse
import pydm
import qdarktheme

## WORKAROUND ##
# For softioc/pyepics incompatibility
os.environ["PYDM_EPICS_LIB"] = "CAPROTO"
# Point to SuperKEKB archiver
os.environ["PYDM_ARCHIVER_URL"] = "http://kekb-co-web.kek.jp/archappl_skekb"


def main():
    # Set the argument parser
    parser = argparse.ArgumentParser()

    # Add arguments
    parser.add_argument(
        "--zmqServerIP",
        type     = str,
        required = False,
        default  = 'localhost',
        help     = "ZeroMQ server's hostname or IP address",
    )

    parser.add_argument(
        "--zmqServerPortHER",
        type     = str,
        required = False,
        default  = '9099',
        help     = "ZeroMQ server's port for HER",
    )

    parser.add_argument(
        "--zmqServerPortLER",
        type     = str,
        required = False,
        default  = '9103',
        help     = "ZeroMQ server's port for LER",
    )

    parser.add_argument(
        "--dark",
        action="store_true",
        required=False,
        default=False,
        help="Set to enable dark mode (nice)",
    )

    top_level = os.path.realpath(__file__).split("software")[0]

    # Get the arguments
    parsed_args = parser.parse_args()
    print(parsed_args)

    title = None
    sizeX = 800
    sizeY = 1000
    maxListExpand = 5
    maxListSize = 100
    dark = parsed_args.dark
    channelHER = f"rogue://{parsed_args.zmqServerIP}:{parsed_args.zmqServerPortHER}/root"
    channelLER = f"rogue://{parsed_args.zmqServerIP}:{parsed_args.zmqServerPortLER}/root"

    args = []
    args.append(f"sizeX={sizeX}")
    args.append(f"sizeY={sizeY}")
    args.append(f"title='{title}'")
    args.append(f"maxListExpand={maxListExpand}")
    args.append(f"maxListSize={maxListSize}")
    args.append(f"dark={dark}")
    args.append(f"channelHER={channelHER}")
    args.append(f"channelLER={channelLER}")

    app = pydm.PyDMApplication(
        ui_file=f"{top_level}/firmware/python/kek_lrsp_bpm/gui/CrInjpGuiTop.py",
        command_line_args=args,
        hide_nav_bar=True,
        hide_menu_bar=True,
        hide_status_bar=True,
    )

    if dark:
        qdarktheme.enable_hi_dpi()  # Enable HiDPI.
        qdarktheme.setup_theme()

    app.exec()


if __name__ == "__main__":
    main()
