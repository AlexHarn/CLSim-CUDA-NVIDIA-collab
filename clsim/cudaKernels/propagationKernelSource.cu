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

// !! order matters:
#include <fstream>
#include <propagationKernelFunctions.cuh>
#include <propagationKernelSource.cuh>

cudaError_t gl_err;

#define CUDA_ERR_CHECK(e)              \
    if (cudaError_t(e) != cudaSuccess) \
        printf("!!! Cuda Error %s in line %d \n", cudaGetErrorString(cudaError_t(e)), __LINE__);
#define CUDA_CHECK_CALL                     \
    gl_err = cudaGetLastError();            \
    if (cudaError_t(gl_err) != cudaSuccess) \
        printf("!!! Cuda Error %s in line %d \n", cudaGetErrorString(cudaError_t(gl_err)), __LINE__ - 1);

// remark: ignored tabulate version, removed ifdef TABULATE
// also removed ifdef DOUBLEPRECISION.
// SAVE_PHOTON_HISTORY  and SAVE_ALL_PHOTONS are not define for now, i.e. commented out these snippets,
// s.t. it corresponds to the default contstructor of I3CLSimStepToPhotonConverterOpenCL

__global__ __launch_bounds__(NTHREADS_PER_BLOCK, 4) void propKernel(
    uint32_t* hitIndex,          // deviceBuffer_CurrentNumOutputPhotons
    const uint32_t maxHitIndex,  // maxNumOutputPhotons_
    const unsigned short* __restrict__ geoLayerToOMNumIndexPerStringSet,
    const I3CLSimStepCuda* __restrict__ inputSteps,  // deviceBuffer_InputSteps
    int nsteps,
    I3CLSimPhotonCuda* __restrict__ outputPhotons,  // deviceBuffer_OutputPhotons

#ifdef SAVE_PHOTON_HISTORY
    float4* photonHistory,
#endif
    uint64_t* __restrict__ MWC_RNG_x, uint32_t* __restrict__ MWC_RNG_a);

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

/**
 * @brief Creates a single photon to be propagated
 * @param step the step to create the photon from
 * @param stepDir step direction to create the photon ( calculated in propGroup() )
 * @param _generateWavelength_0distY data needed for wavelength selection (pass pointer to global or shared data)
 * @param _generateWavelength_0distYCumulative data needed for wavelength selection (pass pointer to global or shared data) 
 * @param RNG_ARGS arguments for the random number generator (use RNG_ARGS_TO_CALL)
 */
__device__ __forceinline__ I3CLInitialPhoton createPhoton(const I3CLSimStepCuda &step, float4 stepDir, float* _generateWavelength_0distY, float* _generateWavelength_0distYCumulative, RNG_ARGS)
{
    // create a new photon
    I3CLInitialPhoton ph;
    createPhotonFromTrack(step, stepDir, RNG_ARGS_TO_CALL, ph.posAndTime, ph.dirAndWlen, _generateWavelength_0distY, _generateWavelength_0distYCumulative);
    ph.invGroupvel = 1.f / (getGroupVelocity(0, ph.dirAndWlen.w));

    // set an initial absorption length
    ph.absLength = -logf(RNG_CALL_UNIFORM_OC);
    return ph;
}

/**
 * @brief  propgates a single photon
 * @param ph the photon to propagate
 * @param distancePropagated the distance the photon was propagated during this iteration
 * @param RNG_ARGS arguments for the random number generator (use RNG_ARGS_TO_CALL)
 * @return the propagated distance
 */
