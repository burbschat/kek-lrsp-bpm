#include "PosFit.h"

void Fitter::GetVs(const double x, const double y, double *v1, double *v2,
                   double *v3, double *v4) {
  *v1 = gsl_interp2d_eval_extrap((gsl_interp2d *)splv1, gridx, gridy, gridv1, x,
                                 y, xacc, yacc);
  *v2 = gsl_interp2d_eval_extrap((gsl_interp2d *)splv2, gridx, gridy, gridv2, x,
                                 y, xacc, yacc);
  *v3 = gsl_interp2d_eval_extrap((gsl_interp2d *)splv3, gridx, gridy, gridv3, x,
                                 y, xacc, yacc);
  *v4 = gsl_interp2d_eval_extrap((gsl_interp2d *)splv4, gridx, gridy, gridv4, x,
                                 y, xacc, yacc);
}

double Fitter::GetV1(const double x, const double y) {
  double v1, v2, v3, v4;
  GetVs(x, y, &v1, &v2, &v3, &v4);
  return v1;
}

double Fitter::GetV2(const double x, const double y) {
  double v1, v2, v3, v4;
  GetVs(x, y, &v1, &v2, &v3, &v4);
  return v2;
}

double Fitter::GetV3(const double x, const double y) {
  double v1, v2, v3, v4;
  GetVs(x, y, &v1, &v2, &v3, &v4);
  return v3;
}

double Fitter::GetV4(const double x, const double y) {
  double v1, v2, v3, v4;
  GetVs(x, y, &v1, &v2, &v3, &v4);
  return v4;
}

double Fitter::FcnPosFit(const double x, const double y) {
  double v1, v2, v3, v4;
  GetVs(x, y, &v1, &v2, &v3, &v4);

  // Normalize to unity
  const double sumv = v1 + v2 + v3 + v4;
  v1 /= sumv;
  v2 /= sumv;
  v3 /= sumv;
  v4 /= sumv;

  // printf("Minimizer eval\t(%f, %f):\t%f * %f, %f * %f, %f * %f, %f * %f\n",
  // x, y, static_cast<float>(ch1En), v1, static_cast<float>(ch2En), v2,
  // static_cast<float>(ch3En), v3, static_cast<float>(ch4En), v4);

  return static_cast<double>(ch1En) * pow((v1 - v1meas), 2.) +
         static_cast<double>(ch2En) * pow((v2 - v2meas), 2.) +
         static_cast<double>(ch3En) * pow((v3 - v3meas), 2.) +
         static_cast<double>(ch4En) * pow((v4 - v4meas), 2.);
}

// This is a separate function as a boost wrapped function can only have up to
// 15 arguments??? How annoying. I guess it makes some sense to have this
// separate though...
void Fitter::setLim(double xlim_l, double xlim_u, double ylim_l,
                    double ylim_u) {
  // First parameter (x)
  parl[0] = xlim_l;
  parh[0] = xlim_u;
  // Seocond parameter (y)
  parl[1] = ylim_l;
  parh[1] = ylim_u;
}

