// See LICENSE and LICENSE_1 for licensing terms of the original
// and vectorized version, respectively.

/*************************************************************************
 * RISC-V Vectorized Version
 * Author: Cristóbal Ramírez Lazo
 * email: cristobal.ramirez@bsc.es
 * Barcelona Supercomputing Center (2020)
 *************************************************************************/

// Modifications + Fixes to the vectorized version by:
// Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include "lavamd.h"
#include "stdio.h"
void kernel(fp alpha, uint64_t n_boxes, box_str *box, FOUR_VECTOR *rv, fp *qv,
            FOUR_VECTOR *fv, uint64_t NUMBER_PAR_PER_BOX) {

  ///////////////
  // Variables //
  ///////////////

  // parameters
  fp a2;

  // counters
  uint64_t i, j, k, l;

  // home box
  long first_i;
  FOUR_VECTOR *rA;
  FOUR_VECTOR *fA;

  // neighbor box
  int pointer;
  long first_j;
  FOUR_VECTOR *rB;
  fp *qB;

  // common
  fp r2;
  fp u2;
  fp fs;
  fp vij;
  fp fxij, fyij, fzij;
  THREE_VECTOR d;

  /////////////////
  //  MCPU SETUP //
  /////////////////

  // Inputs
  a2 = 2.0 * alpha * alpha;

  //////////////////////////
  // Process interactions //
  //////////////////////////

  for (l = 0; l < n_boxes; ++l) {

    //---------------------------
    //	home box - box parameters
    //---------------------------

    // offset to common arrays
    first_i = box[l].offset;

    //---------------------------
    //	home box - distance, force, charge and type parameters from common
    // arrays
    //---------------------------

    rA = &rv[first_i];
    fA = &fv[first_i];

    //---------------------------
    //	Do for the # of (home+neighbor) boxes
    //---------------------------
    for (k = 0; k < (uint64_t)(1 + box[l].nn); ++k) {

      //-----------------------
      //	neighbor box - get pointer to the right box
      //-----------------------

      if (k == 0) {
        // set first box to be processed to home box
        pointer = l;
      } else {
        // remaining boxes are neighbor boxes
        pointer = box[l].nei[k - 1].number;
      }

      //-----------------------
      //	neighbor box - box parameters
      //-----------------------

      first_j = box[pointer].offset;

      //-----------------------
      //	neighbor box - distance, force, charge and type parameters
      //-----------------------

      rB = &rv[first_j];
      qB = &qv[first_j];

      //-----------------------
      //	Do for the # of particles in home box
      //-----------------------

      for (i = 0; i < NUMBER_PAR_PER_BOX; ++i) {
        // do for the # of particles in current (home or neighbor) box
        for (j = 0; j < NUMBER_PAR_PER_BOX; ++j) {
          // coefficients
          r2 = rA[i].v + rB[j].v - DOT(rA[i], rB[j]);
          u2 = a2 * r2;
          vij = exp(-u2);
          fs = 2. * vij;
          d.x = rA[i].x - rB[j].x;
          d.y = rA[i].y - rB[j].y;
          d.z = rA[i].z - rB[j].z;
          fxij = fs * d.x;
          fyij = fs * d.y;
          fzij = fs * d.z;

          // forces
          fA[i].v += qB[j] * vij;
          fA[i].x += qB[j] * fxij;
          fA[i].y += qB[j] * fyij;
          fA[i].z += qB[j] * fzij;
        }
      }
    }
  }
}

