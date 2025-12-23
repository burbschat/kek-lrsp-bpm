import rogue
import pyrogue as pr
import json
import time


def filter_cal_block_nodes(adc_block):
    return [node for node in adc_block.Calibration.nodeList if node.name.startswith("CAL_BLOCK")]


def get_cal_block_coeffs(adc_block):
    cal_block_nodes = filter_cal_block_nodes(adc_block)
    result = {}
    for node in cal_block_nodes:
        result[node.name] = node.get()

    return result


class CalibrationCtrl(pr.Device):
    def __init__(self, adcBlocks, coeffFile, **kwargs):
        super().__init__(**kwargs)

        self._adcBlocks = adcBlocks
        self._adcTiles = []

        for channel, adc_block in self._adcBlocks.items():
            self._adcTiles += [adc_block.parent]

        self.add(
            pr.LocalVariable(
                name="CoeffFile",
                value=coeffFile,
            )
        )

        # Remove duplicates
        self._adcTiles = list(set(self._adcTiles))

        @self.command(description="Dump ADC calibration coefficients to file.")
        def dumpCoeffs():
            self._dumpCoeffs()

        @self.command(
            description="Load ADC calibration coefficients from file. This freezes the background calibration coefficients!"
        )
        def loadCoeffs():
            self._loadCoeffs()

        @self.command(description="Release all coefficient overrides, re-enabling the continous calibration routines.")
        def releaseCoeffOverrides():
            self._releaseAllOverrides()

    def _dumpCoeffs(self):
        result = {}
        coeff_file = self.CoeffFile.get()
        self._log.info(f"Dumping calibration coefficients to {coeff_file}")
        for adc_block_name, adc_block in self._adcBlocks.items():
            result[adc_block_name] = get_cal_block_coeffs(adc_block)

        with open(coeff_file, "w") as f:
            json.dump(result, f, indent=4)

        self._log.info("Done dumping calibration coefficients.")

    def _releaseAllOverrides(self):
        for adc_block in self._adcBlocks.values():
            for i in range(4):
                adc_block.Calibration.DisableCoefficientsOverride.set(i)

    def _loadCoeffs(self):
        coeff_file = self.CoeffFile.get()
        self._log.warning(
            f"Loading calibration coefficients from {coeff_file}. This also overrides the automatic calibration for GCB and TSCB (only!). This can be reversed using DisableCoefficientsOverride."
        )
        with open(coeff_file, "r") as f:
            d = json.load(f)

        for channel, coeffs in d.items():
            coeff_nodes = filter_cal_block_nodes(self._adcBlocks[channel])
            coeff_nodes = {node.name: node for node in coeff_nodes}
            # Make sure not froze, as otherwise TSCB coefficients cannot be written.
            self._adcBlocks[channel].Calibration.FreezeCalibration.set(0x0)
            # This may take a little tiny while to be applied? Poll status register.
            timeout = 5  # second
            wait_time = 0.1
            time_waited = 0
            while self._adcBlocks[channel].Calibration.CalFrozen.get() > 0:
                time.sleep(wait_time)
                time_waited += wait_time
                if wait_time >= timeout:
                    raise (TimeoutError(f"Calibration still not unfrozen after timeout ({timeout} s)"))

            max_attempts = 5
            for coeff_name, coeff_val in coeffs.items():
                attempt = 1
                if coeff_name in coeff_nodes.keys():
                    # This sometimes seemingly randomly fails, usually on the
                    # first write to TSCB coeff 4. No idea why. I guess it's
                    # just flaky? So re-try a bunch of times.
                    try:
                        coeff_nodes[coeff_name].set(coeff_val)
                    # Can't further narrow down error type as to Python it is
                    # presented as a GeneralError only. It should howver should
                    # be an error like 'checkTransaction: General Error: Verify
                    # error for block'.
                    except rogue.GeneralError as e:
                        self._log.warning(
                            f"Failed coefficient write for {coeff_nodes[coeff_name]}. This might just be flaky, try again (attempt {attempt}/{max_attempts})."
                        )
                        if attempt <= max_attempts:
                            attempt += 1
                            continue
                        else:
                            # Make sure to release all overrides
                            self._releaseAllOverrides()
                            raise e

            # Relseas the overrides for OCB1/2 as those can correctly function
            # without a steady input signal, which we do not have for the
            # stripline BPM application.
            self._log.info("Release overrides by loaded coefficients for OCB1 and OCB2 blocks.")
            for i in range(2):
                self._adcBlocks[channel].Calibration.DisableCoefficientsOverride.set(i)

        self._log.info("Done loading calibration coefficients.")
