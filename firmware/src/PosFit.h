#ifndef POSFIT_H_
#define POSFIT_H_

#include <iostream>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string>
#include <time.h>

#include <gsl/gsl_interp2d.h>
#include <gsl/gsl_math.h>
#include <gsl/gsl_multimin.h>
#include <gsl/gsl_spline2d.h>
#include <string>

#include "bobyqa/bobyqa.h"

#include <boost/python.hpp>

// Print level for minimizer (increase for debug output)
#define BOBYA_IPRINT 0

class Fitter {
public:
  // vvvv Initialized in init() call vvvv
  std::string smap;
  double xmin, ymin, xstep, ystep;
  double xinit, yinit;
  unsigned int nx, ny;
  double rhobeg = 1e-1;
  double rhoend = 1e-12;
  long maxfun = 1000;
  // ^^^^ Initialized in init() call ^^^^

  double *gridx, *gridy;
  double *gridv1, *gridv2, *gridv3, *gridv4;

  gsl_spline2d *splv1, *splv2, *splv3, *splv4;

  gsl_interp_accel *xacc, *yacc;

  double v1meas, v2meas, v3meas, v4meas;

  bool ch1En, ch2En, ch3En, ch4En = true;

  double FcnPosFit(const double x, const double y);

  // Wrap in a static function we pass to the fitting code.
  // Pass reference to this instance using the void pointer.
  static double FcnPosFitWrapper(const long n, const double *x, void *data) {
    auto *thisInstance = static_cast<Fitter *>(data);
    // Make call to the underlying function accessing class attributes
    return thisInstance->FcnPosFit(x[0], x[1]);
  }

  void init(std::string smap, double xmin, double ymin, double xstep,
            double ystep, double xinit, double yinit, double rhobeg,
            double rhoend, unsigned int nx, unsigned int ny, long maxfun);

  void setLim(double xlim_l, double xlim_u, double ylim_l, double ylim_u);

  void cleanup();

  void GetVs(const double x, const double y, double *v1, double *v2, double *v3,
             double *v4);

  double GetV1(const double x, const double y);
  double GetV2(const double x, const double y);
  double GetV3(const double x, const double y);
  double GetV4(const double x, const double y);

  int fit(const double &v1measRaw, const double &v2measRaw,
          const double &v3measRaw, const double &v4measRaw,
          const bool &ch1Enable, const bool &ch2Enable, const bool &ch3Enable,
          const bool &ch4Enable);

  Fitter();
  ~Fitter();

  double GetFitY();
  double GetFitX();

  // Expose methods to python
  static void setup_python() {
    boost::python::class_<Fitter, boost::shared_ptr<Fitter>,
                          boost::noncopyable>(
        // Must pass argument types of constructor here
        "Fitter", boost::python::init<>())
        .def("init", &Fitter::init)
        .def("setLim", &Fitter::setLim)
        .def("fit", &Fitter::fit)
        .add_property("fitX", &Fitter::GetFitX) // Read only!
        .add_property("fitY", &Fitter::GetFitY)
        .def("getV1", &Fitter::GetV1)
        .def("getV2", &Fitter::GetV2)
        .def("getV3", &Fitter::GetV3)
        .def("getV4", &Fitter::GetV4);
  };

private:
  static const long npar = 2;
  static const long npt = 5;
  // Compute of required work memory
  static const int nw = (npt + 5) * (npt + npar) + 3 * npar * (npar + 5) / 2;

  // Used for bobyqa minimization
  double parl[npar]; // lower bounds on fit parameters
  double parh[npar]; // uppper bounds on fit parameters
  // Parameters are reset to initial guess at the start of each fit.
  double par[npar] = {0, 0};

  // Array required for optimizer to store data during optimization
  double work[nw];
};

// Setup this module in python
BOOST_PYTHON_MODULE(PosFit) {
  PyEval_InitThreads();
  try {
    Fitter::setup_python();
  } catch (...) {
    printf("Failed to load module. import rogue first\n");
  }
  printf("Loaded poscalc module\n");
};

#endif // !POSFIT_H_
