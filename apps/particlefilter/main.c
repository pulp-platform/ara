// This modified implementation is based on the following work:
/**
 * @file ex_particle_OPENMP_seq.c
 * @author Michael Trotter & Matt Goodrum
 * @brief Particle filter implementation in C/OpenMP
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <riscv_vector.h>

#ifndef SPIKE
#include "printf.h"
#endif

#include "runtime.h"
// RISC-V VECTOR Version by Cristóbal Ramírez Lazo, "Barcelona 2019"
#include "lib/cos.h"
#include "lib/exp.h"
#include "lib/log.h"

// #include <omp.h>
#include <limits.h>
#include <math.h>
#define PI 3.1415926535897932
/**
@var M value for Linear Congruential Generator (LCG); use GCC's value
*/
long M = INT_MAX;
/**
@var A value for LCG
*/
int A = 1103515245;
/**
@var C value for LCG
*/
int C = 12345;

// Define sizes
#if defined(SIMTINY)
#define ISZX 128
#define ISZY 128
#define NFR 2
#define NPARTICLES 256
#elif defined(SIMSMALL)
#define ISZX 128
#define ISZY 128
#define NFR 8
#define NPARTICLES 1024
#elif defined(SIMMEDIUM)
#define ISZX 128
#define ISZY 128
#define NFR 16
#define NPARTICLES 4096
#elif defined(SIMLARGE)
#define ISZX 128
#define ISZY 128
#define NFR 24
#define NPARTICLES 8192
#else
#define ISZX 8
#define ISZY 8
#define NFR 2
#define NPARTICLES 64
#endif

int Seed = 353;
int32_t seed[NPARTICLES];
int64_t seed_64[NPARTICLES];
int I[ISZX * ISZY * NFR];

/**
 * Takes in a double and returns an integer that approximates to that double
 * @return if the mantissa < .5 => return value < input value; else return value
 * > input value
 */
double roundDouble(double value) {
  int newValue = (int)(value);
  if (value - newValue < .5)
    return newValue;
  else
    return newValue++;
}
/**
 * Set values of the 3D array to a newValue if that value is equal to the
 * testValue
 * @param testValue The value to be replaced
 * @param newValue The value to replace testValue with
 * @param array3D The image vector
 * @param dimX The x dimension of the frame
 * @param dimY The y dimension of the frame
 * @param dimZ The number of frames
 */
void setIf(int testValue, int newValue, int *array3D, int *dimX, int *dimY,
           int *dimZ) {
  int x, y, z;
  for (x = 0; x < *dimX; x++) {
    for (y = 0; y < *dimY; y++) {
      for (z = 0; z < *dimZ; z++) {
        if (array3D[x * *dimY * *dimZ + y * *dimZ + z] == testValue)
          array3D[x * *dimY * *dimZ + y * *dimZ + z] = newValue;
      }
    }
  }
}
/**
 * Generates a uniformly distributed random number using the provided seed and
 * GCC's settings for the Linear Congruential Generator (LCG)
 * @see http://en.wikipedia.org/wiki/Linear_congruential_generator
 * @note This function is thread-safe
 * @param seed The seed array
 * @param index The specific index of the seed to be advanced
 * @return a uniformly distributed number [0, 1)
 */
double randu(int *seed, int index) {
  int num = A * seed[index] + C;
  seed[index] = num % M;
  return fabs(seed[index] / ((double)M));
}

inline vfloat64m1_t randu_vector(long int *seed, int index, size_t gvl) {
  /*
  vint64m1_t    xseed = vle64_v_i64m1(&seed[index],gvl);
  vint64m1_t    xA = vmv_v_x_i64m1(A,gvl);
  vint64m1_t    xC = vmv_v_x_i64m1(C,gvl);
  vint64m1_t    xM = vmv_v_x_i64m1(M,gvl);

  xseed =  vmul_vv_i64m1(xseed,xA,gvl);
  xseed =  vadd_vv_i64m1(xseed,xC,gvl);

  vse64_v_i64m1(&seed[index],vrem_vv_i64m1(xseed,xM,gvl),gvl);
  asm volatile ("fence"::);
  vfloat64m1_t    xResult;
  xResult =
  _MM_DIV_f64(vfcvt_f_x_v_f64m1(xseed,gvl),vfcvt_f_x_v_f64m1(xM,gvl),gvl);
  xResult = vfsgnjx_vv_f64m1(xResult,xResult,gvl);
  return xResult;
  */

  /*
  Esta parte del codigo deberia ser en 32 bits, pero las instrucciones de
  conversion aún no están disponibles,
  moviendo todo a 64 bits el resultado cambia ya que no se desborda, y las
  variaciones son muchas.
  */
  double result[256];
  int num[256];
  // asm volatile ("fence"::);
  // double* result = (double*)malloc(gvl*sizeof(double));
  // int* num = (int*)malloc(gvl*sizeof(int));

  asm volatile("fence" ::);
  for (int x = index; x < (int)(index + gvl); x++) {
    num[x - index] = A * seed[x] + C;
    seed[x] = num[x - index] % M;
    result[x - index] = fabs(seed[x] / ((double)M));
  }
  vfloat64m1_t xResult;
  xResult = vle64_v_f64m1(&result[0], gvl);
  asm volatile("fence" ::);
  return xResult;
}
/**
 * Generates a normally distributed random number using the Box-Muller
 * transformation
 * @note This function is thread-safe
 * @param seed The seed array
 * @param index The specific index of the seed to be advanced
 * @return a double representing random number generated using the Box-Muller
 * algorithm
 * @see http://en.wikipedia.org/wiki/Normal_distribution, section computing
 * value for normal random distribution
 */
