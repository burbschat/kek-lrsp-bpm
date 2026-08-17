import os
from pydm import Display, PyDMApplication
from qtpy.QtGui import QColor, QPalette
from qtpy.QtWidgets import QFrame, QPushButton, QSpinBox, QVBoxLayout, QHBoxLayout, QTabWidget, QCheckBox

from pydm.widgets.timeplot import PyDMTimePlot
from pydm.widgets import PyDMPushButton
from PyQt5.QtWidgets import QSizePolicy
from PyQt5.QtGui import QColor
import pyqtgraph as pg

import kek_lrsp_bpm.gui as guiUser

DEFAULT_TIME_SPAN = 60  # seconds


class BpmTimePlots(QFrame):
    def __init__(self, parent, bunch_ids):
        super().__init__()

        self.bunch_ids = bunch_ids

        self.backgroundColor = parent.backgroundColor
        # Use QColor so we can adjust alpha value later!
        self.bunch_colors = {
            "X1": QColor("red"),
            "Y1": QColor("orange"),
            "Q1": QColor("gold"),
            "X2": QColor("royalblue"),
            "Y2": QColor("deepskyblue"),
            "Q2": QColor("turquoise"),
        }

        # If more than one bunches are plotted, add alpha so overlapping lines
        # can be told apart
        # alpha_val = 80
        # if len(bunch_ids) > 1:
        #     for _, v in self.bunch_colors.items():
        #         v.setAlpha(alpha_val)

        self.pv_prefix = parent.pv_prefix

        vb = QVBoxLayout()
        vb.setContentsMargins(0, 0, 0, 0)
        vb.setSpacing(2)
        self.setLayout(vb)

        # self.plot = PyDMArchiverTimePlot(background=self.background, cache_data=True, show_all=False)
        self.plot = PyDMTimePlot(background=self.backgroundColor)
        self.plot.setTimeSpan(DEFAULT_TIME_SPAN)
        self.plot.setShowLegend(True)

        # Set maximum update rate. Decrease if too much resources used.
        self.plot.setMaxRedrawRate(25)

        self.y_channels = []

        lineplot_opts = {
            # Must set NoPen object as workaround as a None value is not passed
            # on in pydm...
            "lineStyle": pg.QtCore.Qt.NoPen,
            "symbol": "o",
            # Did not manage to get filled points but small non-filled ones are fine
            "symbolSize": 3,
        }

        self.curves = {}

        for direction in ["X", "Y"]:
            self.plot.addAxis(
                plot_data_item=None,
                name=f"{direction}_pos",
                orientation="left",
                label=f"{direction} Pos. (mm)",
                enable_auto_range=True,
            )

            for bunch_id in self.bunch_ids:
                self.curves[f"pos_{direction}_{bunch_id}"] = self.plot.addYChannel(
                    y_channel=f"ca://{self.pv_prefix}:{direction}_{bunch_id}",
                    plot_style="Line",
                    name=f"{direction}_{bunch_id}",
                    color=self.bunch_colors[f"{direction}{bunch_id}"],
                    yAxisName=f"{direction}_pos",
                    **lineplot_opts,
                )

        self.plot.addAxis(
            plot_data_item=None,
            name="Charge",
            orientation="left",
            label="Charge (a.u.)",
            enable_auto_range=True,
        )

        for bunch_id in self.bunch_ids:
            self.curves[f"charge_{bunch_id}"] = self.plot.addYChannel(
                y_channel=f"ca://{self.pv_prefix}:Q_{bunch_id}",
                plot_style="Line",
                name=f"Q_{bunch_id}",
                # color="green",
                color=self.bunch_colors[f"Q{bunch_id}"],
                yAxisName="Charge",
                **lineplot_opts,
            )

        self.bunches_shown_flags = [True] * len(self.bunch_ids)

        self.controls_frame = QFrame()
        controls_hb = QHBoxLayout()
        controls_hb.setContentsMargins(5, 1, 1, 5)
        controls_hb.setSpacing(2)
        self.controls_frame.setLayout(controls_hb)

        self.forceRedrButton = PyDMPushButton(label="Force Redraw")
        self.forceRedrButton.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Preferred)
        self.forceRedrButton.clicked.connect(self.force_redraw_plots)

        self.reloadArchDatButton = PyDMPushButton(label="Reload All")
        self.reloadArchDatButton.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Preferred)
        self.reloadArchDatButton.clicked.connect(self.refetch_archiver_data)

        self.xrangeSpinbox = QSpinBox()
        self.xrangeSpinbox.setValue(DEFAULT_TIME_SPAN)
        self.xrangeSpinbox.setPrefix("X Range: ")
        self.xrangeSpinbox.setSuffix(" s")
        self.xrangeSpinbox.setRange(0, 2147483647)
        self.xrangeSpinbox.valueChanged.connect(self.xrangeSpinChanged)

        self.chkbx_live = QCheckBox("Live Update")
        self.chkbx_live.setChecked(True)
        self.chkbx_live.stateChanged.connect(self.set_live)

        self.show_bunch_chkbxs = {}
        for bunch_id in self.bunch_ids:
            chkbx = QCheckBox(f"Bunch {bunch_id}")
            chkbx.setChecked(True)
            chkbx.stateChanged.connect(lambda val, i=bunch_id: self.set_bunch_visible(i, val))
            self.show_bunch_chkbxs[bunch_id] = chkbx

        # vb.addWidget(self.tab)
        vb.addWidget(self.plot)
        for chkbx in self.show_bunch_chkbxs.values():
            controls_hb.addWidget(chkbx)

        # controls_hb.addWidget(self.forceRedrButton)
        # controls_hb.addWidget(self.reloadArchDatButton)
        controls_hb.addWidget(self.xrangeSpinbox)

        # controls_hb.addWidget(self.chkbx_live)
        vb.addWidget(self.controls_frame)

        self.plot.plotItem.sigXRangeChanged.connect(self.plot.updateXAxis)

        self.set_all_curves_alpha(80)

    def set_curve_alpha(self, curve, alpha):
        # Get color, then re-assign to ensure proper update
        color = curve.color
        color.setAlpha(alpha)
        curve.color = color

    def set_all_curves_alpha(self, alpha):
        for curve in self.curves.values():
            self.set_curve_alpha(curve, alpha)

    def set_bunch_visible(self, bunch_id, val):
        # Keep track of number of shown bunches
        self.bunches_shown_flags[bunch_id - 1] = bool(val)

        if self.bunches_shown_flags.count(True) > 1:
            alpha = 80
        else:
            alpha = 255

        for bunch_id in self.bunch_ids:
            bunch_curves = [f"pos_{direction}_{bunch_id}" for direction in ("X", "Y")] + [f"charge_{bunch_id}"]
            if self.bunches_shown_flags[bunch_id - 1]:
                for curve_name in bunch_curves:
                    curve = self.curves[curve_name]
                    curve.setVisible(True)
                    self.set_curve_alpha(curve, alpha)
            else:
                for curve_name in bunch_curves:
                    curve = self.curves[curve_name]
                    curve.setVisible(False)

    # Workaround for fetch on pan/zoom not updating until redraw which only happens on PV update
    def force_redraw_plots(self):
        self.plot.set_needs_redraw()
        # self.plot._min_x = self.plot._starting_timestamp
        self.plot.updateXAxis()

    def refetch_archiver_data(self):
        self.plot._min_x = self.plot._starting_timestamp
        self.force_redraw_plots()  # Force redraw

    # Shit ain't work
    # def set_autoscrl(self, value):
    #     print(value)
    #     self.plot.setAutoScroll(bool(value))
    #     print(self.plot.auto_scroll_timer.isActive())

    def set_live(self, value):
        print(value)
        for curve in self.curves.values():
            curve.liveData = value

    def xrangeSpinChanged(self, value):
        self.plot.setTimeSpan(value)


