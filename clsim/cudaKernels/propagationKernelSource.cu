/*The MIT License (MIT)

Copyright (c) 2020, Ramona Hohl, rhohl@nvidia.com

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

/* 
    implements main simulation kernel as well as host code to launch it
*/

// includes
// ------------------
#include "propagationKernelSource.cuh"

#include <cuda.h>
#include <cuda_runtime_api.h>
#include <iostream>
#include <chrono>

#include "settings.cuh"
#include "dataStructCuda.cuh"
#include "utils.cuh"
#include "rng.cuh"
#include "propagationKernelFunctions.cuh"
#include "zOffsetHandling.cuh"
#include "wlenGeneration.cuh"
#include "scatteringAndAbsorbtionData.cuh"
// ------------------

// remark: ignored tabulate version, removed ifdef TABULATE
// also removed ifdef DOUBLEPRECISION.
// SAVE_PHOTON_HISTORY  and SAVE_ALL_PHOTONS are not define for now, i.e. commented out these snippets,
// s.t. it corresponds to the default contstructor of I3CLSimStepToPhotonConverterOpenCL

__global__ __launch_bounds__(NTHREADS_PER_BLOCK, 4) void propKernel( I3CLSimStepCuda* __restrict__ steps, int numSteps, 
                                                                     I3CLSimPhotonCuda* __restrict__ outputPhotons, int* numHits,
                                                                     const float* wlenLut, const float* zOffsetLut, 
                                                                     const unsigned short* __restrict__ geoLayerToOMNumIndexPerStringSet, 
                                                                     uint64_t* __restrict__ rng_x, uint32_t* __restrict__ rng_a); 

// maxNumbWOrkItems from  CL rndm arrays
void init_RDM_CUDA(int maxNumWorkitems, uint64_t* MWC_RNG_x, uint32_t* MWC_RNG_a, uint64_t** d_MWC_RNG_x,
                   uint32_t** d_MWC_RNG_a)
{
    CUDA_ERR_CHECK(cudaMalloc(d_MWC_RNG_a, maxNumWorkitems * sizeof(uint32_t)));
    CUDA_ERR_CHECK(cudaMalloc(d_MWC_RNG_x, maxNumWorkitems * sizeof(uint64_t)));

    CUDA_ERR_CHECK(cudaMemcpy(*d_MWC_RNG_a, MWC_RNG_a, maxNumWorkitems * sizeof(uint32_t), cudaMemcpyHostToDevice));
    CUDA_ERR_CHECK(cudaMemcpy(*d_MWC_RNG_x, MWC_RNG_x, maxNumWorkitems * sizeof(uint64_t), cudaMemcpyHostToDevice));

    cudaDeviceSynchronize();
    printf("RNG is set up on CUDA gpu %d. \n", maxNumWorkitems);
}

