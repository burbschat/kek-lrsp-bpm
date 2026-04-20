import pyrogue.utilities.fileio as fileio
from collections import OrderedDict
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
from scipy import stats
from threebpmtools import fit_single_direction, plane2d

# Add library paths (not sure how to import `setupLibPaths.py` here...)
import pyrogue as pr
import os

top_level = os.path.realpath(__file__).split("software")[0]
pr.addLibraryPath(top_level + "firmware/submodules/surf/python")
pr.addLibraryPath(top_level + "firmware/submodules/axi-soc-ultra-plus-core/python")
pr.addLibraryPath(top_level + "firmware/python")

# Import functions from python modules actually used in firmware
from kek_lrsp_bpm import load_poly_coeffs, compute_pos_poly


def to_np_ts(header, data):
    # Check if there is a 8-byte header in the frame
    if header.flags == 0:
        hdrOffset = 8
    else:
        hdrOffset = 0
        print("Warning: Found a frame with no header. This is not expected in this context.")

    # Data is everything but the header
    data_raw = data[hdrOffset:].view(np.int16)
    # Convert to 64 bit int here to save me headaches later (16 bit int DOES overflow easily if you for example square it)
    waveform = data_raw.reshape(-1, 4).T.astype(np.int64)  # Transpose to get (4, N) shape
    # The header is a unix timestamp in 64 bit float format
    ts = data[:hdrOffset].view(np.float64)[0]
    # Convert to datetime object (the pandas version of that with better precision/convenienter methods)
    ts_pd = pd.to_datetime(ts, unit="s").tz_localize("UTC").tz_convert("Japan")
    return ts_pd, waveform


# Obtain the puls type (electron or positron) from the pulse shape. The pules
# either goes first positive, then negative or the other way around. Pass data
# from only a single channel to this function, as all four channels should have
# the same pulse shape (but slightly different amplitude).
def get_pulse_type(data, thr_pos=2000, thr_neg=-2000):
    # Use two thresholds and compare order in which they are crossed.
    cross_pos_idx = (data > thr_pos).argmax()
    cross_neg_idx = (data < thr_neg).argmax()

    if cross_pos_idx > cross_neg_idx:
        return 1
    else:
        return -1


# Hardcoded polynomial for BT. Use to check agains the more general
# implementation used in the rogue application.
def compute_pos_poly_bt_static(sums):
    V1, V2, V3, V4 = sums
    U = ((V1 + V4) - (V2 + V3)) / (V1 + V2 + V3 + V4)
    V = ((V1 + V2) - (V3 + V4)) / (V1 + V2 + V3 + V4)

    x = (
        0
        + (-11.3680358 * U)
        + (11.3680358 * V)
        + (-3.30928757 * U**3)
        + (0.91938864 * U**2 * V)
        + (-0.91938864 * U * V**2)
        + (3.30928757 * V**3)
        + (-1.89451733 * U**5)
        + (2.0189691 * U**4 * V)
        + (0.31586347 * U**3 * V**2)
        + (-0.31586347 * U**2 * V**3)
        + (-2.0189691 * U * V**4)
        + (1.89451733 * V**5)
    )

    y = (
        0
        + (11.3680358 * U)
        + (11.3680358 * V)
        + (3.30928757 * U**3)
        + (0.91938864 * U**2 * V)
        + (0.91938864 * U * V**2)
        + (3.30928757 * V**3)
        + (1.89451733 * U**5)
        + (2.0189691 * U**4 * V)
        + (-0.31586347 * U**3 * V**2)
        + (-0.31586347 * U**2 * V**3)
        + (2.0189691 * U * V**4)
        + (1.89451733 * V**5)
    )

    return x, y


# Use coefficients loaded from files just as used for online computation
def compute_pos_poly_bt_online(sums, coeffx, coeffy, degree):
    delsigx = ((sums[0] + sums[3]) - (sums[1] + sums[2])) / (sums[0] + sums[1] + sums[2] + sums[3])
    delsigy = ((sums[0] + sums[1]) - (sums[2] + sums[3])) / (sums[0] + sums[1] + sums[2] + sums[3])
    posx, posy = compute_pos_poly(sums, coeffx, coeffy, degree)
    return posx, posy