double randn(int *seed, int index) {
  /*Box-Muller algorithm*/
  double u = randu(seed, index);
  double v = randu(seed, index);
  double cosine = cos(2 * PI * v);
  double rt = -2 * log(u);
  return sqrt(rt) * cosine;
}

inline vfloat64m1_t randn_vector(long int *seed, int index, size_t gvl) {
  /*Box-Muller algorithm*/
  vfloat64m1_t xU = randu_vector(seed, index, gvl);
  vfloat64m1_t xV = randu_vector(seed, index, gvl);
  vfloat64m1_t xCosine;
  vfloat64m1_t xRt;

  xV = vfmul_vv_f64m1(vfmv_v_f_f64m1(PI * 2.0, gvl), xV, gvl);
  xCosine = __cos_1xf64(xV, gvl);
  asm volatile("fence" ::);
  xU = __log_1xf64(xU, gvl);
  xRt = vfmul_vv_f64m1(vfmv_v_f_f64m1(-2.0, gvl), xU, gvl);
  return vfmul_vv_f64m1(vfsqrt_v_f64m1(xRt, gvl), xCosine, gvl);
}
/**
 * Sets values of 3D matrix using randomly generated numbers from a normal
 * distribution
 * @param array3D The video to be modified
 * @param dimX The x dimension of the frame
 * @param dimY The y dimension of the frame
 * @param dimZ The number of frames
 * @param seed The seed array
 */
void addNoise(int *array3D, int *dimX, int *dimY, int *dimZ, int *seed) {
  int x, y, z;
  for (x = 0; x < *dimX; x++) {
    for (y = 0; y < *dimY; y++) {
      for (z = 0; z < *dimZ; z++) {
        array3D[x * *dimY * *dimZ + y * *dimZ + z] =
            array3D[x * *dimY * *dimZ + y * *dimZ + z] +
            (int)(5 * randn(seed, 0));
      }
    }
  }
}
/**
 * Fills a radius x radius matrix representing the disk
 * @param disk The pointer to the disk to be made
 * @param radius  The radius of the disk to be made
 */
void strelDisk(int *disk, int radius) {
  int diameter = radius * 2 - 1;
  int x, y;
  for (x = 0; x < diameter; x++) {
    for (y = 0; y < diameter; y++) {
      double distance = sqrt(pow((double)(x - radius + 1), 2) +
                             pow((double)(y - radius + 1), 2));
      if (distance < radius)
        disk[x * diameter + y] = 1;
    }
  }
}
/**
 * Dilates the provided video
 * @param matrix The video to be dilated
 * @param posX The x location of the pixel to be dilated
 * @param posY The y location of the pixel to be dilated
 * @param poxZ The z location of the pixel to be dilated
 * @param dimX The x dimension of the frame
 * @param dimY The y dimension of the frame
 * @param dimZ The number of frames
 * @param error The error radius
 */
void dilate_matrix(int *matrix, int posX, int posY, int posZ, int dimX,
                   int dimY, int dimZ, int error) {
  int startX = posX - error;
  while (startX < 0)
    startX++;
  int startY = posY - error;
  while (startY < 0)
    startY++;
  int endX = posX + error;
  while (endX > dimX)
    endX--;
  int endY = posY + error;
  while (endY > dimY)
    endY--;
  int x, y;
  for (x = startX; x < endX; x++) {
    for (y = startY; y < endY; y++) {
      double distance =
          sqrt(pow((double)(x - posX), 2) + pow((double)(y - posY), 2));
      if (distance < error)
        matrix[x * dimY * dimZ + y * dimZ + posZ] = 1;
    }
  }
}

/**
 * Dilates the target matrix using the radius as a guide
 * @param matrix The reference matrix
 * @param dimX The x dimension of the video
 * @param dimY The y dimension of the video
 * @param dimZ The z dimension of the video
 * @param error The error radius to be dilated
 * @param newMatrix The target matrix
 */