void kernel_vec(fp alpha, uint64_t n_boxes, box_str *box, FOUR_VECTOR *rv,
                fp *qv, FOUR_VECTOR *fv, uint64_t NUMBER_PAR_PER_BOX) {

  //================
  //	Variables
  //================

  // parameters
  fp a2;

  // counters
  uint64_t i, j, k, l;

  // home box
  long first_i;
  FOUR_VECTOR *rA;
  FOUR_VECTOR *fA;

  // neighbor box
  int pointer;
  long first_j;
  FOUR_VECTOR *rB;
  fp *qB;

  //==============
  //	INPUTS
  //==============

  a2 = 2.0 * alpha * alpha;

  //===========================
  //	PROCESS INTERACTIONS
  //===========================

  for (l = 0; l < n_boxes; ++l) {

    //-----------------------------
    //	home box - box parameters
    //-----------------------------

    first_i = box[l].offset; // offset to common arrays

    //---------------------------------------------------------------------
    //	home box - distance, force, charge and type parameters from common
    // arrays
    //---------------------------------------------------------------------

    rA = &rv[first_i];
    fA = &fv[first_i];

    //-----------------------------------------
    //	Do for the # of (home+neighbor) boxes
    //-----------------------------------------
    for (k = 0; k < (uint64_t)(1 + box[l].nn); k++) {

      //---------------------------------------
      //	neighbor box - get pointer to the right box
      //---------------------------------------

      if (k == 0) {
        pointer = l; // set first box to be processed to home box
      } else {
        pointer =
            box[l].nei[k - 1].number; // remaining boxes are neighbor boxes
      }

      //---------------------------------------
      //	neighbor box - box parameters
      //---------------------------------------

      first_j = box[pointer].offset;

      //---------------------------------------
      //	neighbor box - distance, force, charge and type parameters
      //---------------------------------------

      rB = &rv[first_j];
      qB = &qv[first_j];

      //---------------------------------------
      //	Do for the # of particles in home box
      //---------------------------------------
      for (i = 0; i < NUMBER_PAR_PER_BOX; ++i) {

        unsigned long int gvl = vsetvl_e32m1(NUMBER_PAR_PER_BOX);

        _MMR_f32 xr2;
        _MMR_f32 xDOT;
        _MMR_f32 xu2;
        _MMR_f32 xa2 = _MM_SET_f32(a2, gvl);
        _MMR_f32 xvij;
        _MMR_f32 xrA_v = _MM_SET_f32(rA[i].v, gvl);
        _MMR_f32 xrA_x = _MM_SET_f32(rA[i].x, gvl);
        _MMR_f32 xrA_y = _MM_SET_f32(rA[i].y, gvl);
        _MMR_f32 xrA_z = _MM_SET_f32(rA[i].z, gvl);
        _MMR_f32 xrB_v;
        _MMR_f32 xrB_x;
        _MMR_f32 xrB_y;
        _MMR_f32 xrB_z;
        _MMR_f32 xd_x;
        _MMR_f32 xd_y;
        _MMR_f32 xd_z;
        _MMR_f32 xfxij;
        _MMR_f32 xfyij;
        _MMR_f32 xfzij;
        _MMR_f32 xfs;
        _MMR_f32 xqB;
        _MMR_f32 xfA_v = _MM_SET_f32(0.0, gvl);
        _MMR_f32 xfA_x = _MM_SET_f32(0.0, gvl);
        _MMR_f32 xfA_y = _MM_SET_f32(0.0, gvl);
        _MMR_f32 xfA_z = _MM_SET_f32(0.0, gvl);
        _MMR_f32 xfA_1_v = _MM_SET_f32(0.0, 1);
        _MMR_f32 xfA_1_x = _MM_SET_f32(0.0, 1);
        _MMR_f32 xfA_1_y = _MM_SET_f32(0.0, 1);
        _MMR_f32 xfA_1_z = _MM_SET_f32(0.0, 1);

        // do for the # of particles in current (home or neighbor) box
        for (j = 0; j < NUMBER_PAR_PER_BOX; j += gvl) {
          gvl = vsetvl_e32m1(NUMBER_PAR_PER_BOX - j);
          // coefficients
          xrB_v = _MM_LOAD_STRIDE_f32(&rB[j].v, 16, gvl);
          xrB_x = _MM_LOAD_STRIDE_f32(&rB[j].x, 16, gvl);
          xrB_y = _MM_LOAD_STRIDE_f32(&rB[j].y, 16, gvl);
          xrB_z = _MM_LOAD_STRIDE_f32(&rB[j].z, 16, gvl);
          // r2 = rA[i].v + rB[j].v - DOT(rA[i],rB[j]);
          xr2 = _MM_ADD_f32(xrA_v, xrB_v, gvl);
          xDOT = _MM_MUL_f32(xrA_x, xrB_x, gvl);
          xDOT = _MM_MACC_f32(xDOT, xrA_y, xrB_y, gvl);
          xDOT = _MM_MACC_f32(xDOT, xrA_z, xrB_z, gvl);
          xr2 = _MM_SUB_f32(xr2, xDOT, gvl);
          // u2 = a2*r2;
          xu2 = _MM_MUL_f32(xa2, xr2, gvl);
          // vij= exp(-u2);
          xvij = __exp_2xf32(_MM_VFSGNJN_f32(xu2, xu2, gvl), gvl);
          // fs = 2.*vij;
          xfs = _MM_MUL_f32(_MM_SET_f32(2.0f, gvl), xvij, gvl);
          // d.x = rA[i].x  - rB[j].x;
          xd_x = _MM_SUB_f32(xrA_x, xrB_x, gvl);
          // d.y = rA[i].y  - rB[j].y;
          xd_y = _MM_SUB_f32(xrA_y, xrB_y, gvl);
          // d.z = rA[i].z  - rB[j].z;
          xd_z = _MM_SUB_f32(xrA_z, xrB_z, gvl);
          // fxij=fs*d.x;
          xfxij = _MM_MUL_f32(xfs, xd_x, gvl);
          // fyij=fs*d.y;
          xfyij = _MM_MUL_f32(xfs, xd_y, gvl);
          // fzij=fs*d.z;
          xfzij = _MM_MUL_f32(xfs, xd_z, gvl);

          // forces
          // fA[i].v +=  qB[j]*vij;
          // fA[i].x +=  qB[j]*fxij;
          // fA[i].y +=  qB[j]*fyij;
          // fA[i].z +=  qB[j]*fzij;
          gvl = vsetvl_e32m1(NUMBER_PAR_PER_BOX);
          xqB = _MM_LOAD_f32(&qB[j], gvl);
          xfA_v = _MM_MACC_f32(xfA_v, xqB, xvij, gvl);
          xfA_x = _MM_MACC_f32(xfA_x, xqB, xfxij, gvl);
          xfA_y = _MM_MACC_f32(xfA_y, xqB, xfyij, gvl);
          xfA_z = _MM_MACC_f32(xfA_z, xqB, xfzij, gvl);
        }

        gvl = vsetvl_e32m1(NUMBER_PAR_PER_BOX);

        // Accumulate final results
        xfA_1_v = _MM_LOAD_f32(&fA[i].v, 1);
        xfA_1_x = _MM_LOAD_f32(&fA[i].x, 1);
        xfA_1_y = _MM_LOAD_f32(&fA[i].y, 1);
        xfA_1_z = _MM_LOAD_f32(&fA[i].z, 1);

        xfA_1_v = _MM_REDSUM_f32(xfA_1_v, xfA_v, xfA_1_v, gvl);
        xfA_1_x = _MM_REDSUM_f32(xfA_1_x, xfA_x, xfA_1_x, gvl);
        xfA_1_y = _MM_REDSUM_f32(xfA_1_y, xfA_y, xfA_1_y, gvl);
        xfA_1_z = _MM_REDSUM_f32(xfA_1_z, xfA_z, xfA_1_z, gvl);
        _MM_STORE_f32(&fA[i].v, xfA_1_v, 1);
        _MM_STORE_f32(&fA[i].x, xfA_1_x, 1);
        _MM_STORE_f32(&fA[i].y, xfA_1_y, 1);
        _MM_STORE_f32(&fA[i].z, xfA_1_z, 1);
      }
    }
  }
}