# Define a position that runs on exactly one shot at a time so we don't have to
# worry about the whole dataset not fitting into memory.
def process_shot(header, data, windows, coeffx, coeffy, degree, particle_type, check_plot_ax=None):
    ts, wav = to_np_ts(header, data)

    pulse_type = get_pulse_type(wav[0, :])
    # For now, only do positive pulses (=electron)
    if particle_type == "e":
        if pulse_type < 0:
            return
    elif particle_type == "p":
        if pulse_type > 0:
            return
    else:
        print("Invalid particle type")
        exit()

    positions = []

    for lb, ub in windows:
        sums = np.abs(wav[:, lb:ub]).sum(axis=1)
        # Both methods appear to yield equivalent results. The hard coded
        # approach is much faster. Makes sense I guess.
        # posx, posy = compute_pos_poly_online(sums, coeffx, coeffy, degree)
        posx, posy = compute_pos_poly_bt_static(sums)
        positions += [(posx, posy)]

    if check_plot_ax is not None:
        for i in range(wav.shape[0]):
            check_plot_ax.plot(wav[i, :], label=f"channel {i}")

    positions = np.array(positions)
    return ts, positions


def scatter_hist(x, y, ax, ax_histx, ax_histy, label=None):
    # no labels
    ax_histx.tick_params(axis="x", labelbottom=False)
    ax_histy.tick_params(axis="y", labelleft=False)

    # the scatter plot:
    ax.scatter(x, y, marker="x", s=3, label=label, color="royalblue")

    # now determine nice limits by hand:
    binwidth = 0.25
    xymax = max(np.max(np.abs(x)), np.max(np.abs(y)))
    lim = (int(xymax / binwidth) + 1) * binwidth

    # bins = np.arange(-lim, lim + binwidth, binwidth)
    bins = 30
    ax_histx.hist(x, bins=bins, density=True, color="royalblue")
    ax_histy.hist(y, bins=bins, density=True, orientation="horizontal", color="royalblue")

        
    for ax_hist, data, is_vert in zip([ax_histx, ax_histy], [x, y], [False, True]):
        dist = stats.norm
        res = stats.fit(dist, data, bounds=[(-20, 20), (1e-9, 20)])  # Set appropriate limits!
        fit_curve_lsp = np.linspace(min(data), max(data), 100)
        fit_curve_vals = dist.pdf(fit_curve_lsp, res.params.loc, res.params.scale)

        if is_vert:
            lp_x, lp_y = fit_curve_vals, fit_curve_lsp
        else:
            lp_x, lp_y = fit_curve_lsp, fit_curve_vals

        ax_hist.plot(lp_x, lp_y, color="red")

        text = (
            rf"$\mu = {res.params.loc:.2f}$" "\n"
            rf"$\sigma = {res.params.scale:.2f}$"
        )

        ax_hist.text(
            0.93, 0.93, text,
            transform=ax_hist.transAxes,
            ha="right", va="top",
            fontsize=9,
        )


def plot_fit_gauss(pos_all, n_cols=3, bpm_names=None):
    n_bpm = pos_all.shape[1]
    n_rows = int(np.ceil(n_bpm / n_cols))

    fig, ax_all = plt.subplots(n_rows, n_cols, layout="constrained", figsize=(15, 15))
    ax_all = ax_all.flatten()

    for i in range(n_bpm):
        ax = ax_all[i]

        # The main Axes' aspect can be fixed.
        #ax.set_aspect("equal")
        # Create marginal Axes, which have 25% of the size of the main Axes.  Note that
        # the inset Axes are positioned *outside* (on the right and the top) of the
        # main Axes, by specifying axes coordinates greater than 1.  Axes coordinates
        # less than 0 would likewise specify positions on the left and the bottom of
        # the main Axes.
        ax_histx = ax.inset_axes([0, 1.05, 1, 0.25], sharex=ax)
        ax_histy = ax.inset_axes([1.05, 0, 0.25, 1], sharey=ax)
        # Draw the scatter plot and marginals.
        scatter_hist(pos_all[:, i, 0], pos_all[:, i, 1], ax, ax_histx, ax_histy, label=f"Window {i}")
        # ax.scatter(pos_all[:, i, 0], pos_all[:, i, 1], marker="x", s=3, label=f"Window {i}")
        if bpm_names is not None:
            ax_histx.set_title(bpm_names[i])

    return fig