void imdilate_disk(int *matrix, int dimX, int dimY, int dimZ, int error,
                   int *newMatrix) {
  int x, y, z;
  for (z = 0; z < dimZ; z++) {
    for (x = 0; x < dimX; x++) {
      for (y = 0; y < dimY; y++) {
        if (matrix[x * dimY * dimZ + y * dimZ + z] == 1) {
          dilate_matrix(newMatrix, x, y, z, dimX, dimY, dimZ, error);
        }
      }
    }
  }
}
/**
 * Fills a 2D array describing the offsets of the disk object
 * @param se The disk object
 * @param numOnes The number of ones in the disk
 * @param neighbors The array that will contain the offsets
 * @param radius The radius used for dilation
 */
void getneighbors(int *se, double *neighbors, int radius) {
  int x, y;
  int neighY = 0;
  int center = radius - 1;
  int diameter = radius * 2 - 1;
  for (x = 0; x < diameter; x++) {
    for (y = 0; y < diameter; y++) {
      if (se[x * diameter + y]) {
        neighbors[neighY * 2] = (int)(y - center);
        neighbors[neighY * 2 + 1] = (int)(x - center);
        neighY++;
      }
    }
  }
}
/**
 * The synthetic video sequence we will work with here is composed of a
 * single moving object, circular in shape (fixed radius)
 * The motion here is a linear motion
 * the foreground intensity and the backgrounf intensity is known
 * the image is corrupted with zero mean Gaussian noise
 * @param I The video itself
 * @param IszX The x dimension of the video
 * @param IszY The y dimension of the video
 * @param Nfr The number of frames of the video
 * @param seed The seed array used for number generation
 */
int NEWMATRIX[ISZX * ISZY * NFR];
void videoSequence(int *I, int IszX, int IszY, int Nfr, int *seed) {
  int k;
  int max_size = IszX * IszY * Nfr;
  /*get object centers*/
  int x0 = (int)roundDouble(IszY / 2.0);
  int y0 = (int)roundDouble(IszX / 2.0);
  I[x0 * IszY * Nfr + y0 * Nfr + 0] = 1;

  /*move point*/
  int xk, yk, pos;
  for (k = 1; k < Nfr; k++) {
    xk = abs(x0 + (k - 1));
    yk = abs(y0 - 2 * (k - 1));
    pos = yk * IszY * Nfr + xk * Nfr + k;
    if (pos >= max_size)
      pos = 0;
    I[pos] = 1;
  }

  /*dilate matrix*/
  int *newMatrix = (int *)NEWMATRIX;
  imdilate_disk(I, IszX, IszY, Nfr, 5, newMatrix);
  int x, y;
  for (x = 0; x < IszX; x++) {
    for (y = 0; y < IszY; y++) {
      for (k = 0; k < Nfr; k++) {
        I[x * IszY * Nfr + y * Nfr + k] =
            newMatrix[x * IszY * Nfr + y * Nfr + k];
      }
    }
  }

  /*define background, add noise*/
  setIf(0, 100, I, &IszX, &IszY, &Nfr);
  setIf(1, 228, I, &IszX, &IszY, &Nfr);
  /*add noise*/
  addNoise(I, &IszX, &IszY, &Nfr, seed);
}
/**
 * Determines the likelihood sum based on the formula: SUM( (IK[IND] - 100)^2 -
 * (IK[IND] - 228)^2)/ 100
 * @param I The 3D matrix
 * @param ind The current ind array
 * @param numOnes The length of ind array
 * @return A double representing the sum
 */
double calcLikelihoodSum(int *I, int *ind, int numOnes) {
  double likelihoodSum = 0.0;
  int y;
  for (y = 0; y < numOnes; y++)
    likelihoodSum +=
        (pow((I[ind[y]] - 100), 2) - pow((I[ind[y]] - 228), 2)) / 50.0;
  return likelihoodSum;
}
/**
 * Finds the first element in the CDF that is greater than or equal to the
 * provided value and returns that index
 * @note This function uses sequential search
 * @param CDF The CDF
 * @param lengthCDF The length of CDF
 * @param value The value to be found
 * @return The index of value in the CDF; if value is never found, returns the
 * last index
 */
int findIndex(double *CDF, int lengthCDF, double value) {
  int index = -1;
  int x;

  // for(int a = 0; a < lengthCDF; a++)
  // {
  // printf("%f ",CDF[a]);
  // }
  // printf("\n");

  // printf("CDF[x] >= value ,%f >= %f \n",CDF[0],value);

  for (x = 0; x < lengthCDF; x++) {
    if (CDF[x] >= value) {
      index = x;
      break;
    }
  }
  if (index == -1) {
    return lengthCDF - 1;
  }
  return index;
}

/**
 * Finds the first element in the CDF that is greater than or equal to the
 * provided value and returns that index
 * @note This function uses binary search before switching to sequential search
 * @param CDF The CDF
 * @param beginIndex The index to start searching from
 * @param endIndex The index to stop searching
 * @param value The value to find
 * @return The index of value in the CDF; if value is never found, returns the
 * last index
 * @warning Use at your own risk; not fully tested
 */
