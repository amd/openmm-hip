/**
 * This file contains HIP definitions for the macros and functions needed for the
 * common compute framework.
 */

#define KERNEL extern "C" __global__
#define DEVICE __device__
#define LOCAL __shared__
#define LOCAL_ARG
#define GLOBAL
#define RESTRICT __restrict__
#define LOCAL_ID threadIdx.x
#define LOCAL_SIZE blockDim.x
#define GLOBAL_ID (blockIdx.x*blockDim.x+threadIdx.x)
#define GLOBAL_SIZE (blockDim.x*gridDim.x)
#define GROUP_ID blockIdx.x
#define NUM_GROUPS gridDim.x
#define SYNC_THREADS __syncthreads();
#define MEM_FENCE __threadfence_block();
#define ATOMIC_ADD(dest, value) atomicAdd(dest, value)

typedef long long mm_long;
typedef unsigned long long mm_ulong;

#define SUPPORTS_64_BIT_ATOMICS 1
#define SUPPORTS_DOUBLE_PRECISION 1

#define LAUNCH_BOUNDS_EXACT(WORK_GROUP_SIZE, WAVES_PER_EU) \
    __attribute__((amdgpu_flat_work_group_size(WORK_GROUP_SIZE, WORK_GROUP_SIZE), amdgpu_waves_per_eu(WAVES_PER_EU, WAVES_PER_EU)))

#ifdef USE_DOUBLE_PRECISION

__device__ inline long long realToFixedPoint(double x) {
    return static_cast<long long>(x * 0x100000000);
}

#else

__device__ inline long long realToFixedPoint(float x) {
    // More effective way to do static_cast<long long>(x * 0x100000000)
    int hi = __float2int_rz(x);
    float rem = (x - __float2int_rz(x)) * 0x100000000;
    bool isRemNeg = rem < -0.5f;
    int lo = __float2uint_rn(fabsf(rem));
    return static_cast<long long>(
        (static_cast<unsigned long long>(static_cast<unsigned int>(isRemNeg ? hi - 1 : hi)) << 32) |
        static_cast<unsigned long long>(static_cast<unsigned int>(isRemNeg ? -lo : +lo)));
}

#endif
