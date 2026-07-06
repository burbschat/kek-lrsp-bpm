# TODO: Not sure how close the RFDC PLL config frequencies should be to the
# actual sample rate. If problems with e.g. spurs are encountered, perhaps
# try adjusting the RFDC IP cores config. However I do not believe that
# this matters much as all the dividers etc. in the PLLs should be the
# same. Or does it?
LMK_CONFIGS = {
    "default": {"file": "config/lmk/HexRegisterValues_CLKin0-125MHz_CLKin1-10MHz.txt", "out_f_MHz": 500},
    # Below are fractional PLL configs which make it pretty much impossible
    # to configure for use of both the internal 10MHz oscillator and
    # external clock signal. The former is therefore not usable with those.
    # This is required as the LMK on the RFSoC4x2 does not allow to simply
    # bypass the PLL and use the clock signal directly.
    "skbrf": {"file": "config/lmk/HexRegisterValues_CLKin0-508MHz89Approx.txt", "out_f_MHz": 508.89},
    "linacrf": {"file": "config/lmk/HexRegisterValues_CLKin0-114MHz24Approx.txt", "out_f_MHz": 514.08},
    "linacrf_half": {"file": "config/lmk/HexRegisterValues_CLKin0-57MHz12Approx.txt", "out_f_MHz": 514.08},
    "oc520": {"file": "config/lmk/HexRegisterValues_CLKin0-125MHz_CLKin1-10MHz_OC520MHz.txt", "out_f_MHz": 520},
}

def get_sr_lmkconfig(pllConfigName):
    lmk_config_file = LMK_CONFIGS[pllConfigName]["file"]
    # ADC/DAC(?) sampling rate is reference clock times eight and thus depends
    # on PLL config! Multiplier defined in RFDC IP core config's PLL settings.
    refclock_freq = LMK_CONFIGS[pllConfigName]["out_f_MHz"] * 1e6  # in Hz
    # Multiplication factor must match RfDC IP core config!
    # With 10 + lock on 509 we are thus actually overclocking (a little bit)
    sampleRate = refclock_freq * 10  # in Hz

    return lmk_config_file, sampleRate


def get_injplike_pvmap(poscalcPath, hardDisablePoly, hardDisableFit, nWindows, enBackwardCompPVs=True):
    # Build map subset of available rogue variables to EPICS PVs
    pvMap = {}

    # Attenuators
    pvMap["Root.AttenuationCtrl.AttChA"] = "AttChA"
    pvMap["Root.AttenuationCtrl.AttChB"] = "AttChB"
    pvMap["Root.AttenuationCtrl.AttChC"] = "AttChC"
    pvMap["Root.AttenuationCtrl.AttChD"] = "AttChD"

    pvMap[f"{poscalcPath}.ChannelCorrections"] = "CHCORR"

    if not hardDisablePoly:
        pvMap[f"{poscalcPath}.polyEn"] = "POLYEN"
    if not hardDisableFit:
        pvMap[f"{poscalcPath}.fitEn"] = "FITEN"

    pvMap[f"{poscalcPath}.NumWindows"] = "NWIN"
    for i in range(nWindows):
        pvMap[f"{poscalcPath}.WindowOpen[{i}]"] = f"WINOP_{i+1}"
        pvMap[f"{poscalcPath}.WindowClose[{i}]"] = f"WINCL_{i+1}"
        pvMap[f"{poscalcPath}.WindowOpenRaw[{i}]"] = f"WINOP:RAW_{i+1}"
        pvMap[f"{poscalcPath}.WindowCloseRaw[{i}]"] = f"WINCL:RAW_{i+1}"
        pvMap[f"{poscalcPath}.Sums[{i}]"] = f"SUMS_{i+1}"
        pvMap[f"{poscalcPath}.SumsSq[{i}]"] = f"SUMSSQ_{i+1}"
        pvMap[f"{poscalcPath}.Charge[{i}]"] = f"Q_{i+1}"
        pvMap[f"{poscalcPath}.ChargeThreshold[{i}]"] = f"QTHR_{i+1}"
        if not hardDisablePoly:
            pvMap[f"{poscalcPath}.XposPoly[{i}]"] = f"X_Poly{i+1}"
            pvMap[f"{poscalcPath}.YposPoly[{i}]"] = f"Y_Poly{i+1}"
        if not hardDisableFit:
            pvMap[f"{poscalcPath}.XposFit[{i}]"] = f"X_{i+1}"
            pvMap[f"{poscalcPath}.YposFit[{i}]"] = f"Y_{i+1}"
            pvMap[f"{poscalcPath}.XposFitMaskedStd[{i}]"] = f"XMSKSTD_{i+1}"
            pvMap[f"{poscalcPath}.YposFitMaskedStd[{i}]"] = f"YMSKSTD_{i+1}"
            pvMap[f"{poscalcPath}.XposFitMaskedMean[{i}]"] = f"XMSKMEAN_{i+1}"
            pvMap[f"{poscalcPath}.YposFitMaskedMean[{i}]"] = f"YMSKMEAN_{i+1}"
            for j in range(4):
                pvMap[f"{poscalcPath}.XposFitMasked{0xf^(0b1<<j):04b}[{i}]"] = f"XMSK{0xf^(0b1<<j):04b}_{i+1}"
                pvMap[f"{poscalcPath}.YposFitMasked{0xf^(0b1<<j):04b}[{i}]"] = f"YMSK{0xf^(0b1<<j):04b}_{i+1}"

    # First bunch only PVs (without numbers) for backwards compatability
    if enBackwardCompPVs and not hardDisableFit:
        pvMap[f"{poscalcPath}.XposFit[{0}]"] = f"X"
        pvMap[f"{poscalcPath}.YposFit[{0}]"] = f"Y"

    pvMap[f"{poscalcPath}.ResultsVector"] = "RESWAV"

    return pvMap
