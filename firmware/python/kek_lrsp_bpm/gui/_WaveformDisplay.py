from pydm.widgets.frame import PyDMFrame
from pydm.widgets import PyDMWaveformPlot, PyDMPushButton

from qtpy.QtCore import Qt
from qtpy.QtWidgets import QVBoxLayout, QFormLayout, QGroupBox, QDoubleSpinBox

from pyrogue.pydm.data_plugins.rogue_plugin import nodeFromAddress

import pyrogue as pr

from pyqtgraph import TextItem
from pyqtgraph import LinearRegionItem
from pydm import PyDMChannel
import numpy as np
import pyqtgraph as pg

# Reloading with labels breaks thisngs and I cannot figure out why.
# Something keeps calling the receive value callbacks even if I try to
# disconnect all PyDM channels.
LABELS = False

class ShadedRegionItem:
    def __init__(self, lowerBoundAddr, upperBoundAddr, regionLabel=None, **kwargs):
        self.lower = 0  # Arbitrary default value
        self.upper = 1  # Arbitrary default value

        self.latest_lower = None
        self.latest_upper = None

        self.lower_channel = PyDMChannel(
            address=lowerBoundAddr, value_slot=self.receiveValueLower, connection_slot=self.connection_state_changed
        )
        self.upper_channel = PyDMChannel(
            address=upperBoundAddr, value_slot=self.receiveValueUpper, connection_slot=self.connection_state_changed
        )

        # All keyword arguments are passed on as styling options
        self.region = LinearRegionItem(values=(self.lower, self.upper), movable=False, **kwargs)

        self.label = None
        if regionLabel is not None and LABELS:
            self.label = TextItem(text=regionLabel, color="#aaaaaa", anchor=(0.5, 0.0))

        self.lower_channel.connect()
        self.upper_channel.connect()

    def connection_state_changed(self):
        # print("Connection state changed")
        pass

    def receiveValueLower(self, new_value):
        # print(f"Received value lower: {new_value}")
        self.latest_lower = new_value
        self.update_region()

    def receiveValueUpper(self, new_value):
        # print(f"Received value upper: {new_value}")
        self.latest_upper = new_value
        self.update_region()

    def update_region(self):
        if self.latest_lower is not None:
            self.lower = self.latest_lower
        if self.latest_upper is not None:
            self.upper = self.latest_upper
        # print(f"Setting bounds: {self.lower, self.upper}")
        self.region.setRegion((self.lower, self.upper))
        if LABELS:
            self.label.setX((self.upper + self.lower) / 2)

# Inherit from PyDMWaveformPlot adding a basic way for shading regions
class PyDMWaveformPlotRanges(PyDMWaveformPlot):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

        self.regions = []

        if LABELS:
            self.sigYRangeChanged.connect(self.update_labels)

    def addShadedRegion(self, lowerBoundChannel, upperBoundChannel, **kwargs):
        region = ShadedRegionItem(lowerBoundChannel, upperBoundChannel, **kwargs)
        self.addItem(region.region)
        if LABELS:
            self.addItem(region.label)
        self.regions += [region]
        return region

    def update_labels(self, vb):
        for region in self.regions:
            ypos = vb.viewRange()[1][1]
            region.label.setY(ypos)


