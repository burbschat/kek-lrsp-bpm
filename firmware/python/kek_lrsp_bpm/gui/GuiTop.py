import os
from pydm import Display
from qtpy.QtWidgets import QVBoxLayout, QTabWidget

from pyrogue.pydm.widgets import DebugTree
from pyrogue.pydm.widgets import SystemWindow

import axi_soc_ultra_plus_core.rfsoc_utility.gui as gui
import kek_lrsp_bpm.gui as guiUser

Channel = "rogue://0/root"


class GuiTop(Display):
    def __init__(self, parent=None, args=[], macros=None):
        super(GuiTop, self).__init__(parent=parent, args=args, macros=None)

        self.setStyleSheet("*[dirty='true']\
                           {background-color: orange;}")

        self.channelColors = ["royalblue", "orange", "red", "limegreen"]

        self.sizeX = None
        self.sizeY = None
        self.title = None
        self.numAdcCh = None
        self.numDacCh = None

        for a in args:
            if "sizeX=" in a:
                self.sizeX = int(a.split("=")[1])
            if "sizeY=" in a:
                self.sizeY = int(a.split("=")[1])
            if "title=" in a:
                self.title = a.split("=")[1]
            if "numAdcCh=" in a:
                self.numAdcCh = int(a.split("=")[1])
            if "numDacCh=" in a:
                self.numDacCh = int(a.split("=")[1])

        if self.title is None:
            self.title = "Rogue Server: {}".format(os.getenv("ROGUE_SERVERS"))

        if self.sizeX is None:
            self.sizeX = 800
        if self.sizeY is None:
            self.sizeY = 1000
        if self.numAdcCh is None:
            self.numAdcCh = 1
        if self.numDacCh is None:
            self.numDacCh = 1

        self.setWindowTitle(self.title)

        vb = QVBoxLayout()
        self.setLayout(vb)

        self.tab = QTabWidget()
        vb.addWidget(self.tab)

        # System (Tab Index=0)
        sysWin = SystemWindow(parent=None, init_channel=Channel)
        self.tab.addTab(sysWin, "System")

        # Debug Tree (Tab Index=1)
        debugTree = DebugTree(parent=None, init_channel=Channel)
        self.tab.addTab(debugTree, "Debug Tree")

        # ADC Live Display (Tab Index=2)
        adcDisplayLive = gui.LiveDisplay(parent=None, init_channel=Channel, dispType="AdcLive", numCh=self.numAdcCh)
        adcDisplayLive.color = self.channelColors * 4
        self.tab.addTab(adcDisplayLive, "ADC Live")

        # DAC Live Display (Tab Index=3)
        dacDisplayLive = gui.LiveDisplay(parent=None, init_channel=Channel, dispType="DacLive", numCh=self.numDacCh)
        dacDisplayLive.color = self.channelColors * 4
        self.tab.addTab(dacDisplayLive, "DAC Live")

        customColors = ["red", "royalblue"]

        # ADC Display (Tab Index=4)
        self.tab.addTab(
            guiUser.WaveformDisplay(
                parent=None,
                init_channel=Channel,
                nodePath="SoftwarePositionCalculation",
                waveformNodeName="WaveformData",
                customRegionColors=customColors,
            ),
            "ADC",
        )

        # BPM Position Scatter Plot (Tab Index=5, 6)
        # TODO: For BT we probably want a different variation of those: Poly
        # only, no signal map. Put some sort of argument for selection maybe...
        self.tab.addTab(
            guiUser.BpmPosScatter(
                parent=None,
                init_channel=Channel,
                invertX=True,
                nWindows=2,
                customColors=customColors,
            ),
            "Pos Scatter (Fit)",
        )
        self.tab.addTab(
            guiUser.BpmPosScatter(
                parent=None,
                init_channel=Channel,
                invertX=True,
                nWindows=2,
                customColors=customColors,
                posVarType="Poly",
            ),
            "Pos Scatter (Poly)",
        )

        self.tab.addTab(
            guiUser.UserControls(
                parent=None,
                init_channel=Channel,
            ),
            "User Controls",
        )

        # Set the default Tab view
        self.tab.setCurrentIndex(7)

        # Resize the window
        self.resize(self.sizeX, self.sizeY)

    def ui_filepath(self):
        # No UI file is being used
        return None
