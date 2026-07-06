from pydm import PyDMChannel
from pydm.tools import QWidget
from pydm.widgets import PyDMFrame, PyDMPushButton
from qtpy import QtCore
from qtpy.QtGui import QColor
from qtpy.QtWidgets import QHBoxLayout, QLabel, QVBoxLayout

from _GuiUtils import (
    SECTION_TITLE_STYLE,
    IndicatorWithCheckbox,
    IndicatorWithLabel,
    SpinboxWithLabel,
    FsmStateIndicator,
    ValueWithLabel,
)


class EvrDbSdControls(PyDMFrame):
    def __init__(self, parent=None, init_channel=None):
        super().__init__(parent=parent, init_channel=init_channel)
        # Call initial setup
        self.setup_ui()

    def setup_ui(self):
        self.main_layout = QHBoxLayout()
        self.main_layout.setContentsMargins(0, 0, 0, 0) 
        self.main_layout.setSpacing(2)
        self.setLayout(self.main_layout)

        self.state_indicator = FsmStateIndicator(
            text="DBSD FSM State",
            init_channel=self.channel,
            state_val_node="stateReg",
            state_name_node="stateStr",
        )
        self.main_layout.addWidget(self.state_indicator)


class EvrTrgsControls(PyDMFrame):
    def __init__(self, parent=None, init_channel=None):
        super().__init__(parent=parent, init_channel=init_channel)
        # Default value for number of trigger channels
        self.num_trigs = 1
        # Call initial setup
        self.setup_ui()
        # Setup channel to receive number of windows
        self.setup_num_trigs_channel()

    def setup_ui(self):
        self.main_layout = QVBoxLayout()
        self.main_layout.setContentsMargins(0, 0, 0, 0) 
        self.main_layout.setSpacing(0)
        self.setLayout(self.main_layout)

        # List to hold widgets so we can remove and re-add them on num_windows
        # update. All dynamic widgets must be in this list.
        self.dynamic_widgets = []

        # Construct static part of the UI
        self.last_event_code = ValueWithLabel(text="Last Event Code", init_channel=f"{self.channel}.eventCode")
        self.main_layout.addWidget(self.last_event_code)

    def setup_num_trigs_channel(self):
        self.num_trigs_channel = PyDMChannel(
            address=f"{self.channel}.NumTrigs",
            value_slot=self.receive_num_trigs,
            connection_slot=self.receive_num_trigs,
        )
        self.num_trigs_channel.connect()

    def receive_num_trigs(self, new_value):
        if new_value != self.num_trigs:
            self.num_trigs = new_value
            self.redraw_ui()

    def remove_dynamic_widgets(self):
        while len(self.dynamic_widgets) > 0:
            self.main_layout.removeWidget(self.dynamic_widgets.pop(0))

    def construct_dynamic_widgets(self):
        spin_box_step = 1
        for i in range(self.num_trigs):
            # Use container so we can easily remove this later
            sub_layout = QHBoxLayout()
            sub_layout.setContentsMargins(0, 0, 0, 0) 
            sub_layout.setAlignment(QtCore.Qt.AlignLeft)
            container = QWidget()
            container.setLayout(sub_layout)

            trig_label = QLabel(text=f"Trg. {i}")
            sub_layout.addWidget(trig_label)

            selected_event_code = SpinboxWithLabel(f"Event Code", init_channel=f"{self.channel}.trg{i}EventCode")
            selected_event_code.spinbox.setWriteOnPress(True)
            selected_event_code.spinbox.setShowStepExponent(False)
            selected_event_code.spinbox.setSingleStep(spin_box_step)
            sub_layout.addWidget(selected_event_code)
            trg_count = ValueWithLabel(f"Trigger Count", init_channel=f"{self.channel}.trg{i}Count")
            sub_layout.addWidget(trg_count)
            # The Resets are still borked on rogue/firmware side. Rogue writes
            # the whole register every time and thus previously written values
            # are written again... So call the function that works around this
            # instead (i.e. Reset not ResetReg).
            trg_count_reset = PyDMPushButton(
                label="Reset Count", pressValue=1, init_channel=f"{self.channel}.trg{i}Reset"
            )
            sub_layout.addWidget(trg_count_reset)

            self.dynamic_widgets.append(container)
            self.main_layout.addWidget(self.dynamic_widgets[-1])

    def redraw_ui(self):
        self.remove_dynamic_widgets()
        self.construct_dynamic_widgets()


class EvrDecoderControls(PyDMFrame):
    def __init__(self, parent=None, init_channel=None):
        super().__init__(parent=parent, init_channel=init_channel)
        # Call initial setup
        self.setup_ui()

    def setup_ui(self):
        self.main_layout = QVBoxLayout()
        self.main_layout.setAlignment(QtCore.Qt.AlignTop)
        self.setLayout(self.main_layout)

        self.evr_trgs_controls = EvrTrgsControls(init_channel=f"{self.channel}.EvrTrgs")
        self.main_layout.addWidget(self.evr_trgs_controls)
        self.evr_dbsd_controls = EvrDbSdControls(init_channel=f"{self.channel}.EvrDbSd")
        self.main_layout.addWidget(self.evr_dbsd_controls)