class WaveformDisplay(PyDMFrame):

    def __init__(
        self,
        parent=None,
        init_channel=None,
        nodePath="SoftwarePositionCalculation",
        waveformNodeName="WaveformData",
        background=[0, 0, 0, 255],
        minimumWidth=10,
        electrode_colors={"A": "royalblue", "B": "orange", "C": "red", "D": "limegreen"},
    ):
        PyDMFrame.__init__(self, parent, init_channel)
        self.background = background
        self.electrode_colors = electrode_colors
        self._node = None
        self.nodePath = nodePath
        self.waveformNodeName = waveformNodeName
        self.path = f"{self.channel}.{self.nodePath}"
        self.RxEnable = nodeFromAddress(f"{self.path}.RxEnable")

        # Make sure this plot does not excessively restrict min size
        self.setMinimumWidth(minimumWidth)

        self._num_windows_channel = PyDMChannel(
            address=f"{self.channel}.SoftwarePositionCalculation.NumWindows",
            value_slot=self.receiveNumWindows,
            connection_slot=self.receiveNumWindows,
        )
        self._num_windows_channel.connect()

    def receiveNumWindows(self, new_value):
        self._num_windows = new_value
        self.drawShadedRegions()

    def drawShadedRegions(self):
        # Remove all present shaded regions
        for shreg in self.sigPlot.regions:
            self.sigPlot.removeItem(shreg.region)
            if LABELS:
                self.sigPlot.removeItem(shreg.label)
        self.sigPlot.regions.clear()

        # Draw new shaded regions
        for i in range(self._num_windows):
            # color = (255, 0, 0, 50)  # Make sure this has transparency!
            # color = (0, 0, 255, 50)  # Make sure this has transparency!
            color = pg.intColor(i, hues=self._num_windows)  # Get a color
            color.setAlpha(50)
            shreg = self.sigPlot.addShadedRegion(
                f"{self.channel}.SoftwarePositionCalculation.WindowOpen[{i}]",
                f"{self.channel}.SoftwarePositionCalculation.WindowClose[{i}]",
                regionLabel=str(i),
                brush=color,
            )

        # Call once to position labels correctly
        if LABELS:
            self.sigPlot.update_labels(self.sigPlot.getViewBox())

    def resetScales(self):
        # Reset the auto-ranging
        # self.xPosPlot.setAutoRangeX(True)
        # self.xPosPlot.resetAutoRangeX()
        self.sigPlot.resetAutoRangeY()
        # Workaround as the autorange for some reason messes with the shaded region ranges
        # Don't really need x autorange here so just do a pseudo-autorange
        # where we just scale such that everything is in view.
        x_waveform_data = []
        for curve in self.sigPlot._curves:
            x_waveform_data.append(curve.x_waveform)
        x_waveform_data = np.array(x_waveform_data)
        x_waveform_max = x_waveform_data.max().max()
        x_waveform_min = x_waveform_data.min().min()
        self.sigPlot.setXRange(x_waveform_min, x_waveform_max)  # , padding=0.05)

    def connection_changed(self, connected):
        build = (self._node is None) and (self._connected != connected and connected is True)
        super(WaveformDisplay, self).connection_changed(connected)

        if not build:
            return

        self._node = nodeFromAddress(self.channel)

        vb = QVBoxLayout()
        self.setLayout(vb)

        # -----------------------------------------------------------------------------

        gb = QGroupBox("Shaded regions indicate regions used for signal integration")
        vb.addWidget(gb)

        fl = QFormLayout()
        fl.setRowWrapPolicy(QFormLayout.DontWrapRows)
        fl.setFormAlignment(Qt.AlignHCenter | Qt.AlignTop)
        fl.setLabelAlignment(Qt.AlignRight)
        gb.setLayout(fl)

        self.sigPlot = PyDMWaveformPlotRanges(background=self.background)
        # TODO call shaded regions here too?

        self.sigPlot.addAxis(
            plot_data_item=None,
            name="adc_counts",
            orientation="left",
            label="ADC Counts",
            enable_auto_range=True,
        )

        self.sigPlot.setLabel("bottom", text="Time (ns)")
        self.sigPlot.addChannel(
            name="A",
            x_channel=f"{self.path}.Time",
            y_channel=f"{self.path}.{self.waveformNodeName}[0]",
            color=self.electrode_colors["A"],
            symbol="o",
            symbolSize=3,
            yAxisName="adc_counts",
        )
        self.sigPlot.addChannel(
            name="B",
            x_channel=f"{self.path}.Time",
            y_channel=f"{self.path}.{self.waveformNodeName}[1]",
            color=self.electrode_colors["B"],
            symbol="o",
            symbolSize=3,
            yAxisName="adc_counts",
        )
        self.sigPlot.addChannel(
            name="C",
            x_channel=f"{self.path}.Time",
            y_channel=f"{self.path}.{self.waveformNodeName}[2]",
            color=self.electrode_colors["C"],
            symbol="o",
            symbolSize=3,
            yAxisName="adc_counts",
        )
        self.sigPlot.addChannel(
            name="D",
            x_channel=f"{self.path}.Time",
            y_channel=f"{self.path}.{self.waveformNodeName}[3]",
            color=self.electrode_colors["D"],
            symbol="o",
            symbolSize=3,
            yAxisName="adc_counts",
        )
        fl.addWidget(self.sigPlot)

        self.sigPlot.setAutoRangeX(False)
        self.sigPlot.setMinXRange(0.0)
        self.sigPlot.setMaxXRange(300.0)

        self.sigPlot.setShowLegend(True)

        # -----------------------------------------------------------------------------

        gb = QGroupBox("Signal Plot Controls")
        vb.addWidget(gb)

        fl = QFormLayout()
        fl.setRowWrapPolicy(QFormLayout.DontWrapRows)
        fl.setFormAlignment(Qt.AlignHCenter | Qt.AlignTop)
        fl.setLabelAlignment(Qt.AlignRight)
        gb.setLayout(fl)

        rstButton = PyDMPushButton(label="Full Scale")
        rstButton.clicked.connect(self.resetScales)
        fl.addWidget(rstButton)

        # -----------------------------------------------------------------------------

    # Overwrite method without calling parent method.
    # Also do not use widget_ctx_menu. If we'd do so, there is no
    # simple way to get the menu from the pyqtgraph plot. We cannot
    # copy it it seems. If we don't and pass it on to the default
    # generate_context_menu, it will add the external tools entries.
    # If we do a second right click, it however gets the same instance
    # which already has the tools entries, and ends up adding them
    # a second time.
    # Real fix for this would be to find a way to not always re-recrate
    # the menu on every right click.
    def generate_context_menu(self):
        # Inherit menu from the pyqtgraph plot
        return self.sigPlot.getContextMenus(None)
