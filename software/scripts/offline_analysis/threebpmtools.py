from scipy.optimize import curve_fit
import numpy as np
import matplotlib.pyplot as plt


def plane2d(x, a, b, c):
    x1, x2 = x  # 2d input
    return a * x1 + b * x2 + c


def fit_plane(x, y):
    # x must be 2d (two BPM readings used to extrapolate)
    popt, pcov = curve_fit(plane2d, x, y)
    return popt, pcov


# Fit 2d plane to predict the target pos from two reference positions.
def fit_single_direction(reference_pos_1, reference_pos_2, target_pos, check_plot=False):
    references = np.array([reference_pos_1, reference_pos_2])
    target = np.array(target_pos)

    popt, pcov = fit_plane(references, target)

    if check_plot:
        fig = plt.figure()
        ax = fig.add_subplot(111, projection="3d")
        color_values = np.arange(len(target_pos))
        ax.scatter(references[0], references[1], target, c=color_values)

        def get_grid():
            x1min, x1max = min(references[0]), max(references[0])
            x2min, x2max = min(references[1]), max(references[1])
            x, y = np.mgrid[x1min : x1max : (x1max - x1min) / 10, x2min : x2max : (x2max - x2min) / 10]
            return np.vstack((x.flatten(), y.flatten()))

        x_pred = get_grid()
        y_pred = plane2d(x_pred, *popt)
        ax.scatter(*x_pred, y_pred, color="Red")
        plt.show()

    a, b, c = popt

    return a, b, c
