from pydm.widgets.frame import PyDMFrame
from pydm.widgets import PyDMWaveformPlot, PyDMSpinbox, PyDMPushButton, PyDMScatterPlot, base
from pydm.widgets.scatterplot import ScatterPlotCurveItem
from pydm import PyDMChannel

from qtpy.QtCore import Qt
from qtpy.QtGui import QColor
from qtpy.QtWidgets import QVBoxLayout, QHBoxLayout, QFormLayout, QGroupBox, QDoubleSpinBox

from pyrogue.pydm.data_plugins.rogue_plugin import nodeFromAddress
from pyrogue.pydm.widgets import PyRogueLineEdit

import pyrogue as pr
import numpy as np
import json
import os

from pyqtgraph import ImageItem, InfiniteLine, ArrowItem, TextItem
from pyqtgraph.Qt import QtGui
import pyqtgraph as pg

dx = 6
dy = 4.2

class BpmPosScatter(PyDMFrame):

    def __init__(
        self,
        parent=None,
        init_channel=None,
        backgroundColor=[0, 0, 0, 255],
        electrodeMarkers = {
            "A": {"position": (-dx, dy), "angle": -90, "color": "royalblue"},
            "B": {"position": (dx, dy), "angle": -90, "color": "orange"},
            "C": {"position": (dx, -dy), "angle": 90, "color": "red"},
            "D": {"position": (-dx, -dy), "angle": 90, "color": "limegreen"},
        },
        indicateStorageBeam=True,
        invertX = False,
        nWindows=5,
        legendEnabled=True,
        fitLimEnabled=False,
        fitSigMapEnabled=True,
        posVarType = "Fit",  # Depends on variables available in pos compute module
        customColors = None,
    ):
        PyDMFrame.__init__(self, parent, init_channel)
        self.backgroundColor = backgroundColor
        self._node = None
        self.path = f"{self.channel}.SoftwarePositionCalculation"
        self.RxEnable = nodeFromAddress(f"{self.path}.RxEnable")

        self.electrode_markers = electrodeMarkers
        self.indicateStorageBeam = indicateStorageBeam
        self.invertX = invertX
        self.nWindows = nWindows
        self.legendEnabled = legendEnabled
        self.fitLimEnabled = fitLimEnabled
        self.fitSigMapEnabled = fitSigMapEnabled
        self.posVarType = posVarType
        self.posVarNames = {"x": f"Xpos{self.posVarType}", "y": f"Ypos{self.posVarType}"}
        self.customColors = customColors

        # Electrode number for which the map is displayed
        # TODO: Make this adjustable in the GUI
        self.map_electrode_nr = -1  # Negative means sum of all four maps

        # Channel for map name
        self.map_name = None
        self.map_name_channel = PyDMChannel(
            address=f"{self.path}.SignalMapName",
            value_slot=self.receive_map_name
        )
        self.map_name_channel.connect()

        # Channel for map data
        if self.fitSigMapEnabled:
            self.map_data = None
            self.map_data_channel = PyDMChannel(
                address=f"{self.path}.SignalMapData",
                value_slot=self.receive_map_data
            )
            self.map_data_channel.connect()

        # Channel for fit limit lines
        if self.fitLimEnabled:
            self.fit_lim_x = None
            self.fit_lim_x_channel = PyDMChannel(
                address=f"{self.path}.FitLimX",
                value_slot=self.receive_fit_lim_x
            )
            self.fit_lim_y = None
            self.fit_lim_y_channel = PyDMChannel(
                address=f"{self.path}.FitLimY",
                value_slot=self.receive_fit_lim_y
            )
            self.fit_lim_x_channel.connect()
            self.fit_lim_y_channel.connect()


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
        return self.scatterPlot.getContextMenus(None)

    def receive_map_name(self, new_value):
        if new_value is not None:
            self.map_name = new_value
            # TODO: Display map name in GUI?

    def receive_map_data(self, new_value):
        if new_value is not None:
            self.map_data = new_value
            self.set_background_image_map()

    def receive_fit_lim_x(self, new_value):
        if new_value is not None:
            self.fit_lim_x = new_value
            if self.fit_lim_x is not None:
                for i in range(2):
                    self.fit_lim_x_lines[i].setValue((-1)**i * self.fit_lim_x)

    def receive_fit_lim_y(self, new_value):
        if new_value is not None:
            self.fit_lim_y = new_value
            if self.fit_lim_y is not None:
                for i in range(2):
                    self.fit_lim_y_lines[i].setValue((-1)**i * self.fit_lim_y)

    def set_background_image_map(self):
        data_array = self.map_data
        # Extract X, Y coordinates and the data values (let's choose the third column for now)
        x_coords = data_array[:, 0]
        if self.invertX:
            print("Inverting map x-axis to match convention")
            x_coords = np.flip(x_coords)
        y_coords = data_array[:, 1]
        if self.map_electrode_nr < 0:
            # data_values = np.sum([data_array[:, 2 + i] for i in range(4)])
            data_values = 0
            for i in range(4):
                data_values += data_array[:, 2 + i]
        else:
            data_values = data_array[:, 2 + self.map_electrode_nr]  # Choose a data column

        # Find the unique x and y coordinates to create the grid
        x_unique = np.unique(x_coords)
        y_unique = np.unique(y_coords)

        # Create a 2D array (grid) for the data values
        # Initialize the grid with NaNs (or any placeholder value)
        grid = np.full((len(y_unique), len(x_unique)), np.nan)

        # Convert X and Y coordinates to indices for the grid
        x_indices = np.searchsorted(x_unique, x_coords)
        y_indices = np.searchsorted(y_unique, y_coords)

        # Assign the data values to the correct grid positions
        grid[y_indices, x_indices] = data_values

        tr = QtGui.QTransform()  # prepare ImageItem transformation:
        x_range = max(x_unique) - min(x_unique)
        x_n = len(x_unique)

        y_range = max(y_unique) - min(y_unique)
        y_n = len(y_unique)

        tr.scale(x_range/x_n, y_range/y_n)
        tr.translate(-x_n/2, -y_n/2) 

        self.bg_img.setImage(np.log(-grid), axisOrder='row-major')
        self.bg_img.setZValue(-100)
        self.bg_img.setTransform(tr)
        self.bg_img.setColorMap("viridis")

    def connection_changed(self, connected):
        build = (self._node is None) and (self._connected != connected and connected is True)
        super(BpmPosScatter, self).connection_changed(connected)

        if not build:
            return

        self._node = nodeFromAddress(self.channel)

        vb = QVBoxLayout()
        self.setLayout(vb)

        # -----------------------------------------------------------------------------

        gb = QGroupBox(f"Positions for {self.posVarType} computation")  # Can pass a string for this to display a title of the box
        vb.addWidget(gb)

        fl = QFormLayout()
        fl.setRowWrapPolicy(QFormLayout.DontWrapRows)
        fl.setFormAlignment(Qt.AlignHCenter | Qt.AlignTop)
        fl.setLabelAlignment(Qt.AlignRight)
        gb.setLayout(fl)

        self.scatterPlot = PyDMScatterPlot(background=self.backgroundColor)

        self.scatterPlot.addAxis(
                plot_data_item=None,
                name="pb_scatter_y",
                orientation="left",
                label="y (mm)",
        )
        # self.scatterPlot.setLabel("right", text='y (mm)')
        self.scatterPlot.setLabel("bottom", text='x (mm)')

        # Adjust hue/value rather than setting alpha as that would blend the
        # colors resulting in a huge mess when things overlap.
        def boost_color(c, sat_factor, val_factor):
            h, s, v, a = c.getHsv()
            s = min(int(s * sat_factor), 255)
            v = min(int(v * val_factor), 255)
            return QColor.fromHsv(h, s, v, a)

        for window_i in range(self.nWindows):
            if self.customColors is not None:
                base_color = self.customColors[window_i]
            else:
                base_color = pg.intColor(window_i, hues=self.nWindows)  # Get a color
            color = QColor(base_color)
            color = boost_color(color, 0.8, 0.8)
            color_recent = QColor(base_color)
            color_recent = boost_color(color_recent, 5, 5)

            pos_var_name_x = self.posVarNames["x"]
            pos_var_name_y = self.posVarNames["y"]

            self.scatterPlot.addChannel(
                name        = f'Window {window_i} pos.',
                yAxisName   = "pb_scatter_y",
                x_channel   = f'{self.path}.{pos_var_name_x}[{window_i}]',
                y_channel   = f'{self.path}.{pos_var_name_y}[{window_i}]',
                color       = color,
                symbol      = 'x',
                redraw_mode = ScatterPlotCurveItem.REDRAW_ON_BOTH,
                symbolSize = 10,
            )

            self.scatterPlot.addChannel(
                name        = f'Window {window_i} pos. recent',
                yAxisName   = "pb_scatter_y",
                x_channel   = f'{self.path}.{pos_var_name_x}[{window_i}]',
                y_channel   = f'{self.path}.{pos_var_name_y}[{window_i}]',
                color       = color_recent,
                symbol      = 'x',
                redraw_mode = ScatterPlotCurveItem.REDRAW_ON_BOTH,
                buffer_size = 5,  # Display last 5 shots in different color
                symbolSize = 10,
            )


        self.scatterPlot.setShowLegend(self.legendEnabled)

        self.scatterPlot.setMaxRedrawRate(100)

        # Initialize fresh background image object
        self.bg_img = ImageItem()
        axisToLink = self.scatterPlot.plotItem.axes.get("pb_scatter_y")["item"]
        axisToLink.linkedView().addItem(self.bg_img)

        if self.indicateStorageBeam:
            self.storage_beam_arrow_pos = (-8, 0)
            self.storage_beam_arrow = ArrowItem(
                pos=self.storage_beam_arrow_pos,  # tip position
                angle=0,
                headLen=20,
                brush='r'
            )
            axisToLink.linkedView().addItem(self.storage_beam_arrow)

            self.arrow_label = TextItem(
                text="Storage Beam",
                anchor=(-0.08, 0),   # position relative to text box
                angle=90,
                color='r'
            )
            self.arrow_label.setPos(*self.storage_beam_arrow_pos)
            axisToLink.linkedView().addItem(self.arrow_label)

        if self.electrode_markers is not None:
            self.electrode_marker_objs = {}
            for label_text, marker in self.electrode_markers.items():
                arrow_pos = marker["position"]
                arrow_angle = marker["angle"]
                color = marker["color"]
                label_shift = 0.3
                label_dx = - label_shift * np.cos(arrow_angle/360 * 2 * np.pi)
                label_dy = label_shift * np.sin(arrow_angle/360 * 2 * np.pi)
                label_pos = (arrow_pos[0] - label_dx, arrow_pos[1] - label_dy)

                arrow = ArrowItem(
                    pos=arrow_pos,
                    angle=arrow_angle,
                    headLen=12,
                    tipAngle=80,
                    brush=color,
                )

                label = TextItem(
                    text=label_text,
                    anchor=(0.5, 0.5),   # position relative to text box
                    angle=0,
                    color=color,
                )
                label.setPos(*label_pos)

                self.electrode_marker_objs[label_text] = (arrow, label)
                axisToLink.linkedView().addItem(arrow)
                axisToLink.linkedView().addItem(label)

        # Initialize fit limit lines
        if self.fitLimEnabled:
            self.fit_lim_x_lines = [InfiniteLine(angle=90), InfiniteLine(angle=90)]
            self.fit_lim_y_lines = [InfiniteLine(angle=0), InfiniteLine(angle=0)]
            for i in range(2):
                axisToLink.linkedView().addItem(self.fit_lim_x_lines[i])
                axisToLink.linkedView().addItem(self.fit_lim_y_lines[i])

        fl.addWidget(self.scatterPlot)
