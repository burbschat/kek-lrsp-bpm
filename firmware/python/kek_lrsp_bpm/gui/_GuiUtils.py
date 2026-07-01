from pydm.widgets import PyDMCheckbox, PyDMLabel, PyDMMultiStateIndicator, PyDMPushButton, PyDMSpinbox
from pydm.widgets.frame import PyDMFrame
from qtpy import QtCore
from qtpy.QtGui import QColor
from qtpy.QtWidgets import QHBoxLayout, QLabel

SECTION_TITLE_STYLE = "\
            QLabel {\
                qproperty-alignment: AlignCenter;\
                border: 2px solid Black;\
                padding: 5px 0px;\
                max-height: 25px;\
                font-size: 14px;\
            }"

INDICATOR_HEIGHT_SCALE = 1.3


class IndicatorWithCheckbox(PyDMFrame):
    def __init__(self, text, parent=None, init_channel=None):
        super().__init__(parent=parent, init_channel=init_channel)
        self.text = text
        self.setup_ui()

    def setup_ui(self):
        self.horizontal_layout = QHBoxLayout()
        self.horizontal_layout.setContentsMargins(0, 0, 0, 0) 
        self.setLayout(self.horizontal_layout)
        self.indicator = PyDMMultiStateIndicator(init_channel=self.channel)
        self.indicator.setState0Color(QColor("Red"))
        self.indicator.setState1Color(QColor("LawnGreen"))
        fm = self.fontMetrics()
        h = int(fm.height() * INDICATOR_HEIGHT_SCALE)
        self.indicator.setFixedSize(h, h)
        self.horizontal_layout.addWidget(self.indicator)
        self.checkbox = PyDMCheckbox(self.text, init_channel=self.channel)
        self.horizontal_layout.addWidget(self.checkbox)


class IndicatorWithLabel(PyDMFrame):
    def __init__(self, text, parent=None, init_channel=None):
        super().__init__(parent=parent, init_channel=init_channel)
        self.text = text
        self.setup_ui()

    def setup_ui(self):
        self.horizontal_layout = QHBoxLayout()
        self.horizontal_layout.setContentsMargins(0, 0, 0, 0) 
        self.setLayout(self.horizontal_layout)
        self.indicator = PyDMMultiStateIndicator(init_channel=self.channel)
        self.indicator.setState0Color(QColor("Red"))
        self.indicator.setState1Color(QColor("LawnGreen"))
        fm = self.fontMetrics()
        h = int(fm.height() * INDICATOR_HEIGHT_SCALE)
        self.indicator.setFixedSize(h, h)
        self.horizontal_layout.addWidget(self.indicator)
        self.label = QLabel(self.text)
        self.horizontal_layout.addWidget(self.label)


class ValueWithLabel(PyDMFrame):
    def __init__(self, text, parent=None, init_channel=None):
        super().__init__(parent=parent, init_channel=init_channel)
        self.text = text
        self.setup_ui()

    def setup_ui(self):
        self.horizontal_layout = QHBoxLayout()
        self.horizontal_layout.setContentsMargins(0, 0, 0, 0) 
        self.horizontal_layout.setAlignment(QtCore.Qt.AlignLeft)
        self.setLayout(self.horizontal_layout)
        self.label = QLabel(self.text)
        self.horizontal_layout.addWidget(self.label)
        self.value_label = PyDMLabel(init_channel=self.channel)
        self.horizontal_layout.addWidget(self.value_label)


class SpinboxWithLabel(PyDMFrame):
    def __init__(self, text, parent=None, init_channel=None, val_min=0, val_max=1e6, precision=3):
        super().__init__(parent=parent, init_channel=init_channel)
        self.text = text
        self.val_min = val_min
        self.val_max = val_max
        self.precision = precision
        self.setup_ui()

    def setup_ui(self):
        self.horizontal_layout = QHBoxLayout()
        self.horizontal_layout.setContentsMargins(0, 0, 0, 0) 
        self.horizontal_layout.setAlignment(QtCore.Qt.AlignLeft)
        self.setLayout(self.horizontal_layout)
        self.label = QLabel(self.text)
        self.horizontal_layout.addWidget(self.label)
        self.spinbox = PyDMSpinbox(init_channel=self.channel)
        self.spinbox.setUserMinimum(self.val_min)
        self.spinbox.setUserMaximum(self.val_max)
        self.spinbox.setUserDefinedLimits(True)
        self.spinbox.precisionFromPV = False
        self.spinbox.setPrecision(self.precision)
        self.horizontal_layout.addWidget(self.spinbox)


class FsmStateIndicator(PyDMFrame):
    def __init__(self, text, parent=None, state_val_node=None, state_name_node=None, init_channel=None):
        super().__init__(parent=parent, init_channel=init_channel)
        self.state_val_channel = f"{self.channel}.{state_val_node}"
        self.state_name_channel = f"{self.channel}.{state_name_node}"
        self.text = text
        self.setup_ui()

    def setup_ui(self):
        self.horizontal_layout = QHBoxLayout()
        self.horizontal_layout.setContentsMargins(0, 0, 0, 0) 
        self.horizontal_layout.setAlignment(QtCore.Qt.AlignLeft)
        self.setLayout(self.horizontal_layout)
        self.indicator = PyDMMultiStateIndicator(init_channel=self.state_val_channel)
        self.indicator.setState0Color(QColor("LawnGreen"))
        self.indicator.setState1Color(QColor("Blue"))
        self.indicator.setState2Color(QColor("Orange"))
        self.indicator.setState3Color(QColor("Red"))
        fm = self.fontMetrics()
        h = int(fm.height() * INDICATOR_HEIGHT_SCALE)
        self.indicator.setFixedSize(h, h)
        self.horizontal_layout.addWidget(self.indicator)
        self.label = QLabel(self.text)
        self.horizontal_layout.addWidget(self.label)
        self.value_label = PyDMLabel(init_channel=self.state_name_channel)
        self.horizontal_layout.addWidget(self.value_label)