int findIndexBin(double *CDF, int beginIndex, int endIndex, double value) {
  if (endIndex < beginIndex)
    return -1;
  int middleIndex = beginIndex + ((endIndex - beginIndex) / 2);
  /*check the value*/
  if (CDF[middleIndex] >= value) {
    /*check that it's good*/
    if (middleIndex == 0)
      return middleIndex;
    else if (CDF[middleIndex - 1] < value)
      return middleIndex;
    else if (CDF[middleIndex - 1] == value) {
      while (middleIndex > 0 && CDF[middleIndex - 1] == value)
        middleIndex--;
      return middleIndex;
    }
  }
  if (CDF[middleIndex] > value)
    return findIndexBin(CDF, beginIndex, middleIndex + 1, value);
  return findIndexBin(CDF, middleIndex - 1, endIndex, value);
}
/**
 * The implementation of the particle filter using OpenMP for many frames
 * @see http://openmp.org/wp/
 * @note This function is designed to work with a video of several frames. In
 * addition, it references a provided MATLAB function which takes the video, the
 * objxy matrix and the x and y arrays as arguments and returns the likelihoods
 * @param I The video to be run
 * @param IszX The x dimension of the video
 * @param IszY The y dimension of the video
 * @param Nfr The number of frames
 * @param seed The seed array used for random number generation
 * @param Nparticles The number of particles to be used
 */
#define RADIUS 5
// #define DIAMETER RADIUS*2-1;
#define DIAMETER 9
int DISK[DIAMETER * DIAMETER];
double WEIGHTS[NPARTICLES];
double LIKELIHOOD[NPARTICLES];
double ARRAYX[NPARTICLES];
double ARRAYY[NPARTICLES];
double XJ[NPARTICLES];
double YJ[NPARTICLES];
double CDF[NPARTICLES];
double U[NPARTICLES];
double OBJXY[DIAMETER * DIAMETER];
int IND[DIAMETER * DIAMETER * NPARTICLES];
int DISK_V[DIAMETER * DIAMETER];
double WEIGHTS_V[NPARTICLES];
double LIKELIHOOD_V[NPARTICLES];
double ARRAYX_V[NPARTICLES];
double ARRAYY_V[NPARTICLES];
double XJ_V[NPARTICLES];
double YJ_V[NPARTICLES];
double CDF_V[NPARTICLES];
double U_V[NPARTICLES];
double OBJXY_V[DIAMETER * DIAMETER];
int IND_V[DIAMETER * DIAMETER * NPARTICLES];