class GuiSingleRing(QFrame):
    def __init__(
        self,
        parent=None,
        init_channel=None,
        pv_prefix="",
        dark=False,
        backgroundColor=None,
        border=[0, 0, 0],
        top_label="Title",
    ):
        super().__init__(parent=parent)

        self.init_channel = init_channel
        self.top_label = top_label
        self.dark = dark

        self.backgroundColor = backgroundColor
        self.pv_prefix = pv_prefix

        self.setFrameShape(QFrame.Box)
        self.setFrameShadow(QFrame.Plain)
        self.setLineWidth(3)
        pal = self.palette()
        pal.setColor(QPalette.WindowText, QColor(*border))
        self.setPalette(pal)

        vb = QVBoxLayout()
        vb.setContentsMargins(0, 0, 0, 0)
        vb.setSpacing(2)
        self.setLayout(vb)

        self.tabWavScatter = QTabWidget()
        # self.tabTimePlots = QTabWidget()

        self.tabWavScatter.addTab(
            guiUser.WaveformDisplay(
                parent=self,
                init_channel=self.init_channel,
                nodePath="SoftwarePositionCalculation",
                waveformNodeName="WaveformData",
                backgroundColor=self.backgroundColor,
            ),
            "Waveform",
        )

        # BPM Position Scatter Plot
        self.tabWavScatter.addTab(
            guiUser.BpmPosScatter(
                parent=None,
                init_channel=self.init_channel,
                backgroundColor=self.backgroundColor,
                nWindows=2,
                customColors=["red", "royalblue"],
            ),
            "Pos. Scatter",
        )

        # Set the default Tab view
        self.tabWavScatter.setCurrentIndex(1)

        # "Natural" bunch index (i.e. 1 or 2)
        # self.timePlots1st = BpmTimePlots(parent=self, bunch_ids=[1])
        # self.timePlots2nd = BpmTimePlots(parent=self, bunch_ids=[2])
        self.timePlotsBoth = BpmTimePlots(parent=self, bunch_ids=[1, 2])

        # self.openControlsDispButton = PyDMRelatedDisplayButton("test", filename="/home/bera/kek-lrsp-bpm/firmware/python/kek_lrsp_bpm/gui/DevGuiTop.py")
        self.openControlsDispButton = QPushButton("Open Controls")
        self.openControlsDispButton.clicked.connect(self.launchControlsGui)
        self.openControlsDispButton.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Preferred)

        # self.tabTimePlots.addTab(
        #     self.timePlots1st,
        #     "1st Bunch"
        # )
        #
        # self.tabTimePlots.addTab(
        #     self.timePlots2nd,
        #     "2nd Bunch"
        # )
        #
        # self.tabTimePlots.addTab(
        #     self.timePlotsBoth,
        #     "Both"
        # )

        # self.label = QLabel(self.top_label)
        # self.label.setAlignment(Qt.AlignCenter)
        # self.label.setStyleSheet("QFrame {border-width: 2;}")
        # self.label.setStyleSheet(f"color: rgb{tuple(border)};")
        # self.label.setFont(QFont("Arial", 14))
        # vb.addWidget(self.label)
        vb.addWidget(self.tabWavScatter)
        # vb.addWidget(self.tabTimePlots)
        vb.addWidget(self.timePlotsBoth)
        vb.addWidget(self.openControlsDispButton)

    def launchControlsGui(self):
        args = []
        args.append(f"title=Controls Injp BPM ({self.top_label})")
        args.append(f"channel={self.init_channel}")
        args.append(f"dark={self.dark}")
        app = PyDMApplication.instance()

        top_level = os.path.realpath(__file__).split("firmware")[0]
        app.new_pydm_process(
            ui_file=f"{top_level}firmware/python/kek_lrsp_bpm/gui/ControlsOnlyGuiTop.py",
            command_line_args=args,
        )


