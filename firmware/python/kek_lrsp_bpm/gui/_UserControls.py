# Control panel exposing trigger settings etc. to the user.

from pydm import PyDMChannel
from pydm.tools import QWidget
from kek_lrsp_bpm.gui._GuiUtils import (
    SECTION_TITLE_STYLE,
    EnumComboBoxWithLabel,
    IndicatorWithCheckbox,
    IndicatorWithLabel,
    SpinboxWithLabel,
    FsmStateIndicator,
    ValueWithLabel,
)
from kek_lrsp_bpm.gui._WaveformDisplay import WaveformDisplay
from kek_lrsp_bpm.gui._EvrControls import EvrControls

from pydm.widgets import PyDMCheckbox, PyDMPushButton
from pydm.widgets.frame import PyDMFrame
from qtpy import QtCore
from qtpy.QtGui import QColor
from qtpy.QtWidgets import QLabel, QVBoxLayout, QHBoxLayout


class TriggerControls(PyDMFrame):
    def __init__(self, parent=None, init_channel=None):
        super().__init__(parent=parent, init_channel=init_channel)
        # Assemble base path for trigger controls module
        self.path = f"{self.channel}.RFSoC.Application.ReadoutCtrl"
        # Assemble the widgets
        self.setup_ui()

    def setup_ui(self):
        self.main_layout = QVBoxLayout()
        self.main_layout.setAlignment(QtCore.Qt.AlignTop)
        self.main_layout.setContentsMargins(0, 0, 0, 0)
        self.main_layout.setSpacing(2)
        self.setLayout(self.main_layout)

        self.lbl_title = QLabel("Trigger Controls")
        self.lbl_title.setStyleSheet(SECTION_TITLE_STYLE)
        self.main_layout.addWidget(self.lbl_title)

        self.trig_arm_button = PyDMPushButton(label="Arm Trigger", pressValue=1, init_channel=f"{self.path}.TrigInArm")
        self.main_layout.addWidget(self.trig_arm_button)

        self.trig_force_button = PyDMPushButton(label="Force Trigger", pressValue=1, init_channel=f"{self.path}.SwTrig")
        self.main_layout.addWidget(self.trig_force_button)

        self.trig_fsm_state = FsmStateIndicator(
            text="Trigger FSM State",
            init_channel=self.path,
            state_val_node="stateReg",
            state_name_node="stateStr",
        )
        self.main_layout.addWidget(self.trig_fsm_state)

        self.trig_cont_setting = IndicatorWithCheckbox(text="Continous Trigger", init_channel=f"{self.path}.SetKeepArm")
        self.main_layout.addWidget(self.trig_cont_setting)

        self.trig_inv_polarity = self.checkbox = PyDMCheckbox(
            "Invert Polarity", init_channel=f"{self.path}.TrigInPolarity"
        )
        self.main_layout.addWidget(self.trig_inv_polarity)

        self.trig_source_combo_box = EnumComboBoxWithLabel(text="Trigger source", init_channel=f"{self.path}.TrigInSelIdx")
        self.main_layout.addWidget(self.trig_source_combo_box)

        self.trig_status = ValueWithLabel(text="Trigger Signal Value", init_channel=f"{self.path}.TrigInSel")
        self.main_layout.addWidget(self.trig_status)

        self.trig_delay_spinbox = SpinboxWithLabel(
            text="Trigger Delay (us)", init_channel=f"{self.path}.TrigRingBufDly"
        )
        self.trig_delay_spinbox.spinbox.setWriteOnPress(True)
        self.trig_delay_spinbox.spinbox.setShowStepExponent(False)
        self.trig_delay_spinbox.spinbox.setSingleStep(0.1)
        self.main_layout.addWidget(self.trig_delay_spinbox)

        self.trig_delay_spinbox_raw = SpinboxWithLabel(
            text="Trigger Delay (clock cycles)", init_channel=f"{self.path}.TrigRingBufDlyRaw"
        )
        self.trig_delay_spinbox_raw.spinbox.setWriteOnPress(True)
        self.trig_delay_spinbox_raw.spinbox.setShowStepExponent(False)
        self.trig_delay_spinbox_raw.spinbox.setSingleStep(1)
        self.main_layout.addWidget(self.trig_delay_spinbox_raw)

        self.trig_deglitch_spinbox = SpinboxWithLabel(
            text="Trigger deglitch (us)", init_channel=f"{self.path}.deglitchLen"
        )
        self.trig_deglitch_spinbox.spinbox.setWriteOnPress(True)
        self.trig_deglitch_spinbox.spinbox.setShowStepExponent(False)
        self.trig_deglitch_spinbox.spinbox.setSingleStep(0.1)
        self.main_layout.addWidget(self.trig_deglitch_spinbox)

        self.trig_deglitch_spinbox_raw = SpinboxWithLabel(
            text="Trigger deglitch (clock cycles)", init_channel=f"{self.path}.deglitchLenRaw"
        )
        self.trig_deglitch_spinbox_raw.spinbox.setWriteOnPress(True)
        self.trig_deglitch_spinbox_raw.spinbox.setShowStepExponent(False)
        self.trig_deglitch_spinbox_raw.spinbox.setSingleStep(1)
        self.main_layout.addWidget(self.trig_deglitch_spinbox_raw)

