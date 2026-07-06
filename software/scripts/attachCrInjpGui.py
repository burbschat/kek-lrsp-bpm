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
    # parser.add_argument(
    #     "--serverList",
    #     type     = str,
    #     required = False,
    #     default  = 'localhost:9099',
    #     help     = "ZeroMQ server's hostname or IP address:port",
    # )

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
    numAdcCh = 1
    numDacCh = 1
    dark = parsed_args.dark
    # channelHER = "rogue://172.19.46.9:9099/root"
    # channelLER = "rogue://172.19.46.9:9103/root"
    channelHER = "rogue://localhost:9099/root"
    channelLER = "rogue://localhost:9099/root"

    args = []
    args.append(f"sizeX={sizeX}")
    args.append(f"sizeY={sizeY}")
    args.append(f"title='{title}'")
    args.append(f"maxListExpand={maxListExpand}")
    args.append(f"maxListSize={maxListSize}")
    args.append(f"numAdcCh={numAdcCh}")
    args.append(f"numDacCh={numDacCh}")
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