void particleFilter(int *I, int IszX, int IszY, int Nfr, int *seed,
                    int Nparticles, int *disk, double *objxy, double *weights,
                    double *likelihood, double *arrayX, double *arrayY,
                    double *xj, double *yj, double *CDF, double *u, int *ind) {

  int max_size = IszX * IszY * Nfr;
  start_timer();
  // original particle centroid
  double xe = roundDouble(IszY / 2.0);
  double ye = roundDouble(IszX / 2.0);

  // expected object locations, compared to center
  int radius = 5;
  int diameter = radius * 2 - 1;
  strelDisk(disk, radius);
  int countOnes = 0;
  int x, y;
  for (x = 0; x < diameter; x++) {
    for (y = 0; y < diameter; y++) {
      if (disk[x * diameter + y] == 1)
        countOnes++;
    }
  }

  // printf("countOnes = %ld \n",countOnes); // 69

  getneighbors(disk, objxy, radius);

  stop_timer();
  printf("TIME TO GET NEIGHBORS TOOK: %ld\n", get_timer());
  start_timer();
  // initial weights are all equal (1/Nparticles)
  // #pragma omp parallel for shared(weights, Nparticles) private(x)
  for (x = 0; x < Nparticles; x++) {
    weights[x] = 1 / ((double)(Nparticles));
  }
  stop_timer();
  printf("TIME TO GET WEIGHTSTOOK: %ld\n", get_timer());
  // initial likelihood to 0.0
  start_timer();
  // #pragma omp parallel for shared(arrayX, arrayY, xe, ye) private(x)
  for (x = 0; x < Nparticles; x++) {
    arrayX[x] = xe;
    arrayY[x] = ye;
  }
  int k;

  stop_timer();
  printf("TIME TO SET ARRAYS TOOK: %ld\n", get_timer());
  int indX, indY;
  for (k = 1; k < Nfr; k++) {
    start_timer();
    // apply motion model
    // draws sample from motion model (random walk). The only prior information
    // is that the object moves 2x as fast as in the y direction
    // #pragma omp parallel for shared(arrayX, arrayY, Nparticles, seed)
    // private(x)
    for (x = 0; x < Nparticles; x++) {
      arrayX[x] += 1 + 5 * randn(seed, x);
      arrayY[x] += -2 + 2 * randn(seed, x);
    }
    stop_timer();
    printf("TIME TO SET ERROR TOOK: %ld\n", get_timer());
    // particle filter likelihood
    // #pragma omp parallel for shared(likelihood, I, arrayX, arrayY, objxy,
    // ind)
    // private(x, y, indX, indY)
    start_timer();
    for (x = 0; x < Nparticles; x++) {
      // compute the likelihood: remember our assumption is that you know
      // foreground and the background image intensity distribution.
      // Notice that we consider here a likelihood ratio, instead of
      // p(z|x). It is possible in this case. why? a hometask for you.
      // calc ind
      for (y = 0; y < countOnes; y++) {
        indX = roundDouble(arrayX[x]) + objxy[y * 2 + 1];
        indY = roundDouble(arrayY[x]) + objxy[y * 2];
        ind[x * countOnes + y] = abs(indX * IszY * Nfr + indY * Nfr + k);
        if (ind[x * countOnes + y] >= max_size)
          ind[x * countOnes + y] = 0;
      }
      likelihood[x] = 0;
      for (y = 0; y < countOnes; y++)
        likelihood[x] += (pow((I[ind[x * countOnes + y]] - 100), 2) -
                          pow((I[ind[x * countOnes + y]] - 228), 2)) /
                         50.0;
      likelihood[x] = likelihood[x] / ((double)countOnes);
    }
    stop_timer();
    printf("TIME TO GET LIKELIHOODS TOOK: %ld\n", get_timer());
    // update & normalize weights
    // using equation (63) of Arulampalam Tutorial
    // #pragma omp parallel for shared(Nparticles, weights, likelihood)
    // private(x)
    start_timer();
    for (x = 0; x < Nparticles; x++) {
      weights[x] = weights[x] * exp(likelihood[x]);
    }
    stop_timer();
    printf("TIME TO GET EXP TOOK: %ld\n", get_timer());
    double sumWeights = 0;
    // #pragma omp parallel for private(x) reduction(+:sumWeights)
    start_timer();
    for (x = 0; x < Nparticles; x++) {
      sumWeights += weights[x];
    }
    stop_timer();
    printf("TIME TO SUM WEIGHTS TOOK: %ld\n", get_timer());
    // #pragma omp parallel for shared(sumWeights, weights) private(x)
    start_timer();
    for (x = 0; x < Nparticles; x++) {
      weights[x] = weights[x] / sumWeights;
    }
    stop_timer();
    printf("TIME TO NORMALIZE WEIGHTS TOOK: %ld\n", get_timer());
    xe = 0;
    ye = 0;
    // estimate the object location by expected values
    // #pragma omp parallel for private(x) reduction(+:xe, ye)
    start_timer();
    for (x = 0; x < Nparticles; x++) {
      xe += arrayX[x] * weights[x];
      ye += arrayY[x] * weights[x];
    }
    stop_timer();
    printf("TIME TO MOVE OBJECT TOOK: %ld\n", get_timer());
    start_timer();
    printf("XE: %lf\n", xe);
    printf("YE: %lf\n", ye);
    double distance = sqrt(pow((double)(xe - (int)roundDouble(IszY / 2.0)), 2) +
                           pow((double)(ye - (int)roundDouble(IszX / 2.0)), 2));
    printf("%lf\n", distance);
    // display(hold off for now)

    // pause(hold off for now)

    // resampling

    CDF[0] = weights[0];
    for (x = 1; x < Nparticles; x++) {
      CDF[x] = weights[x] + CDF[x - 1];
    }
    stop_timer();
    printf("TIME TO CALC CUM SUM TOOK: %ld\n", get_timer());
    start_timer();
    double u1 = (1 / ((double)(Nparticles))) * randu(seed, 0);
    // #pragma omp parallel for shared(u, u1, Nparticles) private(x)
    for (x = 0; x < Nparticles; x++) {
      u[x] = u1 + x / ((double)(Nparticles));
    }
    stop_timer();
    printf("TIME TO CALC U TOOK: %ld\n", get_timer());
    start_timer();
    int j, i;

    // #pragma omp parallel for shared(CDF, Nparticles, xj, yj, u, arrayX,
    //  arrayY) private(i, j)
    for (j = 0; j < Nparticles; j++) {
      i = findIndex(CDF, Nparticles, u[j]);
      if (i == -1)
        i = Nparticles - 1;
      // printf("%ld ", i);
      xj[j] = arrayX[i];
      yj[j] = arrayY[i];
    }
    // printf("\n");

    stop_timer();
    printf("TIME TO CALC NEW ARRAY X AND Y TOOK: %ld\n", get_timer());

    // #pragma omp parallel for shared(weights, Nparticles) private(x)
    start_timer();
    for (x = 0; x < Nparticles; x++) {
      // reassign arrayX and arrayY
      arrayX[x] = xj[x];
      arrayY[x] = yj[x];
      weights[x] = 1 / ((double)(Nparticles));
    }
    stop_timer();
    printf("TIME TO RESET WEIGHTS TOOK: %ld\n", get_timer());
  }
}