class GuiTop(Display):
    def __init__(self, parent=None, args=[], macros=None):
        super(GuiTop, self).__init__(parent=parent, args=args, macros=None)
        print(macros)

        if "dark=True" in args:
            self.dark = True
            self.backgroundColor = [0, 0, 0, 255]  # Use black background
        else:
            self.dark = False
            self.backgroundColor = [255, 255, 255, 255]  # Use white background
            # self.backgroundColor = None  # Use transparent background

        # Get rogue channels from arguments
        self.channelHER = None
        self.channelLER = None
        if args is not None:
            for a in args:
                if "channelHER=" in a:
                    self.channelHER = a.split("=")[1]
                if "channelLER=" in a:
                    self.channelLER = a.split("=")[1]

        self.setStyleSheet("*[dirty='true']\
                           {background-color: orange;}")

        self.sizeX = None
        self.sizeY = None
        self.title = "Injection BPM"

        if self.sizeX is None:
            self.sizeX = 800
        if self.sizeY is None:
            self.sizeY = 1000

        self.setWindowTitle(self.title)

        hb = QHBoxLayout()
        hb.setContentsMargins(1, 1, 1, 1)
        hb.setSpacing(1)
        self.setLayout(hb)

        self.guiLER = GuiSingleRing(
            init_channel=self.channelLER,
            pv_prefix="BMLD07:INJ",
            dark=self.dark,
            backgroundColor=self.backgroundColor,
            border=(255, 100, 100),
            top_label="LER",
        )
        self.guiHER = GuiSingleRing(
            init_channel=self.channelHER,
            pv_prefix="BMHD08:INJ",
            dark=self.dark,
            backgroundColor=self.backgroundColor,
            border=(100, 100, 255),
            top_label="HER",
        )
        hb.addWidget(self.guiLER)
        hb.addWidget(self.guiHER)

        # Resize the window
        self.resize(self.sizeX, self.sizeY)

    def ui_filepath(self):
        # No UI file is being used
        return None