void launch_CudaPropogate(const I3CLSimStep* __restrict__ in_steps, int nsteps, const uint32_t maxHitIndex,
                          unsigned short* geoLayerToOMNumIndexPerStringSet, int ngeolayer,
                          I3CLSimPhotonSeries& outphotons, uint64_t* __restrict__ MWC_RNG_x,
                          uint32_t* __restrict__ MWC_RNG_a, int sizeRNG, float& totalCudaKernelTime)
{
    // set up congruental random number generator, reusing host arrays and randomService from
    // I3CLSimStepToPhotonConverterOpenCL setup.
    uint64_t* d_MWC_RNG_x;
    uint32_t* d_MWC_RNG_a;
    init_RDM_CUDA(sizeRNG, MWC_RNG_x, MWC_RNG_a, &d_MWC_RNG_x, &d_MWC_RNG_a);

    printf("nsteps total = %d but dividing into %d launches of max size %d \n", nsteps, 1, nsteps);
    unsigned short* d_geolayer;
    CUDA_ERR_CHECK(cudaMalloc((void**)&d_geolayer, ngeolayer * sizeof(unsigned short)));
    CUDA_ERR_CHECK(cudaMemcpy(d_geolayer, geoLayerToOMNumIndexPerStringSet, ngeolayer * sizeof(unsigned short),
                              cudaMemcpyHostToDevice));

    struct I3CLSimStepCuda* h_cudastep = (struct I3CLSimStepCuda*)malloc(nsteps * sizeof(struct I3CLSimStepCuda));

    for (int i = 0; i < nsteps; i++) {
        h_cudastep[i] = I3CLSimStep(in_steps[i]);
    }

    I3CLSimStepCuda* d_cudastep;
    CUDA_ERR_CHECK(cudaMalloc((void**)&d_cudastep, nsteps * sizeof(I3CLSimStepCuda)));
    CUDA_ERR_CHECK(cudaMemcpy(d_cudastep, h_cudastep, nsteps * sizeof(I3CLSimStepCuda), cudaMemcpyHostToDevice));

    uint32_t* d_hitIndex;
    uint32_t h_hitIndex[1];
    h_hitIndex[0] = 0;
    CUDA_ERR_CHECK(cudaMalloc((void**)&d_hitIndex, 1 * sizeof(uint32_t)));
    CUDA_ERR_CHECK(cudaMemcpy(d_hitIndex, h_hitIndex, 1 * sizeof(uint32_t), cudaMemcpyHostToDevice));

    I3CLSimPhotonCuda* d_cudaphotons;
    CUDA_ERR_CHECK(cudaMalloc((void**)&d_cudaphotons, maxHitIndex * sizeof(I3CLSimPhotonCuda)));

    int numBlocks = (nsteps + NTHREADS_PER_BLOCK - 1) / NTHREADS_PER_BLOCK;
    printf("launching kernel propKernel<<< %d , %d >>>( .., nsteps=%d)  \n", numBlocks, NTHREADS_PER_BLOCK, nsteps);

    std::chrono::time_point<std::chrono::system_clock> startKernel = std::chrono::system_clock::now();
    propKernel<<<numBlocks, NTHREADS_PER_BLOCK>>>(d_hitIndex, maxHitIndex, d_geolayer, d_cudastep, nsteps,
                                                  d_cudaphotons, d_MWC_RNG_x, d_MWC_RNG_a);

    CUDA_ERR_CHECK(cudaDeviceSynchronize());
    std::chrono::time_point<std::chrono::system_clock> endKernel = std::chrono::system_clock::now();
    totalCudaKernelTime = std::chrono::duration_cast<std::chrono::milliseconds>(endKernel - startKernel).count();

    CUDA_ERR_CHECK(cudaMemcpy(h_hitIndex, d_hitIndex, 1 * sizeof(uint32_t), cudaMemcpyDeviceToHost));
    int numberPhotons = h_hitIndex[0];

    if (numberPhotons > maxHitIndex) {
        printf("Maximum number of photons exceeded, only receiving %" PRIu32 " of %" PRIu32 " photons", maxHitIndex,
               numberPhotons);
        numberPhotons = maxHitIndex;
    }

    // copy (max fo maxHitIndex) photons to host.
    struct I3CLSimPhotonCuda* h_cudaphotons =
        (struct I3CLSimPhotonCuda*)malloc(numberPhotons * sizeof(struct I3CLSimPhotonCuda));
    CUDA_ERR_CHECK(
        cudaMemcpy(h_cudaphotons, d_cudaphotons, numberPhotons * sizeof(I3CLSimPhotonCuda), cudaMemcpyDeviceToHost));

    outphotons.resize(numberPhotons);
    for (int i = 0; i < numberPhotons; i++) {
        outphotons[i] = h_cudaphotons[i].getI3CLSimPhoton();
    }

    free(h_cudastep);
    free(h_cudaphotons);
    cudaFree(d_cudaphotons);
    cudaFree(d_cudastep);
    cudaFree(d_geolayer);
    cudaFree(d_MWC_RNG_a);
    cudaFree(d_MWC_RNG_x);
    printf("photon hits = %i from %i steps \n", numberPhotons, nsteps);
}

