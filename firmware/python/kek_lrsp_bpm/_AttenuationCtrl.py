import pyrogue as pr

XRFDC_ADC_OVR_VOLTAGE_MASK = 0x0400_0000
XRFDC_ADC_OVR_RANGE_MASK = 0x0800_0000

# AND of all masks for all the sub ADCs, which is required for clearing the
# over range interrupt. The masks are named
# XRFDC_SUBADC<n>_IXR_DCDR_[OF|UF]_MASK
# Just clear all of them here (over and underflow).
SUBADC_OVR_RANGE_ALL = 0x00FF_0000


class AttenuationCtrl(pr.Device):
    def __init__(self, AdcBlocks, **kwargs):
        super().__init__(**kwargs)

        self._AdcBlocks = AdcBlocks
        self._OverVoltageSticky = {}
        self._intrStatus = {}

        for channel, adc_block in self._AdcBlocks.items():
            # Simply alias the variables
            self.add(
                pr.LinkVariable(
                    name=f"AttCh{channel}",
                    variable=adc_block.DSA.Attenuation,
                )
            )

            # Use a default argument to capture the current value as lambdas
            # and inner functions capture variables by reference, not by value.
            self.add(
                pr.LocalVariable(
                    name=f"OverRange{channel}",
                    type=bool,
                    mode="RO",
                    localGet=lambda channel=channel: self._getOverRange(channel=channel),
                )
            )

            self.add(
                pr.LocalVariable(
                    name=f"OverVolt{channel}",
                    type=bool,
                    mode="RO",
                    localGet=lambda channel=channel: self._getOverVolt(channel=channel),
                )
            )

            self.add(
                pr.LocalCommand(
                    name=f"OverRangeClear{channel}",
                    function=lambda channel=channel: self._clearOverRange(channel=channel),
                )
            )

            self.add(
                pr.LocalCommand(
                    name=f"OverVoltClear{channel}",
                    function=lambda channel=channel: self._clearOverVolt(channel=channel),
                )
            )

            # Initialize the over volt sticky dict
            self._OverVoltageSticky[channel] = False

    def _getOverRange(self, channel):
        adc_block = self._AdcBlocks[channel]
        self._intrStatus[channel] = adc_block.GetIntrStatus.get()
        return (self._intrStatus[channel] & XRFDC_ADC_OVR_RANGE_MASK) > 0

    def _getOverVolt(self, channel):
        adc_block = self._AdcBlocks[channel]
        self._intrStatus[channel] = adc_block.GetIntrStatus.get()
        # To make this sticky (in software), check the last state
        self._OverVoltageSticky[channel] = (
            (self._intrStatus[channel] & XRFDC_ADC_OVR_VOLTAGE_MASK) > 0
        ) or self._OverVoltageSticky[channel]
        return self._OverVoltageSticky[channel]

    def _clearOverRange(self, channel):
        adc_block = self._AdcBlocks[channel]
        adc_block.IntrClr.set(SUBADC_OVR_RANGE_ALL)

    def _clearOverVolt(self, channel):
        # Do a read as that is the only way to clear the over voltage flag.
        # Likely it is already cleard as one probably reads first, then notices
        # the flag, then clears it. But do the read just in case.
        adc_block = self._AdcBlocks[channel]
        self._intrStatus[channel] = adc_block.GetIntrStatus.get()
        # Clear the local sticky flag
        self._OverVoltageSticky[channel] = False
