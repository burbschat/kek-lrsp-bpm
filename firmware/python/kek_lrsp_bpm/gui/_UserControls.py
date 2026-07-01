# Control panel exposing trigger settings etc. to the user.

from pydm import PyDMChannel
from pydm.tools import QWidget
from _GuiUtils import (
    SECTION_TITLE_STYLE,
    IndicatorWithCheckbox,
    IndicatorWithLabel,
    SpinboxWithLabel,
    FsmStateIndicator,
    ValueWithLabel,
)
from _WaveformDisplay import WaveformDisplay
from _EvrControls import EvrControls

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


# This is sort of an experiment to see if I can dynamically adjust the UI
# depending on the number of windows. Stuff like the debug tree and at this
# point also the scatter plots I believe do just require a full restart of the
# GUI though...
# Actually this also does not quite work when the widget is supposed to read a
# value as apparently something in the application keeps track of the variable
# tree and that is not updated even when the rogue backend server is
# re-connected (maybe there is an option for that?).
# Alternative might be to always have all window vars/widgets and
# enable/disable as required? Probably not worth the effort though...
class PoscalcWindowControls(PyDMFrame):
    def __init__(self, parent=None, init_channel=None):
        super().__init__(parent=parent, init_channel=init_channel)
        # Default value for number of windows
        self.num_windows = 2
        # Call initial setup
        self.setup_ui()
        # Setup channel to receive number of windows
        self.setup_num_windows_channel()

    def setup_ui(self):
        # Construct main layout
        self.main_layout = QVBoxLayout()
        self.main_layout.setAlignment(QtCore.Qt.AlignTop)
        self.main_layout.setContentsMargins(0, 0, 0, 0)
        self.main_layout.setSpacing(0)
        self.setLayout(self.main_layout)

        # List to hold widgets so we can remove and re-add them on num_windows
        # update. All dynamic widgets must be in this list.
        self.dynamic_widgets = []

        # Construct static part of the UI
        # self.redraw_button = QPushButton("Redraw", self)  # Redraw button for debug
        # self.main_layout.addWidget(self.redraw_button)
        # self.redraw_button.clicked.connect(self.redraw_ui)

    def setup_num_windows_channel(self):
        self.num_windows_channel = PyDMChannel(
            address=f"{self.channel}.NumWindows",
            value_slot=self.receive_num_windows,
            connection_slot=self.receive_num_windows,
        )
        self.num_windows_channel.connect()

    def receive_num_windows(self, new_value):
        if new_value != self.num_windows:
            self.num_windows = new_value
            self.redraw_ui()

    def remove_dynamic_widgets(self):
        while len(self.dynamic_widgets) > 0:
            self.main_layout.removeWidget(self.dynamic_widgets.pop(0))

    def construct_dynamic_widgets(self):
        spin_box_step = 1
        for i in range(self.num_windows):
            # Use container so we can easily remove this later
            sub_layout = QHBoxLayout()
            sub_layout.setContentsMargins(0, 0, 0, 0)
            container = QWidget()
            container.setLayout(sub_layout)

            window_label = QLabel(text=f"Wd. {i}")
            sub_layout.addWidget(window_label)

            window_start = SpinboxWithLabel(f"Start (ns)", init_channel=f"{self.channel}.WindowOpen[{i}]")
            window_start.spinbox.setWriteOnPress(True)
            window_start.spinbox.setShowStepExponent(False)
            window_start.spinbox.setSingleStep(spin_box_step)
            sub_layout.addWidget(window_start)

            window_end = SpinboxWithLabel(f"End (ns)", init_channel=f"{self.channel}.WindowClose[{i}]")
            window_end.spinbox.setWriteOnPress(True)
            window_end.spinbox.setShowStepExponent(False)
            window_end.spinbox.setSingleStep(spin_box_step)
            sub_layout.addWidget(window_end)

            # Only make sense when charge threshold used but we would like to
            # get rid of that anyways so leave those widgets disabled for
            # now...
            # charge_threshold = SpinboxWithLabel(f"Wd. {i} C Thresh.", init_channel=f"{self.channel}.ChargeThreshold[{i}]")
            # charge_threshold.spinbox.setWriteOnPress(True)
            # charge_threshold.spinbox.setShowStepExponent(False)
            # charge_threshold.spinbox.setSingleStep(1)
            # sub_layout.addWidget(charge_threshold)
            #
            # empty_cnt = ValueWithLabel(f"Wd. {i} Empty Cnt.", init_channel=f"{self.channel}.EmptyShotsSinceLast[{i}]")
            # sub_layout.addWidget(empty_cnt)

            self.dynamic_widgets.append(container)
            self.main_layout.addWidget(self.dynamic_widgets[-1])

    def redraw_ui(self):
        self.remove_dynamic_widgets()
        self.construct_dynamic_widgets()


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
    def __init__(self, parent=None, init_channel=None):
        super().__init__(parent=parent, init_channel=init_channel)
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
            parent=None,
            init_channel=self.channel,
            nodePath="SoftwarePositionCalculation",
            waveformNodeName="WaveformData",
            customRegionColors=["red", "royalblue"],
        )
        self.attenuation_controls_and_waveform_layout.addWidget(self.waveform_display)
        self.upper_layout.addLayout(self.attenuation_controls_and_waveform_layout)

        # EVR stuff is kept separately for reusability as it is technically not
        # specific to this application.
        self.evr_controls = EvrControls(
            init_channel=self.channel, evr_gty_node="RFSoC.EvrGty", evr_decoder_node="RFSoC.Application.EvrDecoder"
        )
        self.lower_layout.addWidget(self.evr_controls)