__global__ void propKernel( I3CLSimStepCuda* __restrict__ steps, int numSteps, 
                            I3CLSimPhotonCuda* __restrict__ outputPhotons, int* numHits,
                            const float* wlenLut, const float* zOffsetLut, 
                            const unsigned short* __restrict__ geoLayerToOMNumIndexPerStringSet, 
                            uint64_t* __restrict__ rng_x, uint32_t* __restrict__ rng_a))
{
    unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;

    __shared__ unsigned short geoLayerToOMNumIndexPerStringSetLocal[GEO_geoLayerToOMNumIndexPerStringSet_BUFFER_SIZE];
    __shared__ float _generateWavelength_0distYValuesShared[_generateWavelength_0NUM_DIST_ENTRIES];
    __shared__ float _generateWavelength_0distYCumulativeValuesShared[_generateWavelength_0NUM_DIST_ENTRIES];
    __shared__ float getWavelengthBias_dataShared[_generateWavelength_0NUM_DIST_ENTRIES];

    for (int ii = threadIdx.x; ii < GEO_geoLayerToOMNumIndexPerStringSet_BUFFER_SIZE; ii += blockDim.x) {
        geoLayerToOMNumIndexPerStringSetLocal[ii] = geoLayerToOMNumIndexPerStringSet[ii];
    }

    for (int ii = threadIdx.x; ii < _generateWavelength_0NUM_DIST_ENTRIES; ii += blockDim.x) {
        _generateWavelength_0distYValuesShared[ii] = _generateWavelength_0distYValues[ii];
        _generateWavelength_0distYCumulativeValuesShared[ii] = _generateWavelength_0distYCumulativeValues[ii];
        getWavelengthBias_dataShared[ii] = getWavelengthBias_data[ii];
    }
    __syncthreads();
    if (i >= nsteps) return;

    // download MWC RNG state
    uint64_t real_rnd_x = MWC_RNG_x[i];
    uint32_t real_rnd_a = MWC_RNG_a[i];
    uint64_t* rnd_x = &real_rnd_x;
    uint32_t* rnd_a = &real_rnd_a;

    const I3CLSimStepCuda step = inputSteps[i];
    float4 stepDir;
    {
        const float rho = sinf(step.dirAndLengthAndBeta.x);       // sin(theta)
        stepDir = float4{rho * cosf(step.dirAndLengthAndBeta.y),  // rho*cos(phi)
                         rho * sinf(step.dirAndLengthAndBeta.y),  // rho*sin(phi)
                         cosf(step.dirAndLengthAndBeta.x),        // cos(phi)
                         ZERO};
    }

    uint32_t photonsLeftToPropagate = step.numPhotons;
    I3CLPhoton photon;
    photon.absLength = 0;
    I3CLInitialPhoton photonInitial;

    while (photonsLeftToPropagate > 0) {
        if (photon.absLength < EPSILON) {
            photonInitial = createPhoton(step, stepDir,_generateWavelength_0distYValuesShared,_generateWavelength_0distYCumulativeValuesShared, RNG_ARGS_TO_CALL);
            photon = I3CLPhoton(photonInitial);
        }

        // this block is along the lines of the PPC kernel
        float distancePropagated;
        propPhoton(photon, distancePropagated, RNG_ARGS_TO_CALL);
        bool collided = checkForCollision(photon, photonInitial, step, distancePropagated, 
                                  hitIndex, maxHitIndex, outputPhotons, geoLayerToOMNumIndexPerStringSetLocal, getWavelengthBias_dataShared);

        if (collided) {
            // get rid of the photon if we detected it
            photon.absLength = ZERO;
        }

        // absorb or scatter the photon
        if (photon.absLength < EPSILON) {
            // photon was absorbed.
            // a new one will be generated at the begin of the loop.
            --photonsLeftToPropagate;
        } else {  // photon was NOT absorbed. scatter it and re-start the loop

            updatePhotonTrack(photon, distancePropagated);
            scatterPhoton(photon, RNG_ARGS_TO_CALL);
        }
    }  // end while

    // upload MWC RNG state
    MWC_RNG_x[i] = real_rnd_x;
    MWC_RNG_a[i] = real_rnd_a;
}
