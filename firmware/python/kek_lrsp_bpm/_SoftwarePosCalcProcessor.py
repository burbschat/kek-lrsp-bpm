import rogue.interfaces.stream as ris
import pyrogue as pr
import numpy as np
import importlib
from sklearn.preprocessing import PolynomialFeatures
import json
import os

# TODO: This module has become way to complicated. Split into different
# processors depending on the exact application.

def load_poly_coeffs(coeffs_file_path):
    with open(coeffs_file_path, "r") as f:
        coeffs_dict = json.load(f)

    degree = coeffs_dict["degree"]

    # Set x and y coeffs (assuming correct order!)
    # coeffs_x = np.array(coeffs_dict["x"]["coeffs"])
    # coeffs_y = np.array(coeffs_dict["y"]["coeffs"])

    # Perform selective loading where coefficients not present in the file
    # are assumed to be zero (required for BT data).

    poly = PolynomialFeatures(degree, include_bias=True)
    poly.fit(np.zeros((1, 2)))  # Dummy fit so I can obtain feature names...
    coeff_names = list(poly.get_feature_names_out())  # Get coefficient names
    n_terms = len(coeff_names)
    # Start off with all zeros
    coeffs = {
        "x": np.zeros(n_terms),
        "y": np.zeros(n_terms),
    }

    for direction in ["x", "y"]:
        for coeff_name, coeff_value in zip(coeffs_dict[direction]["names"], coeffs_dict[direction]["coeffs"]):
            # print(coeff_name, coeff_value)
            idx = coeff_names.index(coeff_name)
            # print(f"Inserting at {idx} ({direction})")
            coeffs[direction][idx] = coeff_value

    coeffs_x = coeffs["x"]
    coeffs_y = coeffs["y"]

    return coeffs_x, coeffs_y, degree


def compute_pos_poly(delsigx, delsigy, coeffx, coeffy, degree):
    # A little akward but make sure to use the same shape as fitting code to avoid confusion
    v_meas = np.stack(([delsigx], [delsigy])).T

    v_poly_meas = PolynomialFeatures(degree, include_bias=True).fit_transform(v_meas)

    posx = np.inner(coeffx, v_poly_meas)[0]
    posy = np.inner(coeffy, v_poly_meas)[0]

    return posx, posy


def getDelsigInjPoint(sums):
    # Cross-over electrode pairs (injection BPM)
    delsigx = (sums[0] - sums[2]) / (sums[0] + sums[2])
    delsigy = (sums[1] - sums[3]) / (sums[1] + sums[3])
    return delsigx, delsigy


def getDelsigInjBT(sums):
    delsigx = ((sums[0] + sums[3]) - (sums[1] + sums[2])) / (sums[0] + sums[1] + sums[2] + sums[3])
    delsigy = ((sums[0] + sums[1]) - (sums[2] + sums[3])) / (sums[0] + sums[1] + sums[2] + sums[3])
    return delsigx, delsigy