int64_t LOCATIONS[NPARTICLES];
void particleFilter_vector(int *I, int IszX, int IszY, int Nfr, int *seed,
                           long int *seed_64, int Nparticles, int *disk,
                           double *objxy, double *weights, double *likelihood,
                           double *arrayX, double *arrayY, double *xj,
                           double *yj, double *CDF, double *u, int *ind) {

  int max_size = IszX * IszY * Nfr;
  int radius = 5;
  int diameter = radius * 2 - 1;

  start_timer();
  // original particle centroid
  double xe = roundDouble(IszY / 2.0);
  double ye = roundDouble(IszX / 2.0);

  strelDisk(disk, radius);
  int countOnes = 0;
  int x, y;
  for (x = 0; x < diameter; x++) {
    for (y = 0; y < diameter; y++) {
      if (disk[x * diameter + y] == 1)
        countOnes++;
    }
  }

  // printf("countOnes = %ld \n",countOnes); // 69

  getneighbors(disk, objxy, radius);

  stop_timer();
  printf("TIME TO GET NEIGHBORS TOOK: %ld\n", get_timer());
  // initial weights are all equal (1/Nparticles)
  start_timer();
  // #pragma omp parallel for shared(weights, Nparticles) private(x)
  /*
  for(x = 0; x < Nparticles; x++){
      weights[x] = 1/((double)(Nparticles));
  }*/
  // size_t gvl = __builtin_epi_vsetvl(Nparticles, __epi_e64,
  // __epi_m1);
  size_t gvl = vsetvl_e64m1(Nparticles); // PLCT

  vfloat64m1_t xweights = vfmv_v_f_f64m1(1.0 / ((double)(Nparticles)), gvl);
  for (x = 0; x < Nparticles; x = x + gvl) {
    // gvl     = __builtin_epi_vsetvl(Nparticles-x, __epi_e64, __epi_m1);
    gvl = vsetvl_e64m1(Nparticles - x); // PLCT

    vse64_v_f64m1(&weights[x], xweights, gvl);
  }
  asm volatile("fence" ::);

  stop_timer();
  printf("TIME TO GET WEIGHTSTOOK: %ld\n", get_timer());
  start_timer();
  // initial likelihood to 0.0

  /*
  //#pragma omp parallel for shared(arrayX, arrayY, xe, ye) private(x)
  for(x = 0; x < Nparticles; x++){
      arrayX[x] = xe;
      arrayY[x] = ye;
  }
  */
  // gvl     = __builtin_epi_vsetvl(Nparticles, __epi_e64, __epi_m1);
  gvl = vsetvl_e64m1(Nparticles); // PLCT
  vfloat64m1_t xArrayX = vfmv_v_f_f64m1(xe, gvl);
  vfloat64m1_t xArrayY = vfmv_v_f_f64m1(ye, gvl);
  for (int i = 0; i < Nparticles; i = i + gvl) {
    // gvl     = __builtin_epi_vsetvl(Nparticles-i, __epi_e64, __epi_m1);
    gvl = vsetvl_e64m1(Nparticles - i); // PLCT
    vse64_v_f64m1(&arrayX[i], xArrayX, gvl);
    vse64_v_f64m1(&arrayY[i], xArrayY, gvl);
  }
  asm volatile("fence" ::);

  vfloat64m1_t xAux;

  int k;
  stop_timer();
  printf("TIME TO SET ARRAYS TOOK: %ld\n", get_timer());
  int indX, indY;
  for (k = 1; k < Nfr; k++) {
    start_timer();
    // apply motion model
    // draws sample from motion model (random walk). The only prior information
    // is that the object moves 2x as fast as in the y direction
    // gvl     = __builtin_epi_vsetvl(Nparticles, __epi_e64, __epi_m1);
    gvl = vsetvl_e64m1(Nparticles); // PLCT
    for (x = 0; x < Nparticles; x = x + gvl) {
      // gvl     = __builtin_epi_vsetvl(Nparticles-x, __epi_e64, __epi_m1);
      gvl = vsetvl_e64m1(Nparticles - x); // PLCT
      xArrayX = vle64_v_f64m1(&arrayX[x], gvl);
      asm volatile("fence" ::);
      xAux = randn_vector(seed_64, x, gvl);
      asm volatile("fence" ::);
      xAux = vfmul_vv_f64m1(xAux, vfmv_v_f_f64m1(5.0, gvl), gvl);
      xAux = vfadd_vv_f64m1(xAux, vfmv_v_f_f64m1(1.0, gvl), gvl);
      xArrayX = vfadd_vv_f64m1(xAux, xArrayX, gvl);
      vse64_v_f64m1(&arrayX[x], xArrayX, gvl);

      xArrayY = vle64_v_f64m1(&arrayY[x], gvl);
      asm volatile("fence" ::);
      xAux = randn_vector(seed_64, x, gvl);
      asm volatile("fence" ::);
      xAux = vfmul_vv_f64m1(xAux, vfmv_v_f_f64m1(2.0, gvl), gvl);
      xAux = vfadd_vv_f64m1(xAux, vfmv_v_f_f64m1(-2.0, gvl), gvl);
      xArrayY = vfadd_vv_f64m1(xAux, xArrayY, gvl);
      vse64_v_f64m1(&arrayY[x], xArrayY, gvl);
    }
    asm volatile("fence" ::);
    /*
    //#pragma omp parallel for shared(arrayX, arrayY, Nparticles, seed)
    private(x)
    for(x = 0; x < Nparticles; x++){
        arrayX[x] += 1 + 5*randn(seed, x);
        arrayY[x] += -2 + 2*randn(seed, x);
    }
    */
    stop_timer();
    printf("TIME TO SET ERROR TOOK: %ld\n", get_timer());
    start_timer();
    // particle filter likelihood
    // #pragma omp parallel for shared(likelihood, I, arrayX, arrayY, objxy,
    // ind)
    // private(x, y, indX, indY)
    for (x = 0; x < Nparticles; x++) {
      // compute the likelihood: remember our assumption is that you know
      // foreground and the background image intensity distribution.
      // Notice that we consider here a likelihood ratio, instead of
      // p(z|x). It is possible in this case. why? a hometask for you.
      // calc ind
      for (y = 0; y < countOnes; y++) {
        indX = roundDouble(arrayX[x]) + objxy[y * 2 + 1];
        indY = roundDouble(arrayY[x]) + objxy[y * 2];
        ind[x * countOnes + y] = abs(indX * IszY * Nfr + indY * Nfr + k);
        if (ind[x * countOnes + y] >= max_size)
          ind[x * countOnes + y] = 0;
      }
      likelihood[x] = 0;
      for (y = 0; y < countOnes; y++)
        likelihood[x] += (pow((I[ind[x * countOnes + y]] - 100), 2) -
                          pow((I[ind[x * countOnes + y]] - 228), 2)) /
                         50.0;
      likelihood[x] = likelihood[x] / ((double)countOnes);
    }
    stop_timer();
    printf("TIME TO GET LIKELIHOODS TOOK: %ld\n", get_timer());
    start_timer();
    // update & normalize weights
    // using equation (63) of Arulampalam Tutorial
    // #pragma omp parallel for shared(Nparticles, weights, likelihood)
    // private(x)
    for (x = 0; x < Nparticles; x++) {
      weights[x] = weights[x] * exp(likelihood[x]);
    }
    stop_timer();
    printf("TIME TO GET EXP TOOK: %ld\n", get_timer());
    start_timer();
    double sumWeights = 0;
    // #pragma omp parallel for private(x) reduction(+:sumWeights)
    for (x = 0; x < Nparticles; x++) {
      sumWeights += weights[x];
    }
    stop_timer();
    printf("TIME TO SUM WEIGHTS TOOK: %ld\n", get_timer());
    start_timer();
    // #pragma omp parallel for shared(sumWeights, weights) private(x)
    for (x = 0; x < Nparticles; x++) {
      weights[x] = weights[x] / sumWeights;
    }
    stop_timer();
    printf("TIME TO NORMALIZE WEIGHTS TOOK: %ld\n", get_timer());
    start_timer();
    xe = 0;
    ye = 0;
    // estimate the object location by expected values
    // #pragma omp parallel for private(x) reduction(+:xe, ye)
    for (x = 0; x < Nparticles; x++) {
      xe += arrayX[x] * weights[x];
      ye += arrayY[x] * weights[x];
    }
    stop_timer();
    printf("TIME TO MOVE OBJECT TOOK: %ld\n", get_timer());
    start_timer();
    printf("XE: %lf\n", xe);
    printf("YE: %lf\n", ye);
    double distance = sqrt(pow((double)(xe - (int)roundDouble(IszY / 2.0)), 2) +
                           pow((double)(ye - (int)roundDouble(IszX / 2.0)), 2));
    printf("%lf\n", distance);
    // display(hold off for now)

    // pause(hold off for now)

    // resampling

    CDF[0] = weights[0];
    for (x = 1; x < Nparticles; x++) {
      CDF[x] = weights[x] + CDF[x - 1];
    }
    stop_timer();
    printf("TIME TO CALC CUM SUM TOOK: %ld\n", get_timer());
    start_timer();
    double u1 = (1 / ((double)(Nparticles))) * randu(seed, 0);
    // #pragma omp parallel for shared(u, u1, Nparticles) private(x)
    for (x = 0; x < Nparticles; x++) {
      u[x] = u1 + x / ((double)(Nparticles));
    }
    stop_timer();
    printf("TIME TO CALC U TOOK: %ld\n", get_timer());
    start_timer();

    int j, i;

    vbool64_t xComp;
    vint64m1_t xMask;

    vfloat64m1_t xCDF;
    vfloat64m1_t xU;
    vint64m1_t xArray;

    long int vector_complete;
    long int *locations = (long int *)LOCATIONS;
    long int valid;
    // gvl     = __builtin_epi_vsetvl(Nparticles, __epi_e64, __epi_m1);
    gvl = vsetvl_e64m1(Nparticles); // PLCT
    for (i = 0; i < Nparticles; i = i + gvl) {
      //  gvl     = __builtin_epi_vsetvl(Nparticles-i, __epi_e64, __epi_m1);
      gvl = vsetvl_e64m1(Nparticles - i); // PLCT
      vector_complete = 0;
      xMask = vmv_v_x_i64m1(0, gvl);
      xArray = vmv_v_x_i64m1(Nparticles - 1, gvl);
      xU = vle64_v_f64m1(&u[i], gvl);
      for (j = 0; j < Nparticles; j++) {
        xCDF = vfmv_v_f_f64m1(CDF[j], gvl);
        xComp = vmfge_vv_f64m1_b64(xCDF, xU, gvl);
        xComp = vmseq_vx_i64m1_b64(
            vxor_vv_i64m1(vmerge_vxm_i64m1(xComp, vundefined_i64m1(), 1, gvl),
                          xMask, gvl),
            1, gvl);
        valid = vfirst_m_b64(xComp, gvl);
        if (valid != -1) {
          xArray = vmerge_vvm_i64m1(xComp, xArray, vmv_v_x_i64m1(j, gvl), gvl);
          xMask = vor_vv_i64m1(
              vmerge_vxm_i64m1(xComp, vundefined_i64m1(), 1, gvl), xMask, gvl);
          vector_complete = vcpop_m_b64(vmseq_vx_i64m1_b64(xMask, 1, gvl), gvl);
        }
        if (vector_complete == (int)gvl) {
          break;
        }
        // asm volatile ("fence"::);
      }
      vse64_v_i64m1(&locations[i], xArray, gvl);
    }
    asm volatile("fence" ::);
    // for(i = 0; i < Nparticles; i++) { printf("%ld ", locations[i]); }
    // printf("\n");

    // #pragma omp parallel for shared(CDF, Nparticles, xj, yj, u, arrayX,
    //  arrayY) private(i, j)
    for (j = 0; j < Nparticles; j++) {
      i = locations[j];
      xj[j] = arrayX[i];
      yj[j] = arrayY[i];
    }
    // for(j = 0; j < Nparticles; j++){ printf("%lf ", xj[i]); } printf("\n");
    // for(j = 0; j < Nparticles; j++){ printf("%lf ", yj[i]); } printf("\n");

    stop_timer();
    printf("TIME TO CALC NEW ARRAY X AND Y TOOK: %ld\n", get_timer());
    start_timer();

    // #pragma omp parallel for shared(weights, Nparticles) private(x)
    for (x = 0; x < Nparticles; x++) {
      // reassign arrayX and arrayY
      arrayX[x] = xj[x];
      arrayY[x] = yj[x];
      weights[x] = 1 / ((double)(Nparticles));
    }
    stop_timer();
    printf("TIME TO RESET WEIGHTS TOOK: %ld\n", get_timer());
  }
}