class EvrGtyControls(PyDMFrame):
    def __init__(self, parent=None, init_channel=None):
        super().__init__(parent=parent, init_channel=init_channel)
        # Call initial setup
        self.setup_ui()

    def setup_ui(self):
        self.main_layout = QVBoxLayout()
        self.main_layout.setContentsMargins(0, 0, 0, 0) 
        self.main_layout.setSpacing(0)
        self.setLayout(self.main_layout)

        self.qsfp_layout = QHBoxLayout()
        self.main_layout.addLayout(self.qsfp_layout)

        self.qsfp_mod_prs_l = IndicatorWithLabel(text="QSFP Module Present", init_channel=f"{self.channel}.qsfpModPrsL")
        # Low means present so invert colors
        self.qsfp_mod_prs_l.indicator.setState0Color(QColor("LawnGreen"))
        self.qsfp_mod_prs_l.indicator.setState1Color(QColor("Red"))
        self.qsfp_layout.addWidget(self.qsfp_mod_prs_l)

        # Give reset_l a more intuitive name (activate)...
        self.qsfp_mod_rst_l = IndicatorWithCheckbox(text="QSFP Module Activate", init_channel=f"{self.channel}.qsfpResetL")
        self.qsfp_layout.addWidget(self.qsfp_mod_rst_l)

        self.tx_layout = QHBoxLayout()
        self.main_layout.addLayout(self.tx_layout)
        self.rx_layout = QHBoxLayout()
        self.main_layout.addLayout(self.rx_layout)

        for dir, layout in [["tx", self.tx_layout], ["rx", self.rx_layout]]:
            reset_done = IndicatorWithLabel(
                text=f"{dir.upper()} Reset Done", init_channel=f"{self.channel}.{dir}ResetDone"
            )
            layout.addWidget(reset_done)
            pma_reset_done = IndicatorWithLabel(
                text=f"{dir.upper()} PMA Reset Done", init_channel=f"{self.channel}.{dir}PmaResetDone"
            )
            layout.addWidget(pma_reset_done)
            user_clk_active = IndicatorWithLabel(
                text=f"{dir.upper()} Usr Clk Active", init_channel=f"{self.channel}.{dir}UsrClkActive"
            )
            layout.addWidget(user_clk_active)
            _8b10b_en = IndicatorWithCheckbox(
                text=f"{dir.upper()} 8B10B Enable", init_channel=f"{self.channel}.{dir}8b10bEn"
            )
            layout.addWidget(_8b10b_en)
            polarity_invert = IndicatorWithCheckbox(
                text=f"{dir.upper()} Polarity Invert", init_channel=f"{self.channel}.{dir}Polarity"
            )
            layout.addWidget(polarity_invert)
            # 0 means non-inverted which is the expected value so invert colors
            polarity_invert.indicator.setState0Color(QColor("LawnGreen"))
            polarity_invert.indicator.setState1Color(QColor("Red"))

        # Indicators only available for RX
        self.rx_only_layout = QHBoxLayout()
        self.main_layout.addLayout(self.rx_only_layout)
        rx_cdr_stable = IndicatorWithLabel(text="RX CDR Stable", init_channel=f"{self.channel}.rxCdrStable")
        self.rx_only_layout.addWidget(rx_cdr_stable)
        rx_disp_error = IndicatorWithLabel(text="RX Parity Good", init_channel=f"{self.channel}.rxDispErr")
        # 0 mans no error so invert colors, also can take values > 1 so assign
        # color to more values
        rx_disp_error.indicator.setState0Color(QColor("LawnGreen"))
        rx_disp_error.indicator.setState1Color(QColor("Red"))
        rx_disp_error.indicator.setState2Color(QColor("Red"))
        rx_disp_error.indicator.setState3Color(QColor("Red"))
        self.rx_only_layout.addWidget(rx_disp_error)
        rx_dec_error = IndicatorWithLabel(text="RX Decode Good", init_channel=f"{self.channel}.rxDecErr")
        # 0 mans no error so invert colors, also can take values > 1 so assign
        # color to more values
        rx_dec_error.indicator.setState0Color(QColor("LawnGreen"))
        rx_dec_error.indicator.setState1Color(QColor("Red"))
        rx_dec_error.indicator.setState2Color(QColor("Red"))
        rx_dec_error.indicator.setState3Color(QColor("Red"))
        self.rx_only_layout.addWidget(rx_dec_error)
        rx_byte_aligned = IndicatorWithLabel(text="RX Byte Aligned", init_channel=f"{self.channel}.rxByteIsAligned")
        self.rx_only_layout.addWidget(rx_byte_aligned)
        rx_mcomma_align_en = IndicatorWithCheckbox(
            text="RX - Comma Align En.", init_channel=f"{self.channel}.rxMCommaAlignEn"
        )
        self.rx_only_layout.addWidget(rx_mcomma_align_en)
        rx_pcomma_align_en = IndicatorWithCheckbox(
            text="RX + Comma Align En.", init_channel=f"{self.channel}.rxPCommaAlignEn"
        )
        self.rx_only_layout.addWidget(rx_pcomma_align_en)


class EvrControls(PyDMFrame):
    def __init__(self, parent=None, init_channel=None, evr_gty_node=None, evr_decoder_node=None):
        super().__init__(parent=parent, init_channel=init_channel)
        self.evr_gty_node = evr_gty_node
        self.evr_decoder_node = evr_decoder_node
        # Call initial setup
        self.setup_ui()

    def setup_ui(self):
        self.main_layout = QVBoxLayout()
        self.main_layout.setAlignment(QtCore.Qt.AlignTop)
        self.setLayout(self.main_layout)

        self.lbl_title = QLabel("EVR Controls")
        self.lbl_title.setStyleSheet(SECTION_TITLE_STYLE)
        self.main_layout.addWidget(self.lbl_title)

        self.evr_gty_controls = EvrGtyControls(init_channel=f"{self.channel}.{self.evr_gty_node}")
        self.main_layout.addWidget(self.evr_gty_controls)
        self.evr_decoder_controls = EvrDecoderControls(init_channel=f"{self.channel}.{self.evr_decoder_node}")
        self.main_layout.addWidget(self.evr_decoder_controls)