# Dynamically adding/removing widgets from the layout did not work so well
# (wanted to get the number of windows from a pydm channel and then construct
# the layout according to it...). So instead instantiate a fixed number of
# widgets and then hide the unused ones.
class PoscalcWindowControls(PyDMFrame):
    def __init__(self, parent=None, init_channel=None, max_num_windows=8):
        super().__init__(parent=parent, init_channel=init_channel)

        self._max_windows = max_num_windows

        self.num_windows = 2

        self.setup_ui()
        self.setup_num_windows_channel()

    def setup_ui(self):
        self.main_layout = QVBoxLayout()
        self.main_layout.setAlignment(QtCore.Qt.AlignTop)
        self.main_layout.setContentsMargins(0, 0, 0, 0)
        self.main_layout.setSpacing(0)
        self.setLayout(self.main_layout)

        self.window_widgets = {
            "ns": [],
            "raw": [],
        }

        for units in ["ns", "raw"]:
            for i in range(self._max_windows):
                container = self.construct_window_widget(units, i)
                self.window_widgets[units].append(container)
                self.main_layout.addWidget(container)

        self.update_visibility()

    def construct_window_widget(self, units, i):
        sub_layout = QHBoxLayout()
        sub_layout.setContentsMargins(0, 0, 0, 0)

        container = QWidget()
        container.setLayout(sub_layout)

        window_label = QLabel(text=f"Wd. {i}")
        sub_layout.addWidget(window_label)

        window_start = SpinboxWithLabel(
            f"Start ({units})",
            init_channel=(f"{self.channel}.WindowOpen" f"{'Raw' if units == 'raw' else ''}[{i}]"),
        )
        window_start.spinbox.setWriteOnPress(True)
        window_start.spinbox.setShowStepExponent(False)
        window_start.spinbox.setSingleStep(1)
        sub_layout.addWidget(window_start)

        window_end = SpinboxWithLabel(
            f"End ({units})",
            init_channel=(f"{self.channel}.WindowClose" f"{'Raw' if units == 'raw' else ''}[{i}]"),
        )
        window_end.spinbox.setWriteOnPress(True)
        window_end.spinbox.setShowStepExponent(False)
        window_end.spinbox.setSingleStep(1)
        sub_layout.addWidget(window_end)

        return container

    def setup_num_windows_channel(self):
        self.num_windows_channel = PyDMChannel(
            address=f"{self.channel}.NumWindows",
            value_slot=self.receive_num_windows,
        )
        self.num_windows_channel.connect()

    def receive_num_windows(self, new_value):
        try:
            new_value = int(new_value)
        except (TypeError, ValueError):
            return

        if new_value == self.num_windows:
            return

        self.num_windows = new_value
        self.update_visibility()

    def update_visibility(self):
        for widgets in self.window_widgets.values():
            for i, widget in enumerate(widgets):
                widget.setVisible(i < self.num_windows)


class PoscalcControls(PyDMFrame):
    def __init__(self, parent=None, init_channel=None):
        super().__init__(parent=parent, init_channel=init_channel)
        # Assemble base path for trigger controls module
        self.path = f"{self.channel}.SoftwarePositionCalculation"
        # Call initial setup
        self.setup_ui()

    def setup_ui(self):
        # Construct main layout
        self.main_layout = QVBoxLayout()
        self.main_layout.setAlignment(QtCore.Qt.AlignTop)
        self.main_layout.setContentsMargins(0, 0, 0, 0)
        self.main_layout.setSpacing(0)
        self.setLayout(self.main_layout)

        self.lbl_title = QLabel("Position Computation")
        self.lbl_title.setStyleSheet(SECTION_TITLE_STYLE)
        self.main_layout.addWidget(self.lbl_title)

        self.frames_received_label = ValueWithLabel(text="Frames Received", init_channel=f"{self.path}.FrameCount")
        self.main_layout.addWidget(self.frames_received_label)
        self.error_count_label = ValueWithLabel(text="Error Count", init_channel=f"{self.path}.ErrorCount")
        self.main_layout.addWidget(self.error_count_label)
        self.bytes_received_label = ValueWithLabel(text="Bytes Received", init_channel=f"{self.path}.ByteCount")
        self.main_layout.addWidget(self.bytes_received_label)

        # Those can be adjusted but should in general be fixed so only display
        # them and not allow for modification by user (also not sure what
        # widget to use to modify array type)...
        self.bytes_received_label = ValueWithLabel(
            text="Channel Corrections", init_channel=f"{self.path}.ChannelCorrections"
        )
        self.main_layout.addWidget(self.bytes_received_label)

        self.bytes_received_label = ValueWithLabel(text="Last Shot ID", init_channel=f"{self.path}.ShotID")
        self.main_layout.addWidget(self.bytes_received_label)

        self.window_controls = PoscalcWindowControls(init_channel=self.path)
        self.main_layout.addWidget(self.window_controls)