void Fitter::init(std::string smap, double xmin, double ymin, double xstep,
                  double ystep, double xinit, double yinit, double rhobeg,
                  double rhoend, unsigned int nx, unsigned int ny,
                  long maxfun) {

  this->smap = smap;
  this->xmin = xmin;
  this->ymin = ymin;
  this->xstep = xstep;
  this->ystep = ystep;
  this->xinit = xinit;
  this->yinit = yinit;
  this->nx = nx;
  this->ny = ny;
  this->rhobeg = rhobeg;
  this->rhoend = rhoend;
  this->maxfun = maxfun;

  // Assign parameter bounds (defaults are as large as the map is)
  // First parameter (x)
  parl[0] = xmin;
  parh[0] = xmin + (nx - 1) * xstep;
  // Seocond parameter (y)
  parl[1] = ymin;
  parh[1] = ymin + (ny - 1) * ystep;
  // parl[1] = ylim_l;
  // parh[1] = ylim_u;

  // Allocate required arrays
  gridx = (double *)malloc(nx * sizeof(double));
  gridy = (double *)malloc(ny * sizeof(double));

  gridv1 = (double *)malloc(nx * ny * sizeof(double));
  gridv2 = (double *)malloc(nx * ny * sizeof(double));
  gridv3 = (double *)malloc(nx * ny * sizeof(double));
  gridv4 = (double *)malloc(nx * ny * sizeof(double));

  // Prepare rectangular grid locations (i.e. the axes)
  for (unsigned int ix = 0; ix < nx; ++ix)
    gridx[ix] = xmin + xstep * (double)ix;

  for (unsigned int iy = 0; iy < ny; ++iy)
    gridy[iy] = ymin + ystep * (double)iy;

  // Load signal maps from file
  FILE *fp = fopen(smap.c_str(), "r");
  if (fp == NULL)
    throw std::runtime_error("Signal map file not found");

  for (unsigned int iline = 0; iline < (nx * ny); ++iline) {
    double xtmp, ytmp, v1tmp, v2tmp, v3tmp, v4tmp;
    // fscanf(fp, "%lf %lf %lf %lf %lf %lf", &xtmp, &ytmp, &v1tmp, &v2tmp,
    // &v3tmp, &v4tmp);
    fscanf(fp, "%lf,%lf,%lf,%lf,%lf,%lf", &xtmp, &ytmp, &v1tmp, &v2tmp, &v3tmp,
           &v4tmp);

    // Recover index from the grid positions
    const int ix = (int)round((xtmp - xmin) / xstep);
    const int iy = (int)round((ytmp - ymin) / ystep);

    // Assign to grid arrays in order required by gsl functions
    gridv1[iy * nx + ix] = v1tmp;
    gridv2[iy * nx + ix] = v2tmp;
    gridv3[iy * nx + ix] = v3tmp;
    gridv4[iy * nx + ix] = v4tmp;
  }
  fclose(fp);

  // Prepare interpolation
  const gsl_interp2d_type *T2 = gsl_interp2d_bilinear;
  splv1 = gsl_spline2d_alloc(T2, nx, ny);
  splv2 = gsl_spline2d_alloc(T2, nx, ny);
  splv3 = gsl_spline2d_alloc(T2, nx, ny);
  splv4 = gsl_spline2d_alloc(T2, nx, ny);

  // Prepare accelerators for interpolation
  xacc = gsl_interp_accel_alloc();
  yacc = gsl_interp_accel_alloc();

  // Initialize interpolation
  gsl_spline2d_init(splv1, gridx, gridy, gridv1, nx, ny);
  gsl_spline2d_init(splv2, gridx, gridy, gridv2, nx, ny);
  gsl_spline2d_init(splv3, gridx, gridy, gridv3, nx, ny);
  gsl_spline2d_init(splv4, gridx, gridy, gridv4, nx, ny);

  std::cout << "CPP fitter signal map load completed: " << smap << std::endl;
}

void Fitter::cleanup() {
  // Cleanup allocated arrays
  free(gridx);
  free(gridy);

  free(gridv1);
  free(gridv2);
  free(gridv3);
  free(gridv4);
}

int Fitter::fit(const double &v1measRaw, const double &v2measRaw,
                const double &v3measRaw, const double &v4measRaw,
                const bool &ch1Enable, const bool &ch2Enable,
                const bool &ch3Enable, const bool &ch4Enable) {
  const double vRawSum = v1measRaw + v2measRaw + v3measRaw + v4measRaw;
  // Normalize raw values and assign to attributes
  v1meas = v1measRaw / vRawSum;
  v2meas = v2measRaw / vRawSum;
  v3meas = v3measRaw / vRawSum;
  v4meas = v4measRaw / vRawSum;

  ch1En = ch1Enable;
  ch2En = ch2Enable;
  ch3En = ch3Enable;
  ch4En = ch4Enable;

  // std::cout << ch1En << ch2En << ch3En << ch4En << std::endl;

  // Set initial guess. If this is not done here, the last result will be the
  // initial guess for the next optimization. This appears to be a reasonable
  // assumption, but it was found that in some edge cases the optimizer can get
  // stuck at the edge of the x/y plane. So it is safer to reset to a fixed
  // initial guess every time.
  par[0] = xinit;
  par[1] = yinit;

  int bobyqaExitCode =
      bobyqa(npar, npt, FcnPosFitWrapper, (void *)this, par, parl, parh, rhobeg,
             rhoend, BOBYA_IPRINT, maxfun, work);

  double fitx = par[0];
  double fity = par[1];

  return bobyqaExitCode;
}

double Fitter::GetFitX() { return par[0]; }

double Fitter::GetFitY() { return par[1]; }

Fitter::Fitter() {
  // Initialization references only class attributes
}

Fitter::~Fitter() { cleanup(); }