int main() {

  int error;

  // char *usage = "-x <dimX> -y <dimY> -z <Nfr> -np <Nparticles>";
  int IszX, IszY, Nfr, Nparticles;

  IszX = ISZX;
  IszY = ISZY;
  Nfr = NFR;
  Nparticles = NPARTICLES;

  // Establish seed
  int i;
  for (i = 0; i < Nparticles; i++) {
    seed[i] = Seed * i;
  }
  for (i = 0; i < Nparticles; i++) {
    seed_64[i] = (long int)seed[i];
  }
  // Call Video sequence and measure cycles
  start_timer();
  videoSequence(I, IszX, IszY, Nfr, seed);
  stop_timer();
  printf("Video sequence took %ld cycles.\n", get_timer());

  // Call scalar particle filter and measure cycles
  int end = get_timer();
  start_timer();
  particleFilter(I, IszX, IszY, Nfr, seed, Nparticles, (int *)DISK,
                 (double *)OBJXY, (double *)WEIGHTS, (double *)LIKELIHOOD,
                 (double *)ARRAYX, (double *)ARRAYY, (double *)XJ, (double *)YJ,
                 (double *)CDF, (double *)U, (int *)IND);
  stop_timer();
  end = get_timer() - end;
  printf("Scalar particle filter took %ld cycles.\n", end);
  // Call vector particle filter and measure cycles
  start_timer();
  particleFilter_vector(I, IszX, IszY, Nfr, seed, seed_64, Nparticles,
                        (int *)DISK_V, (double *)OBJXY_V, (double *)WEIGHTS_V,
                        (double *)LIKELIHOOD_V, (double *)ARRAYX_V,
                        (double *)ARRAYY_V, (double *)XJ_V, (double *)YJ_V,
                        (double *)CDF_V, (double *)U_V, (int *)IND_V);
  stop_timer();
  end = get_timer() - end;
  printf("Vector particle filter took %ld cycles.\n", end);

  // Check results only after the benchmark works
  // error = check_result();
  error = 0;

  return error;
}