__device__ __forceinline__ bool propPhoton(I3CLPhoton& ph, float& distancePropagated, RNG_ARGS)
{ 
    const float effective_z = ph.posAndTime.z - getTiltZShift(ph.posAndTime);
    const int currentPhotonLayer = min(max(findLayerForGivenZPos(effective_z), 0), MEDIUM_LAYERS - 1);
    const float photon_dz = ph.dirAndWlen.z;

    // add a correction factor to the number of absorption lengths
    // abs_lens_left before the photon is absorbed. This factor will be
    // taken out after this propagation step. Usually the factor is 1
    // and thus has no effect, but it is used in a direction-dependent
    // way for our model of ice anisotropy.
    const float abs_len_correction_factor = getDirectionalAbsLenCorrFactor(ph.dirAndWlen);
    ph.absLength *= abs_len_correction_factor;

    // the "next" medium boundary (either top or bottom, depending on
    // step direction)
    float mediumBoundary = (photon_dz < ZERO)
                                ? (mediumLayerBoundary(currentPhotonLayer))
                                : (mediumLayerBoundary(currentPhotonLayer) + (float)MEDIUM_LAYER_THICKNESS);

     // track this thing to the next scattering point
    float scaStepLeft = -logf(RNG_CALL_UNIFORM_OC);

    float currentScaLen = getScatteringLength(currentPhotonLayer, ph.dirAndWlen.w);
    float currentAbsLen = getAbsorptionLength(currentPhotonLayer, ph.dirAndWlen.w);

    float ais = (photon_dz * scaStepLeft - ((mediumBoundary - effective_z)) / currentScaLen) *
                (ONE / (float)MEDIUM_LAYER_THICKNESS);
    float aia = (photon_dz * ph.absLength - ((mediumBoundary - effective_z)) / currentAbsLen) *
                (ONE / (float)MEDIUM_LAYER_THICKNESS);

    
    // propagate through layers
    int j = currentPhotonLayer;
    if (photon_dz < 0) {
        for (; (j > 0) && (ais < ZERO) && (aia < ZERO);
                mediumBoundary -= (float)MEDIUM_LAYER_THICKNESS,
                currentScaLen = getScatteringLength(j, ph.dirAndWlen.w),
                currentAbsLen = getAbsorptionLength(j, ph.dirAndWlen.w), ais += 1.f / (currentScaLen),
                aia += 1.f / (currentAbsLen))
            --j;
    } else {
        for (; (j < MEDIUM_LAYERS - 1) && (ais > ZERO) && (aia > ZERO);
                mediumBoundary += (float)MEDIUM_LAYER_THICKNESS,
                currentScaLen = getScatteringLength(j, ph.dirAndWlen.w),
                currentAbsLen = getAbsorptionLength(j, ph.dirAndWlen.w), ais -= 1.f / (currentScaLen),
                aia -= 1.f / (currentAbsLen))
            ++j;
    }

    float distanceToAbsorption;
    if ((currentPhotonLayer == j) || ((my_fabs(photon_dz)) < EPSILON)) {
        distancePropagated = scaStepLeft * currentScaLen;
        distanceToAbsorption = ph.absLength * currentAbsLen;
    } else {
        const float recip_photon_dz = 1.f / (photon_dz);
        distancePropagated =
            (ais * ((float)MEDIUM_LAYER_THICKNESS) * currentScaLen + mediumBoundary - effective_z) *
            recip_photon_dz;
        distanceToAbsorption =
            (aia * ((float)MEDIUM_LAYER_THICKNESS) * currentAbsLen + mediumBoundary - effective_z) *
            recip_photon_dz;
    }

    // get overburden for distance i.e. check if photon is absorbed
    if (distanceToAbsorption < distancePropagated) {
        distancePropagated = distanceToAbsorption;
        ph.absLength = ZERO;
        return true;
    } else {
        ph.absLength = (distanceToAbsorption - distancePropagated) / currentAbsLen;
        
        // hoist the correction factor back out of the absorption length
        ph.absLength = ph.absLength / abs_len_correction_factor;
        return false;
    }

}

/**
 * @brief moves a photon along its track
 * @param ph the photon to move
 * @param distancePropagated the distance the photon was propagated this iteration
 */
__device__ __forceinline__  void updatePhotonTrack(I3CLPhoton& ph, float distancePropagated)
{
        ph.posAndTime.x += ph.dirAndWlen.x * distancePropagated;
        ph.posAndTime.y += ph.dirAndWlen.y * distancePropagated;
        ph.posAndTime.z += ph.dirAndWlen.z * distancePropagated;
        ph.posAndTime.w += ph.invGroupvel * distancePropagated;
        ph.totalPathLength += distancePropagated;
}

/**
 * @brief scatters a photon
 * @param ph the photon to scatter
 * @param RNG_ARGS arguments for the random number generator (use RNG_ARGS_TO_CALL) 
 */
