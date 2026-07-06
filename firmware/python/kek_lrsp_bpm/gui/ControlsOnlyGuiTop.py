import setupLibPaths  # setup the runtime PYTHONPATH paths

from pydm import Display
from qtpy.QtWidgets import QVBoxLayout
import qdarktheme

import kek_lrsp_bpm.gui as guiUser


class GuiTop(Display):
    def __init__(self, parent=None, args=[], macros=None):
        super(GuiTop, self).__init__(parent=parent, args=args, macros=None)

        self.setStyleSheet("*[dirty='true']\
                           {background-color: orange;}")

        self.channel = None
        self.title = None
        self.dark = False
        if args is not None:
            for a in args:
                if "channel=" in a:
                    self.channel = a.split("=")[1]
                if "title=" in a:
                    self.title = a.split("=")[1]
                if "dark=" in a:
                    val = a.split("=")[1]
                    self.dark = True if val == "True" else False

        if self.dark == True:
            qdarktheme.enable_hi_dpi()  # Enable HiDPI.
            qdarktheme.setup_theme()

        self.setWindowTitle(f"{self.title} ({self.channel})")

        self.vb = QVBoxLayout()
        self.setLayout(self.vb)

        self.controlsGui = guiUser.UserControls(
            parent=None,
            init_channel=self.channel,
        )

        self.vb.addWidget(self.controlsGui)