class AttenuationControls(PyDMFrame):
    def __init__(self, parent=None, init_channel=None):
        super().__init__(parent=parent, init_channel=init_channel)
        # Assemble base path for trigger controls module
        self.path = f"{self.channel}.AttenuationCtrl"
        # Call initial setup
        self.setup_ui()

    def setup_ui(self):
        # Construct main layout
        self.main_layout = QVBoxLayout()
        self.main_layout.setAlignment(QtCore.Qt.AlignTop)
        self.main_layout.setContentsMargins(0, 0, 0, 0)
        self.main_layout.setSpacing(2)
        self.setLayout(self.main_layout)

        self.lbl_title = QLabel("Attenuation")
        self.lbl_title.setStyleSheet(SECTION_TITLE_STYLE)
        self.main_layout.addWidget(self.lbl_title)

        self.channel_layouts = []
        for ch in ["A", "B", "C", "D"]:
            channel_layout = QHBoxLayout()

            label = QLabel(text=f"Ch {ch}")
            channel_layout.addWidget(label)

            spin_box = SpinboxWithLabel(
                text=f"Att. (dB)", init_channel=f"{self.path}.AttCh{ch}", val_max=27, val_min=0, precision=0
            )
            spin_box.spinbox.setWriteOnPress(True)
            spin_box.spinbox.setShowStepExponent(False)
            spin_box.spinbox.setSingleStep(1)
            channel_layout.addWidget(spin_box)

            overrange_indicator = IndicatorWithLabel("Overrange", init_channel=f"{self.path}.OverRange{ch}")
            overrange_indicator.indicator.setState0Color(QColor("Grey"))
            overrange_indicator.indicator.setState1Color(QColor("Red"))
            channel_layout.addWidget(overrange_indicator)
            overrange_clear = PyDMPushButton(
                label="clear", pressValue=1, init_channel=f"{self.path}.OverRangeClear{ch}"
            )
            channel_layout.addWidget(overrange_clear)

            overvolt_indicator = IndicatorWithLabel("Overvolt", init_channel=f"{self.path}.OverVolt{ch}")
            overvolt_indicator.indicator.setState0Color(QColor("Grey"))
            overvolt_indicator.indicator.setState1Color(QColor("Red"))
            channel_layout.addWidget(overvolt_indicator)
            overvolt_clear = PyDMPushButton(label="clear", pressValue=1, init_channel=f"{self.path}.OverVoltClear{ch}")
            channel_layout.addWidget(overvolt_clear)

            self.channel_layouts.append(channel_layout)
            self.main_layout.addLayout(self.channel_layouts[-1])


# Frame uniting all available controls frames
class UserControls(PyDMFrame):
    def __init__(self, parent=None, init_channel=None, backgroundColor=None):
        super().__init__(parent=parent, init_channel=init_channel)
        self.backgroundColor = backgroundColor
        self.setup_ui()

    def setup_ui(self):
        self.main_layout = QVBoxLayout()
        self.main_layout.setAlignment(QtCore.Qt.AlignTop)
        self.setLayout(self.main_layout)

        self.upper_layout = QHBoxLayout()
        self.main_layout.addLayout(self.upper_layout)
        self.lower_layout = QHBoxLayout()
        self.main_layout.addLayout(self.lower_layout)

        self.trigger_controls = TriggerControls(init_channel=self.channel)
        self.upper_layout.addWidget(self.trigger_controls)
        self.poscalc_controls = PoscalcControls(init_channel=self.channel)
        self.upper_layout.addWidget(self.poscalc_controls)

        self.attenuation_controls_and_waveform_layout = QVBoxLayout()
        self.attenuation_controls = AttenuationControls(init_channel=self.channel)
        self.attenuation_controls_and_waveform_layout.addWidget(self.attenuation_controls)

        # Put waveform display to be able to observe the waveforms while
        # adjusting settings.
        self.waveform_display = WaveformDisplay(
            init_channel=self.channel,
            nodePath="SoftwarePositionCalculation",
            waveformNodeName="WaveformData",
            # customRegionColors=["red", "royalblue"],
            backgroundColor=self.backgroundColor,
        )
        self.attenuation_controls_and_waveform_layout.addWidget(self.waveform_display)
        self.upper_layout.addLayout(self.attenuation_controls_and_waveform_layout)

        # EVR stuff is kept separately for reusability as it is technically not
        # specific to this application.
        self.evr_controls = EvrControls(
            init_channel=self.channel, evr_gty_node="RFSoC.EvrGty", evr_decoder_node="RFSoC.Application.EvrDecoder"
        )
        self.lower_layout.addWidget(self.evr_controls)