__device__ __forceinline__  void scatterPhoton(I3CLPhoton& ph, RNG_ARGS)
{
     // optional direction transformation (for ice anisotropy)
    transformDirectionPreScatter(ph.dirAndWlen);

    // choose a scattering angle
    const float cosScatAngle = makeScatteringCosAngle(RNG_ARGS_TO_CALL);
    const float sinScatAngle = sqrt(ONE - sqr(cosScatAngle));

    // change the current direction by that angle
    scatterDirectionByAngle(cosScatAngle, sinScatAngle, ph.dirAndWlen, RNG_CALL_UNIFORM_CO);

    // optional direction transformation (for ice anisotropy)
    transformDirectionPostScatter(ph.dirAndWlen);

    ++ph.numScatters;
}

__global__ void propKernel(uint32_t* hitIndex,          // deviceBuffer_CurrentNumOutputPhotons
                           const uint32_t maxHitIndex,  // maxNumOutputPhotons_
                           const unsigned short* __restrict__ geoLayerToOMNumIndexPerStringSet,
                           const I3CLSimStepCuda* __restrict__ inputSteps,  // deviceBuffer_InputSteps
                           int nsteps,
                           I3CLSimPhotonCuda* __restrict__ outputPhotons,  // deviceBuffer_OutputPhotons
                           uint64_t* __restrict__ MWC_RNG_x, uint32_t* __restrict__ MWC_RNG_a)
{
#ifndef FUNCTION_getGroupVelocity_DOES_NOT_DEPEND_ON_LAYER
#error This kernel only works with a constant group velocity (constant w.r.t. layers)
#endif

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
    float abs_lens_left = ZERO;
    float abs_lens_initial = ZERO;

    float4 photonStartPosAndTime;
    float4 photonStartDirAndWlen;
    float4 photonPosAndTime;
    float4 photonDirAndWlen;
    uint32_t photonNumScatters = 0;
    float photonTotalPathLength = ZERO;

    float inv_groupvel = ZERO;

    while (photonsLeftToPropagate > 0) {
        if (abs_lens_left < EPSILON) {
            // create a new photon
            createPhotonFromTrack(step, stepDir, RNG_ARGS_TO_CALL, photonPosAndTime, photonDirAndWlen,
                                  _generateWavelength_0distYValuesShared,
                                  _generateWavelength_0distYCumulativeValuesShared);

            // save the start position and time
            photonStartPosAndTime = photonPosAndTime;
            photonStartDirAndWlen = photonDirAndWlen;

            photonNumScatters = 0;
            photonTotalPathLength = ZERO;

            inv_groupvel = 1.f / (getGroupVelocity(0, photonDirAndWlen.w));

            // the photon needs a lifetime. determine distance to next scatter and
            // absorption (this is in units of absorption/scattering lengths)
            abs_lens_initial = -logf(RNG_CALL_UNIFORM_OC);
            abs_lens_left = abs_lens_initial;
        }

        // this block is along the lines of the PPC kernel
        float distancePropagated;
        {
            const float effective_z = photonPosAndTime.z - getTiltZShift(photonPosAndTime);
            int currentPhotonLayer = min(max(findLayerForGivenZPos(effective_z), 0), MEDIUM_LAYERS - 1);
            const float photon_dz = photonDirAndWlen.z;

            // add a correction factor to the number of absorption lengths
            // abs_lens_left before the photon is absorbed. This factor will be taken
            // out after this propagation step. Usually the factor is 1 and thus has
            // no effect, but it is used in a direction-dependent way for our model of
            // ice anisotropy.

            const float abs_len_correction_factor = getDirectionalAbsLenCorrFactor(photonDirAndWlen);
            abs_lens_left *= abs_len_correction_factor;

            // the "next" medium boundary (either top or bottom, depending on step
            // direction)
            float mediumBoundary = (photon_dz < ZERO)
                                       ? (mediumLayerBoundary(currentPhotonLayer))
                                       : (mediumLayerBoundary(currentPhotonLayer) + (float)MEDIUM_LAYER_THICKNESS);

            // track this thing to the next scattering point
            float sca_step_left = -logf(RNG_CALL_UNIFORM_OC);

            float currentScaLen = getScatteringLength(currentPhotonLayer, photonDirAndWlen.w);
            float currentAbsLen = getAbsorptionLength(currentPhotonLayer, photonDirAndWlen.w);

            float ais = (photon_dz * sca_step_left - ((mediumBoundary - effective_z)) / currentScaLen) *
                        (ONE / (float)MEDIUM_LAYER_THICKNESS);
            float aia = (photon_dz * abs_lens_left - ((mediumBoundary - effective_z)) / currentAbsLen) *
                        (ONE / (float)MEDIUM_LAYER_THICKNESS);

            // propagate through layers
            int j = currentPhotonLayer;
            if (photon_dz < 0) {
                for (; (j > 0) && (ais < ZERO) && (aia < ZERO);
                     mediumBoundary -= (float)MEDIUM_LAYER_THICKNESS,
                     currentScaLen = getScatteringLength(j, photonDirAndWlen.w),
                     currentAbsLen = getAbsorptionLength(j, photonDirAndWlen.w), ais += 1.f / (currentScaLen),
                     aia += 1.f / (currentAbsLen))
                    --j;
            } else {
                for (; (j < MEDIUM_LAYERS - 1) && (ais > ZERO) && (aia > ZERO);
                     mediumBoundary += (float)MEDIUM_LAYER_THICKNESS,
                     currentScaLen = getScatteringLength(j, photonDirAndWlen.w),
                     currentAbsLen = getAbsorptionLength(j, photonDirAndWlen.w), ais -= 1.f / (currentScaLen),
                     aia -= 1.f / (currentAbsLen))
                    ++j;
            }

            float distanceToAbsorption;
            if ((currentPhotonLayer == j) || ((my_fabs(photon_dz)) < EPSILON)) {
                distancePropagated = sca_step_left * currentScaLen;
                distanceToAbsorption = abs_lens_left * currentAbsLen;
            } else {
                const float recip_photon_dz = 1.f / (photon_dz);
                distancePropagated =
                    (ais * ((float)MEDIUM_LAYER_THICKNESS) * currentScaLen + mediumBoundary - effective_z) *
                    recip_photon_dz;
                distanceToAbsorption =
                    (aia * ((float)MEDIUM_LAYER_THICKNESS) * currentAbsLen + mediumBoundary - effective_z) *
                    recip_photon_dz;
            }

            // get overburden for distance
            if (distanceToAbsorption < distancePropagated) {
                distancePropagated = distanceToAbsorption;
                abs_lens_left = ZERO;
            } else {
                abs_lens_left = (distanceToAbsorption - distancePropagated) / currentAbsLen;
            }

            // hoist the correction factor back out of the absorption length
            abs_lens_left = (abs_lens_left) / abs_len_correction_factor;
        }

        // the photon is now either being absorbed or scattered.
        // Check for collisions in its way
        bool collided = checkForCollision(
            photonPosAndTime, photonDirAndWlen, getWavelengthBias_dataShared, inv_groupvel, photonTotalPathLength,
            photonNumScatters, abs_lens_initial - abs_lens_left, photonStartPosAndTime, photonStartDirAndWlen, step,
            distancePropagated, hitIndex, maxHitIndex, outputPhotons, geoLayerToOMNumIndexPerStringSetLocal);

        if (collided) {
            // get rid of the photon if we detected it
            abs_lens_left = ZERO;
        }

        // update the track to its next position
        photonPosAndTime.x += photonDirAndWlen.x * distancePropagated;
        photonPosAndTime.y += photonDirAndWlen.y * distancePropagated;
        photonPosAndTime.z += photonDirAndWlen.z * distancePropagated;
        photonPosAndTime.w += inv_groupvel * distancePropagated;
        photonTotalPathLength += distancePropagated;

        // absorb or scatter the photon
        if (abs_lens_left < EPSILON) {
            // photon was absorbed.
            // a new one will be generated at the begin of the loop.
            --photonsLeftToPropagate;
        } else {  // photon was NOT absorbed. scatter it and re-start the loop
            // optional direction transformation (for ice anisotropy)
            transformDirectionPreScatter(photonDirAndWlen);

            // choose a scattering angle
            const float cosScatAngle = makeScatteringCosAngle(RNG_ARGS_TO_CALL);
            const float sinScatAngle = sqrt(ONE - sqr(cosScatAngle));

            // change the current direction by that angle
            scatterDirectionByAngle(cosScatAngle, sinScatAngle, photonDirAndWlen, RNG_CALL_UNIFORM_CO);

            // optional direction transformation (for ice anisotropy)
            transformDirectionPostScatter(photonDirAndWlen);

            ++photonNumScatters;
        }
    }  // end while

    // upload MWC RNG state
    MWC_RNG_x[i] = real_rnd_x;
    MWC_RNG_a[i] = real_rnd_a;
}