def main():
    infile_path = "/mnt/data2/bt_rfsoc4x2_bpm_test_data/data_20251224_030907.dat"
    particle_type = "p"

    # Maybe this is nonsense, if the dict passed here can change the order
    # prior to being processed by the constructor...
    windows_electron = OrderedDict({
        "QMF2E_1M_1": (335, 450),
        "QMD1E_2M_1": (625, 750),
        "QMF2E_1M_2": (825, 910),
        "QMF2E_2M_1": (925, 1050),
        "QMD1E_2M_2": (1125, 1210),
        "QMD1E_3M_1": (1215, 1335),
        "QMF2E_2M_2": (1420, 1520),
        "QMF3E_M_1": (1530, 1650),
        "QMD1E_3M_2": (1700, 1820),
        "QMF3E_M_2": (2030, 2150),
    })

    windows_positron = OrderedDict({
        "QMD2P_2K_1": (220, 370),
        "QMF1P_3K_1": (435, 610),
        "QMD3P_K_1": (755, 920),
        "QMF4P_K_1": (980, 1135),
        "QMD5P_K_1": (1185, 1350),
        "QMF6P_K_1": (1395, 1580),
        # Could not find below ones in optics plots!
        "QMD7P_K_1": (1625, 1800),
        "QMF8P_K_1": (1855, 2035),
    })

    # Set BPMs to use for 3BPM analysis
    # Electron opt A
    # ref_bpm_name_1 = "QMF2E_2M_1"
    # ref_bpm_name_2 = "QMD1E_3M_1"
    # target_bpm_name = "QMF3E_M_1"
    # Electron opt B
    # ref_bpm_name_1 = "QMD1E_2M_1"
    # ref_bpm_name_2 = "QMF2E_2M_1"
    # target_bpm_name = "QMD1E_3M_1"

    # Positron opt A
    ref_bpm_name_1 = "QMF1P_3K_1"
    ref_bpm_name_2 = "QMD3P_K_1"
    target_bpm_name = "QMF4P_K_1"


    if particle_type == "e":
        windows = windows_electron
    elif particle_type == "p":
        windows = windows_positron

    coeffs_file_path = "../../config/SignalMaps/bt_fit_coeffs.json"
    print(f"Loading polynomial coefficients from {coeffs_file_path}")
    coeffx, coeffy, degree = load_poly_coeffs(coeffs_file_path)

    check_plot = True
    check_plot_num = 1

    process_num = 60000
    skip_num = 3000

    if check_plot:
        fig_wav, ax_wav = plt.subplots(1, 1, layout="constrained", figsize=(13, 4))
        ax_wav.grid()
        ax_wav.xaxis.set_major_locator(ticker.MultipleLocator(150))
        first = True
        for lb, ub in windows.values():
            ax_wav.axvspan(lb, ub, color="royalblue", alpha=0.5, label="sum region" if first else None)
            first = False

    with fileio.FileReader(files=infile_path) as fd:
        pos_all = []

        i = 0
        for header, data in fd.records():
            # Only plot if enabled and only for the first n shots
            if check_plot and i < (skip_num + check_plot_num) and i > skip_num:
                check_plot_ax = ax_wav
            else:
                check_plot_ax = None

            res = process_shot(
                header,
                data,
                list(windows.values()),
                coeffx,
                coeffy,
                degree,
                particle_type=particle_type,
                check_plot_ax=check_plot_ax,
            )

            if res is not None:
                i += 1
                if i < skip_num:
                    continue

                ts, pos_shot = res
                pos_all.append(pos_shot)

                if i == skip_num + 1:
                    ts_first = ts

                # Process only a specified number of shots
                if i >= (process_num + skip_num):
                    ts_last = ts
                    break

        pos_all = np.array(pos_all)

    if check_plot:
        ax_wav.legend()
        ax_wav.set_xlabel("sample nr.")
        ax_wav.set_ylabel("ADC count")
        ax_wav.set_xlim(0, 3300)
        fig_wav.savefig("waveforms_windows.pdf")

    # Fit to extrapolate positon at third from other two
    fit_direction = 0
    bpm_names = list(windows.keys())
    ref_bpm_idx_1 = bpm_names.index(ref_bpm_name_1)
    ref_bpm_idx_2 = bpm_names.index(ref_bpm_name_2)
    target_bpm_idx = bpm_names.index(target_bpm_name)
    pos_ref_1 = pos_all[:, ref_bpm_idx_1, fit_direction]
    pos_ref_2 = pos_all[:, ref_bpm_idx_2, fit_direction]
    pos_target = pos_all[:, target_bpm_idx, fit_direction]
    popt = fit_single_direction(
        pos_ref_1,
        pos_ref_2,
        pos_target,
        check_plot=True,
    )

    # Predict positions using the fit (always on the fitted "average" plane)
    pos_pred = plane2d([pos_ref_1, pos_ref_2], *popt)

    # Compute residual between predicted and measured position
    pos_resid = pos_target - pos_pred
    # Plot residuals distribution
    fig_resid, ax_resid = plt.subplots(1, 1, layout="constrained", figsize=(7.5, 5))
    # Fit gaussian to the distribution
    resid_dist = stats.norm
    pos_resid = pos_resid[np.abs(pos_resid) < 0.3]
    resid_fit_res = stats.fit(resid_dist, pos_resid, bounds=[(-20, 20), (1e-9, 20)])  # Set appropriate limits!
    resid_fit_curve_lsp = np.linspace(min(pos_resid), max(pos_resid), 100)
    resid_fit_curve_vals = resid_dist.pdf(resid_fit_curve_lsp, resid_fit_res.params.loc, resid_fit_res.params.scale)
    # Compute resolution under assumption of equal resolutions by assuming the
    # width (sigma) of the residual distribution to eqal the root of the sum of
    # three equal resolutions squared, however making sure to propagate the
    # effect of parameters used in the extrapolation function.
    resolution_est = resid_fit_res.params.scale / np.sqrt(1 + popt[0]**2 + popt[1]**2)
    # Unite results in a plot
    ax_resid.hist(pos_resid, bins=30, color="royalblue", density=True, label="meas. pos. - pred. pos.")
    ax_resid.plot(resid_fit_curve_lsp, resid_fit_curve_vals, color="red", label=f"Gaussian Fit: $\\sigma={resid_fit_res.params.scale:.2g}, \\mu={resid_fit_res.params.loc:.2g}$")
    ax_resid.legend()
    ax_resid.set_title(f"ref_bpm_1 = {ref_bpm_name_1}, ref_bpm_2 = {ref_bpm_name_2}, target_bpm = {target_bpm_name}\nresolution estimate = $\\sigma/\\sqrt{{1 + A^2 + B^2}} = {resolution_est:.2g}$ mm")
    ax_resid.set_xlabel(f"measured pos. - predicted pos. [mm]")
    ax_resid.set_ylabel(f"normalized counts")
    direction_names = ["x", "y"]
    time_format = "%Y-%m-%d %H:%M"
    fig_resid.suptitle(f"3-BMP Analysis (direction = {direction_names[fit_direction]}, n = {process_num})\ntime period: {ts_first.strftime(time_format)} to {ts_last.strftime(time_format)}")
    fig_resid.savefig(f"3bpm_results_{particle_type}.pdf")

    # Scatter plot positions for all windows
    fig_pos, ax_pos = plt.subplots(1, 1, layout="constrained", figsize=(15, 10))
    for i in range(pos_all.shape[1]):
        # ax_pos.scatter(pos_all[:, i, 0], pos_all[:, i, 1], marker="x", s=3, label=f"Window {i}")
        ax_pos.scatter(pos_all[:, i, 0], pos_all[:, i, 1], marker="x", s=3, label=f"Window {i}", c=np.arange(pos_all.shape[0]))

    ax_pos.legend()
    ax_pos.set_title(f"{process_num} shots (recorded {ts_first} to {ts_last})")

    fig_pos.savefig("pos_scatter.png")

    fig_fit_gauss = plot_fit_gauss(pos_all, bpm_names=bpm_names)
    fig_fit_gauss.suptitle(f"{process_num} shots (recorded {ts_first} to {ts_last})")
    fig_fit_gauss.savefig("fit_gauss.png")

    # Scatter predicted against measured position
    fig_predtar, ax_predtar = plt.subplots(1, 1, layout="constrained", figsize=(15, 10))
    for i in range(pos_all.shape[1]):
        ax_predtar.scatter(pos_target, pos_pred, marker="x", s=3, label=f"Window {i}", c=np.arange(pos_target.shape[0]))

    fig_predtar.savefig("pred_target_scatter.png")

if __name__ == "__main__":
    main()