class SoftwarePosCalcProcessor(pr.DataReceiver):
    bobyqaErrors = {
        -1: "NPT is not in the required interval",
        -2: "insufficient space between the bounds",
        -3: "too much cancellation in a denominator",
        -4: "maximum number of function evaluations exceeded",
        -5: "a trust region step has failed to reduce Q",
    }

    # Init method must call the parent class init
    def __init__(
        self,
        signalMapIndexFile,
        polyVarsType,  # bt or injp
        *args,
        nWindows=2,
        hardDisablePoly=False,
        hardDisableFit=False,
        hardDisableMaskedFit=False,
        hardDisableChargeReject=True,
        flipX=False,
        flipY=False,
        sampleRate=5.0e9,
        bufferDepth=2**6,
        **kwargs,
    ):
        pr.Device.__init__(self, *args, **kwargs)
        ris.Slave.__init__(self)
        pr.DataReceiver.__init__(self, enableOnStart=True, hideData=True, *args, **kwargs)

        # Not saving config/state to YAML
        guiGroups = ["NoStream", "NoState", "NoConfig"]

        # Remove data variable from stream and server
        self.Data.addToGroup("NoServe")
        self.Data.addToGroup("NoStream")
        self.Data.addToGroup("NoStatus")

        if polyVarsType == "bt":
            self.getDelsig = getDelsigInjBT
        elif polyVarsType == "injp":
            self.getDelsig = getDelsigInjPoint
        else:
            raise KeyError(f"Invalid polynomial variables type: {polyVarsType}. Choose 'bt' or 'injp'.")

        # Configurable variables
        self._bufferDepth = bufferDepth
        self._timeBin = 1.0e9 / sampleRate  # Units of ns

        # Option to not even instantiate variables etc. for a given
        # position calculation method
        self._hardDisablePoly = hardDisablePoly
        self._hardDisableFit = hardDisableFit
        self._hardDisableMaskedFit = hardDisableMaskedFit
        # Option to disable data rejection based on computed charge
        self._hardDisableChargeReject = hardDisableChargeReject

        # Option to flip either axis as that was requested for backwards
        # compatibility (existing measurements had X flipped convention)
        self._flipX = flipX
        self._flipY = flipY

        # Do not attempt to import shared library if fit hard disabled
        self._posFitModule = None
        if not self._hardDisableFit:
            if importlib.util.find_spec("kek_lrsp_bpm.PosFit") is None:
                print("Could not find FitPos shared object. Make sure to compile the CPP position fit code.")
                # Do not exit here but rather proceed to try to load the
                # non-existing module which will throw an appropriate
                # exception.
            self._posFitModule = importlib.import_module("kek_lrsp_bpm.PosFit")

        # Number of windows for which to integrate the waveform and compute
        # a position.
        self._nWindows = nWindows

        # Make time direction positive here even though the trigger is at the
        # end of the waveform This is done as otherwise specification of the
        # integration windows in absolute terms is very inconvenient.
        timeSteps = np.linspace(0, self._timeBin * (self._bufferDepth - 1), num=self._bufferDepth)

        # Reference to used signal map and signal map index file
        self._signalMapIndex = None
        # Reference to cpp fitter instance
        self._cppFitter = None

        window_init_len = 100
        window_init_dist = 200

        self.add(
            pr.LocalVariable(
                name="NumWindows",
                description="Number of windows for integration",
                typeStr="Int32",
                value=self._nWindows,
                mode="RO",  # Fixed at initialization
                hidden=False,
            )
        )

        for i in range(self._nWindows):
            self.add(
                pr.LocalVariable(
                    name=f"WindowOpenRaw[{i}]",
                    description="Integration window left boundary sample",
                    typeStr="Int32",
                    value=window_init_dist * i,
                    hidden=False,
                )
            )

            self.add(
                pr.LocalVariable(
                    name=f"WindowCloseRaw[{i}]",
                    description="Integration window right boundary sample",
                    typeStr="Int32",
                    value=window_init_dist * i + window_init_len,
                    hidden=False,
                )
            )

            self.add(
                pr.LinkVariable(
                    name=f"WindowOpen[{i}]",
                    description="Integration window left boundary in ns",
                    typeStr="Float64",
                    units="ns",
                    dependencies=[self.WindowOpenRaw[i]],
                    # Must use default arguments to ensure index properly resolved in each lambda!
                    linkedGet=lambda idx=i: (float(self.WindowOpenRaw[idx].value() * self._timeBin)),
                    linkedSet=lambda value, write, idx=i: self.WindowOpenRaw[idx].set(int(value / self._timeBin)),
                    hidden=False,
                )
            )

            self.add(
                pr.LinkVariable(
                    name=f"WindowClose[{i}]",
                    description="Integration window left boundary in ns",
                    typeStr="Float64",
                    units="ns",
                    dependencies=[self.WindowCloseRaw[i]],
                    # Must use default arguments to ensure index properly resolved in each lambda!
                    linkedGet=lambda idx=i: (float(self.WindowCloseRaw[idx].value() * self._timeBin)),
                    linkedSet=lambda value, write, idx=i: self.WindowCloseRaw[idx].set(int(value / self._timeBin)),
                    hidden=False,
                )
            )

        # self.add(pr.LocalVariable(
        #     name        = f'SumPower',
        #     description = 'Power to which the absolute value of the signal is raised before summing',
        #     typeStr     = 'Float64',
        #     value       = 1,  # For now, leave this 1 (just add the option to try out 2)
        #     hidden      = False,
        # ))

        self.add(
            pr.LocalVariable(
                name="ChannelCorrections",
                description="Correction factors to apply to each channel reading (waveform sum)",
                typeStr="Float64[np]",
                value=np.array([1, 1, 1, 1]),
                hidden=False,
            )
        )

        self.add(
            pr.LocalVariable(
                name=f"polyEn",
                description="Enable polynomial position calculation",
                typeStr="bool",
                value=not self._hardDisablePoly,
                hidden=False,
                mode="RO" if self._hardDisablePoly else "RW",
                localSet=self.updatePosCalcNodesVisibility,
            )
        )

        if not self._hardDisablePoly:
            # Options for position computation may be (soft) disabled during runtime
            self.add(
                pr.LocalVariable(
                    name="PolyCoeffsFilePath",
                    description="Path to json file containing polynomial coefficients (and other metadata like degree)",
                    typeStr="str",
                    value="./config/SignalMaps/bemmapher_fit_coeffs.json",
                    localSet=self._loadPolyCoeffs,
                    groups=["fitPosCalc"],
                    hidden=False,
                )
            )

            self.add(
                pr.LocalVariable(
                    name="PolyDegree",
                    description="Position calculation polynomial degree",
                    mode="RO",
                    typeStr="Int32",
                    value=0,
                    groups=["polyPosCalc"],
                    hidden=False,
                )
            )

            self.add(
                pr.LocalVariable(
                    name="PolyCoeffX",
                    description="X position calculation polynomial coefficients",
                    mode="RO",
                    typeStr="Unknown",
                    value=np.array([0]),
                    groups=["polyPosCalc"],
                    hidden=False,
                )
            )

            self.add(
                pr.LocalVariable(
                    name="PolyCoeffY",
                    description="Y position calculation polynomial coefficients",
                    mode="RO",
                    typeStr="Unknown",
                    value=np.array([0]),
                    groups=["polyPosCalc"],
                    hidden=False,
                )
            )

            # self.add(
            #     pr.LocalVariable(
            #         name="PolyCoeffC",
            #         description="Charge calculation coefficients",
            #         typeStr="Float64[np]",
            #         value=np.array([0]),
            #         groups=["polyPosCalc"],
            #         hidden=False,
            #     )
            # )

        self.add(
            pr.LocalVariable(
                name=f"fitEn",
                description="Enable fit position calculation",
                typeStr="bool",
                value=not self._hardDisableFit,
                hidden=False,
                mode="RO" if self._hardDisableFit else "RW",
                localSet=self.updatePosCalcNodesVisibility,
            )
        )

        self.add(
            pr.LocalVariable(
                name=f"maskedFitEn",
                description="Enable masked fit position calculation",
                typeStr="bool",
                value=not self._hardDisableMaskedFit,
                hidden=False,
                mode="RO" if self._hardDisableMaskedFit or self._hardDisableFit else "RW",
                localSet=self.updatePosCalcNodesVisibility,
            )
        )

        if not self._hardDisableFit:
            # Options for position computation may be (soft) disabled during runtime

            self.add(
                pr.LocalVariable(
                    name="SignalMapIndexFile",
                    description="Signals map index file",
                    typeStr="str",
                    value=signalMapIndexFile,  # Default value must be passed to constructor
                    localSet=self._setSignalMapsIndex,
                    groups=["fitPosCalc"],
                    hidden=False,
                )
            )

            self.add(
                pr.LocalVariable(
                    name="SignalMapName",
                    description="Signals map file name (must be included in index file)",
                    typeStr="str",
                    value="bemmapher2025",
                    localSet=self._setSignalMapName,
                    groups=["fitPosCalc"],
                    hidden=False,
                )
            )

            # CPP fitter loads the map directly (for performance) but also
            # mirror its contents to a variable to make it accessible for use
            # in the GUI. This should be the loaded signal map so set this in
            # the same function as used for instantiating/updating CPP fitter.
            self.add(
                pr.LocalVariable(
                    name="SignalMapData",
                    description="Signals map data",
                    mode="RO",
                    typeStr="Unknown",
                    type=np.array,
                    value=np.array([0]),
                    groups=["fitPosCalc"],
                    hidden=False,
                )
            )

            self.add(
                pr.LocalVariable(
                    name="CppFitterXinit",
                    description="Initial x value for CPP signal map fitter",
                    typeStr="Float64",
                    value=0.0,
                    localSet=self._reinitFitterIfChanged,
                    groups=["fitPosCalc"],
                    hidden=False,
                )
            )

            self.add(
                pr.LocalVariable(
                    name="CppFitterYinit",
                    description="Initial y value for CPP signal map fitter",
                    typeStr="Float64",
                    value=0.0,
                    localSet=self._reinitFitterIfChanged,
                    groups=["fitPosCalc"],
                    hidden=False,
                )
            )

            self.add(
                pr.LocalVariable(
                    name="RhoBeg",
                    description="Initial value of rho (trust region) for bobyaqa minimizer. Tune for fit stability.",
                    typeStr="Float64",
                    value=0.5,
                    localSet=self._reinitFitterIfChanged,
                    groups=["fitPosCalc"],
                    hidden=False,
                )
            )

            self.add(
                pr.LocalVariable(
                    name="RhoEnd",
                    description="Final value of rho (trust region) for bobyaqa minimizer. Dictates fit result precicsion.",
                    typeStr="Float64",
                    value=1e-12,
                    localSet=self._reinitFitterIfChanged,
                    groups=["fitPosCalc"],
                    hidden=False,
                )
            )

            self.add(
                pr.LocalVariable(
                    name="MaxFun",
                    description="Maximum number of function calls during minimization",
                    typeStr="Int",
                    value=1000,
                    localSet=self._reinitFitterIfChanged,
                    groups=["fitPosCalc"],
                    hidden=False,
                )
            )

            self.add(
                pr.LocalVariable(
                    name="FitLimX",
                    description="Limit on x coordinate used during minimization. Symetric around origin. Smaller region stabilizes fit.",
                    typeStr="Float64",
                    value=6.4,
                    localSet=self._reinitFitterIfChanged,
                    groups=["fitPosCalc"],
                    hidden=False,
                )
            )

            self.add(
                pr.LocalVariable(
                    name="FitLimY",
                    description="Limit on y coordinate used during minimization. Symetric around origin. Smaller region stabilizes fit.",
                    typeStr="Float64",
                    value=3.7,
                    localSet=self._reinitFitterIfChanged,
                    groups=["fitPosCalc"],
                    hidden=False,
                )
            )

        # Variables to hold position computation results
        for i in range(self._nWindows):
            self.add(
                pr.LocalVariable(
                    name=f"Charge[{i}]",
                    description="bunch charge variable",
                    typeStr="Float64",
                    mode="RO",
                    value=0.0,
                    hidden=False,
                )
            )

            if not self._hardDisablePoly:
                self.add(
                    pr.LocalVariable(
                        name=f"XposPoly[{i}]",
                        description="position variable",
                        typeStr="Float64",
                        mode="RO",
                        value=0.0,
                        groups=["polyPosCalc"],
                        hidden=False,
                    )
                )

                self.add(
                    pr.LocalVariable(
                        name=f"YposPoly[{i}]",
                        description="position variable",
                        typeStr="Float64",
                        mode="RO",
                        value=0.0,
                        groups=["polyPosCalc"],
                        hidden=False,
                    )
                )

            if not self._hardDisableFit:
                self.add(
                    pr.LocalVariable(
                        name=f"XposFit[{i}]",
                        description="position variable",
                        typeStr="Float64",
                        mode="RO",
                        value=0.0,
                        groups=["fitPosCalc"],
                        hidden=False,
                    )
                )

                self.add(
                    pr.LocalVariable(
                        name=f"YposFit[{i}]",
                        description="position variable",
                        typeStr="Float64",
                        mode="RO",
                        value=0.0,
                        groups=["fitPosCalc"],
                        hidden=False,
                    )
                )

                if not self._hardDisableMaskedFit:
                    for j in range(4):
                        self.add(
                            pr.LocalVariable(
                                name=f"XposFitMasked{0xf^(0b1<<j):04b}[{i}]",
                                description="position variable with masked channels",
                                typeStr="Float64",
                                mode="RO",
                                value=0.0,
                                hidden=False,
                            )
                        )

                        self.add(
                            pr.LocalVariable(
                                name=f"YposFitMasked{0xf^(0b1<<j):04b}[{i}]",
                                description="position variable with masked channels",
                                typeStr="Float64",
                                mode="RO",
                                value=0.0,
                                hidden=False,
                            )
                        )

                    self.add(
                        pr.LocalVariable(
                            name=f"XposFitMaskedStd[{i}]",
                            description="standard deviation of position variables with masked channels",
                            typeStr="Float64",
                            mode="RO",
                            value=0.0,
                            groups=["fitPosCalc"],
                            hidden=False,
                        )
                    )

                    self.add(
                        pr.LocalVariable(
                            name=f"YposFitMaskedStd[{i}]",
                            description="standard deviation of position variables with masked channels",
                            typeStr="Float64",
                            mode="RO",
                            value=0.0,
                            groups=["fitPosCalc"],
                            hidden=False,
                        )
                    )

                    self.add(
                        pr.LocalVariable(
                            name=f"XposFitMaskedMean[{i}]",
                            description="mean of position variables with masked channels",
                            typeStr="Float64",
                            mode="RO",
                            value=0.0,
                            groups=["fitPosCalc"],
                            hidden=False,
                        )
                    )

                    self.add(
                        pr.LocalVariable(
                            name=f"YposFitMaskedMean[{i}]",
                            description="mean of position variables with masked channels",
                            typeStr="Float64",
                            mode="RO",
                            value=0.0,
                            groups=["fitPosCalc"],
                            hidden=False,
                        )
                    )

            if not self._hardDisableChargeReject:
                self.add(
                    pr.LocalVariable(
                        name=f"ChargeThreshold[{i}]",
                        description="Threshold below which measurements are considered empty shots and discarded",
                        typeStr="Float64",
                        mode="RO" if self._hardDisableChargeReject else "RW",
                        value=0.0,
                        hidden=False,
                    )
                )

                self.add(
                    pr.LocalVariable(
                        name=f"EmptyShotsSinceLast[{i}]",
                        description="Number of empty shots since last non-empty shot",
                        typeStr="Int",
                        mode="RO",
                        value=0,
                        hidden=False,
                    )
                )

            # This is technically all that is required to re-do the position
            # calculation offline. Stick them into an array so they can be
            # published in an EPICS v3 waveform PV, which is done to ensure
            # temporal coherence. For non-waveforms, there will be small
            # differences between timestamps, which is a pain to re-synchronize
            # later.
            self.add(
                pr.LocalVariable(
                    name=f"Sums[{i}]",
                    description="Integrated waveforms (all four of them) (integrant is absolute signal)",
                    type=np.array,
                    mode="RO",
                    value=np.array([0, 0, 0, 0]),
                    hidden=False,
                )
            )

            self.add(
                pr.LocalVariable(
                    name=f"SumsSq[{i}]",
                    description="Integrated waveforms (all four of them) (integrant is squared signal)",
                    type=np.array,
                    mode="RO",
                    value=np.array([0, 0, 0, 0]),
                    hidden=False,
                )
            )

        for i in range(4):
            self.add(
                pr.LocalVariable(
                    name=f"WaveformData[{i}]",
                    description="Data Frame Container, only updated on non-empty shots",
                    typeStr="Int16[np]",
                    value=np.zeros(shape=self._bufferDepth, dtype=np.int16, order="C"),
                    hidden=True,
                    groups=guiGroups,
                )
            )

        self.add(
            pr.LocalVariable(
                name="Metadata",
                description="Metadata buffer (shared data) obtained from the event system",
                typeStr="Float64[np]",
                value=np.zeros(shape=2048, dtype=np.uint16, order="C"),
                hidden=True,
                groups=guiGroups,  # Maybe also want metadata in the GUI?
            )
        )

        self.add(
            pr.LinkVariable(
                name="ShotID",
                description="Shot ID extracted from metadata buffer",
                mode="RO",
                dependencies=[self.Metadata],
                linkedGet=lambda: self.Metadata.value()[2],
            )
        )

        # All results collected into vector to ensure temporal coherence
        self.add(
            pr.LocalVariable(
                name="ResultsVector",
                description="Results from a given shot including metadata collected into a list",
                mode="RO",
                value=np.zeros(nWindows * 2 * (int(not self._hardDisableFit) + int(not self._hardDisablePoly)) + 1)
            )
        )

        self.add(
            pr.LocalVariable(
                name="Time",
                description="Time steps (ns)",
                typeStr="Float64[np]",
                value=timeSteps,
                hidden=True,
                groups=guiGroups,
            )
        )

        self.add(
            pr.LocalVariable(
                name="NewDataReady",
                value=False,
                groups=guiGroups,
            )
        )

    def updatePosCalcNodesVisibility(self):
        print("Oh no, updating groups works but this does not appear to be reflected in the Debug Tree?")
        polyEn = self.polyEn.get()
        fitEn = self.fitEn.get()

        for node_name, node_pointer in self._nodes.items():
            for en, group in zip([polyEn, fitEn], ["polyPosCalc", "fitPosCalc"]):
                if node_pointer.inGroup(group):
                    if en and node_pointer.inGroup("Hidden"):
                        node_pointer.removeFromGroup("Hidden")
                    elif not en and not node_pointer.inGroup("Hidden"):
                        node_pointer.addToGroup("Hidden")

    # Compute position using polynomials
    # TODO: Currently coefficients are shared. If different coefficients should
    # be used for different windows this would have to be changed, i.e. add
    # coefficient variables for each window.
    def _computePosPoly(self, sums: np.array):
        # Get coefficient matrices
        coeffx = self.PolyCoeffX.get()
        coeffy = self.PolyCoeffY.get()
        # Get polynomial degree
        degree = self.PolyDegree.get()

        # TODO: Add attribute to select which one we use here
        # For BT: this?
        delsigx = ((sums[0] + sums[3]) - (sums[1] + sums[2])) / (sums[0] + sums[1] + sums[2] + sums[3])
        delsigy = ((sums[0] + sums[1]) - (sums[2] + sums[3])) / (sums[0] + sums[1] + sums[2] + sums[3])

        delsigx, delsigy = self.getDelsig(sums)

        posx, posy = compute_pos_poly(delsigx, delsigy, coeffx, coeffy, degree)

        # For some reason those MUST be python floats. Otherwise pydm scatter
        # plot on update does not work. Maybe a rogue problem where it does not
        # raise the updated flag? Maybe a problem on pydm side.
        return float(posx), float(posy)

    def _computePosFit(self, sums: np.array, enableMask: np.array):
        posx, posy = self._fitPosCpp(*sums, *enableMask)

        # TODO: Check if minimizer failed (if it ever fails...)!
        # if minimize_result.success:
        #     posx, posy = minimize_result.x
        # else:
        #     print(minimize_result)
        #     posx, posy = float("nan"), float("nan")

        return posx, posy

    def _loadSignalMapsIndex(self):
        indexFilePath = self.SignalMapIndexFile.get()
        with open(indexFilePath, "r") as f:
            self._signalMapIndex = json.load(f)

    def _setSignalMapsIndex(self, value, changed):
        if changed:
            self._loadSignalMapsIndex()

    def _setSignalMapName(self, value, changed):
        if changed:
            # Re-initialize CPP fitter
            self._initCppFitter()
            # Re-load the polynomial coefficients
            self._loadPolyCoeffs()

    def _getCoeffsFilePathFromMapName(self):
        # Read metadata from index
        selectedMapIndex = self._signalMapIndex[self.SignalMapName.get()]
        # Map file path in index file is relative to location of the index file
        signalMapPath = os.path.join(os.path.dirname(self.SignalMapIndexFile.get()), selectedMapIndex["filepath"])
        coeffsFilePath = os.path.join(
            os.path.dirname(signalMapPath), os.path.basename(signalMapPath).split(".")[0] + "_fit_coeffs.json"
        )
        return coeffsFilePath

    def _loadPolyCoeffs(self):
        # No longer use this as this does not really make sense when the fit is
        # disabled (as for BT). Introduced variable PolyCoeffsFilePath to provide
        # the required path directly.
        # coeffsFilePath = self._getCoeffsFilePathFromMapName()

        coeffsFilePath = self.PolyCoeffsFilePath.get()
        self._log.info(f"Loading polynomial coefficients from {coeffsFilePath}")
        coeffs_x, coeffs_y, degree = load_poly_coeffs(coeffsFilePath)

        # Set degree
        self.PolyDegree.set(degree)
        self.PolyCoeffX.set(coeffs_x)
        self.PolyCoeffY.set(coeffs_y)
        # Update typestring and ndType (is this really the indended way?)
        self.PolyCoeffX._ndType = coeffs_x.dtype
        self.PolyCoeffY._ndType = coeffs_y.dtype
        self.PolyCoeffX._typeStr = f"{coeffs_x.dtype}{coeffs_x.shape}"
        self.PolyCoeffY._typeStr = f"{coeffs_y.dtype}{coeffs_y.shape}"

    def _reinitFitterIfChanged(self, value, changed):
        if changed:
            # Re-initialize CPP fitter
            self._initCppFitter()

    def _updateSignalMapVar(self, signalMapPath):
        data_array = np.loadtxt(signalMapPath, delimiter=",", dtype=np.float64)
        print(data_array)
        self.SignalMapData.set(data_array)

    def _initCppFitter(self):
        # Read metadata from index
        selectedMapIndex = self._signalMapIndex[self.SignalMapName.get()]
        # Map file path in index file is relative to location of the index file
        signalMapPath = os.path.join(os.path.dirname(self.SignalMapIndexFile.get()), selectedMapIndex["filepath"])
        xsize = selectedMapIndex["xsize"]
        ysize = selectedMapIndex["ysize"]
        xmin = -1 * xsize
        ymin = -1 * ysize
        xstep = selectedMapIndex["xstep"]
        ystep = selectedMapIndex["ystep"]
        xinit = self.CppFitterXinit.get()
        yinit = self.CppFitterYinit.get()
        # Number of points in map infered from map size and step size
        nx = int(round(xsize * 2 / xstep)) + 1
        ny = int(round(ysize * 2 / ystep)) + 1
        rhobeg = self.RhoBeg.get()
        rhoend = self.RhoEnd.get()
        maxfun = self.MaxFun.get()
        float_arguments = [xmin, ymin, xstep, ystep, xinit, yinit, rhobeg, rhoend]
        int_arguments = [nx, ny, maxfun]
        # Do not even attempt call to cpp code if the types are wrong as this may lead to a crash
        # TODO: It would be better if the local variables for at last the xinit/yinit values enforce the type already, but they don't?
        for arg in float_arguments:
            try:
                float(arg)
            except Exception as e:
                raise TypeError(f"Can't cast {type(arg)} to float, aborting fitter init.")
        for arg in int_arguments:
            try:
                int(arg)
            except Exception as e:
                raise TypeError(f"Can't cast {type(arg)} to int, aborting fitter init.")

        self._cppFitter = self._posFitModule.Fitter()
        # TODO: Make sure we don't call fit() before fitter is instantiated!
        self._cppFitter.init(signalMapPath, *float_arguments, *int_arguments)
        xlim = self.FitLimX.get()
        ylim = self.FitLimY.get()
        self._cppFitter.setLim(-xlim, xlim, -ylim, ylim)

        # Update the value of variable containing signal map values (for use in GUI)
        self._updateSignalMapVar(signalMapPath)

    def _fitPosCpp(self, v1, v2, v3, v4, en1, en2, en3, en4):
        # Must make sure to convert to python float (numpy float won't work)
        exitCode = self._cppFitter.fit(
            float(v1), float(v2), float(v3), float(v4), bool(en1), bool(en2), bool(en3), bool(en4)
        )
        if exitCode < 0:
            self._log.warning(
                f"Position fit returned negative exit code: {exitCode} (bobyqa error: {SoftwarePosCalcProcessor.bobyqaErrors[exitCode]}), positions will be NaN"
            )
            return float("nan"), float("nan")
        return self._cppFitter.fitX, self._cppFitter.fitY

    def _computeCharge(self, sums):
        # Calibrated charge computation
        # coeffc = self.PolyCoeffC.get()
        # sumssum = sums.sum()
        # termsc = np.array([sumssum**n for n in range(len(coeffc))])
        # charge = np.dot(coeffc, termsc)

        # Uncalibrated charge computation (just the sum of all signals)
        charge = sums.sum()

        return float(charge)

    def startupInit(self):
        # Cant have these calls in __init__ as there the local variables are not ready yet?
        if not self._hardDisableFit:
            print(self.SignalMapIndexFile.get())
            # Load signal map index
            self._loadSignalMapsIndex()
            # Initialize cpp fitter
            self._initCppFitter()
        if not self._hardDisablePoly:
            # Load the polynomial coefficients
            self._loadPolyCoeffs()

    # Method which updates the waveform PV from external function
    def UpdateWaveform(self):
        # Reset the flag
        self.NewDataReady.set(False)

    def applyFlipConventions(self, xpos, ypos):
        xres = -xpos if self._flipX else xpos
        yres = -ypos if self._flipY else ypos
        return xres, yres

    # Method which is called when a frame is received
    def process(self, frame):
        with self.root.updateGroup():
            # Convert the frame data into a numpy 16-bit integer array
            pl = frame.getNumpy(0, frame.getPayload())
            # pl = pl.view(np.uint8)  # Should already be uint8...
            btr_supfr_hdr_bytes = 2  # 2 byte super frame header
            btr_subfrm_tail_bytes = 7  # 7 byte sub frame tail
            # Superframe header from batcher
            batcher_header = pl[0:btr_supfr_hdr_bytes]
            # nr. of samples in buffer * 4 channels * 2 byte per sample = offset in bytes
            dat_bytes = 2 * self._bufferDepth * 4
            dat = pl[btr_supfr_hdr_bytes : btr_supfr_hdr_bytes + dat_bytes].view(np.int16)
            # Get the metadata payload bytes
            meta = pl[btr_supfr_hdr_bytes + dat_bytes + btr_subfrm_tail_bytes : -btr_subfrm_tail_bytes]
            # Subframe tails from batcher
            data_tail = pl[btr_supfr_hdr_bytes + dat_bytes : btr_supfr_hdr_bytes + dat_bytes + btr_subfrm_tail_bytes]
            meta_tail = pl[-btr_supfr_hdr_bytes : ]
            # For some reason the first byte is always 0x01. Probably part of
            # the protocol but not documented. The byte is there in the serial
            # data stream (as verified with ILA). Apparently not part of the 
            # payload so ignore this byte.
            meta = meta[1:]
            # Always pad to fixed size (2048 byte). Transmissions may terminate
            # early so the received buffer can be shorter.
            meta = np.pad(meta, (0, max(0, 2048 - meta.size)))
            # Metadata is uint16 but big endian as it originates from some
            # PowerPC VNC device. Decode accordingly.
            meta = meta.view(">u2")
            # np.set_printoptions(threshold=sys.maxsize)
            # print("Batcher header:", batcher_header)
            # print("Metadata:", meta)

            # Reshape the array into (4, N) format
            waveformData = dat.reshape(-1, 4).T  # Transpose to get (4, N) shape

            # Get channel correction coefficients
            channelCorrections = self.ChannelCorrections.get()

            atLeastOneWindowUpdated = False

            resultsVector = []

            # TODO: Consider running in parallel if too slow
            for i in range(self._nWindows):
                # Get window with for data to pass on to position calculation function
                windowOpenRaw = self.WindowOpenRaw[i].get()
                windowCloseRaw = self.WindowCloseRaw[i].get()

                # Compute signal sums
                # May want to use the square of the signals to get a metric proportional to signal power.
                # power = self.SumPower.get()
                sums_raw = np.abs(waveformData[:, windowOpenRaw:windowCloseRaw]).sum(axis=1)
                sums_sq_raw = np.power(np.abs(waveformData[:, windowOpenRaw:windowCloseRaw]), 2).sum(axis=1)
                sums = channelCorrections * sums_raw  # channelCorrections is 4 element vector

                # This is the uncalibrated 'charge', only useful for qualitative monitoring!
                charge = self._computeCharge(sums)

                # TODO: Do something smarter than charge threshold. Also decide
                # if we want to read out only if charge was sufficient on a per
                # BPM basis or per shot basis, meaning read all if one had
                # sufficient charge or read each only if charge sufficient.
                if self._hardDisableChargeReject or (charge >= self.ChargeThreshold[i].get()):
                    polyEn = self.polyEn.get()
                    fitEn = self.fitEn.get()
                    maskedFitEn = self.maskedFitEn.get()
                    if polyEn:
                        # Process waveforms to get positions
                        # Polynomial computation
                        xposPoly, yposPoly = self._computePosPoly(sums)
                        xposPoly, yposPoly = self.applyFlipConventions(xposPoly, yposPoly)
                    if fitEn:
                        # Fit computation. Fails with exception if the fit does not
                        # converge leading to this function to return before the results
                        # are written to the local variables (intended behaviour).
                        xposFit, yposFit = self._computePosFit(sums, np.array([True, True, True, True]))
                        xposFit, yposFit = self.applyFlipConventions(xposFit, yposFit)

                        if maskedFitEn:
                            # TODO: Make less verbose
                            xposFitMasked0111, yposFitMasked0111 = self._computePosFit(sums, np.array([False, True, True, True]))
                            xposFitMasked1011, yposFitMasked1011 = self._computePosFit(sums, np.array([True, False, True, True]))
                            xposFitMasked1101, yposFitMasked1101 = self._computePosFit(sums, np.array([True, True, False, True]))
                            xposFitMasked1110, yposFitMasked1110 = self._computePosFit(sums, np.array([True, True, True, False]))
                            xposFitMasked0111, yposFitMasked0111 = self.applyFlipConventions(xposFitMasked0111, yposFitMasked0111)
                            xposFitMasked1011, yposFitMasked1011 = self.applyFlipConventions(xposFitMasked1011, yposFitMasked1011)
                            xposFitMasked1101, yposFitMasked1101 = self.applyFlipConventions(xposFitMasked1101, yposFitMasked1101)
                            xposFitMasked1110, yposFitMasked1110 = self.applyFlipConventions(xposFitMasked1110, yposFitMasked1110)

                            xposFitMaskedMean = np.mean([xposFitMasked0111, xposFitMasked1011, xposFitMasked1101, xposFitMasked1110])
                            yposFitMaskedMean = np.mean([yposFitMasked0111, yposFitMasked1011, yposFitMasked1101, yposFitMasked1110])

                            xposFitMaskedStd = np.std([xposFitMasked0111, xposFitMasked1011, xposFitMasked1101, xposFitMasked1110])
                            yposFitMaskedStd = np.std([yposFitMasked0111, yposFitMasked1011, yposFitMasked1101, yposFitMasked1110])

                    # Write results to variables
                    self.Sums[i].set(sums_raw)  # Use uncorrected values!
                    self.SumsSq[i].set(sums_sq_raw)  # Use uncorrected values!

                    if polyEn:
                        self.XposPoly[i].set(xposPoly)
                        self.YposPoly[i].set(yposPoly)
                        resultsVector += [xposPoly, yposPoly]

                    if fitEn:
                        self.XposFit[i].set(xposFit)
                        self.YposFit[i].set(yposFit)
                        resultsVector += [xposFit, yposFit]

                        if maskedFitEn:
                            self.XposFitMasked0111[i].set(xposFitMasked0111)
                            self.XposFitMasked1011[i].set(xposFitMasked1011)
                            self.XposFitMasked1101[i].set(xposFitMasked1101)
                            self.XposFitMasked1110[i].set(xposFitMasked1110)

                            self.YposFitMasked0111[i].set(yposFitMasked0111)
                            self.YposFitMasked1011[i].set(yposFitMasked1011)
                            self.YposFitMasked1101[i].set(yposFitMasked1101)
                            self.YposFitMasked1110[i].set(yposFitMasked1110)

                            self.XposFitMaskedStd[i].set(xposFitMaskedStd)
                            self.YposFitMaskedStd[i].set(yposFitMaskedStd)

                            self.XposFitMaskedMean[i].set(xposFitMaskedMean)
                            self.YposFitMaskedMean[i].set(yposFitMaskedMean)

                    self.Charge[i].set(charge)

                    atLeastOneWindowUpdated = True
                    if not self._hardDisableChargeReject:
                        self.EmptyShotsSinceLast[i].set(0)  # Reset counter
                else:
                    # Reject the shot as charge below threshold
                    empty_shots_since_last_current = self.EmptyShotsSinceLast[i].get()
                    self.EmptyShotsSinceLast[i].set(empty_shots_since_last_current + 1)  # Increment counter

            # Update only when either bunch had sufficient charge
            # This is slow: TODO: Add a mechanism to update on only every
            # nth waveform or maybe once per second.
            # Or maybe just put it in a separate stream with dropping fifo?
            # In which case however the logic for only update on non empty
            # won't work. So better keep it here.
            if atLeastOneWindowUpdated or self._hardDisableChargeReject:
                for j in range(4):
                    self.WaveformData[j].set(waveformData[j, :], write=True)

                # TODO: Can we replace charge threshold with a check of
                # some information in the metadata? That would be optimal.
                # For now: Add option to hard disable rejection by charge
                # threshold and record data for empty shots as well but
                # add an option in the GUI to reject by charge.

                # Write metadata buffer from last shot
                self.Metadata.set(meta, write=True)

                # Write results to results vector
                resultsVector += [meta[2]]  # Shot ID
                self.ResultsVector.set(np.array(resultsVector))

            # Set the flag
            self.NewDataReady.set(True)
