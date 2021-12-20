/**
 * This file contains the device function for using DPP
 */

template<class T, int dpp_ctrl, int row_mask = 0xf, int bank_mask = 0xf, bool bound_ctrl = true>
static __inline__ __device__
T warpMoveDpp(const T& input) {
    static_assert(sizeof(T) % sizeof(int) == 0, "incorrect type size");
    constexpr int words_no = sizeof(T) / sizeof(int);

    T output;
    #pragma unroll
    for(int i = 0; i < words_no; i++) {
        int word;
        __builtin_memcpy(&word, reinterpret_cast<const char*>(&input) + i * sizeof(int), sizeof(int));
        word = __builtin_amdgcn_update_dpp(
          0, word,
          dpp_ctrl, row_mask, bank_mask, bound_ctrl
        );
        __builtin_memcpy(reinterpret_cast<char*>(&output) + i * sizeof(int), &word, sizeof(int));
    }

    return output;
}

template<class T>
static __inline__ __device__
T warpShuffle(const T& input, const int src_lane) {
    static_assert(sizeof(T) % sizeof(int) == 0, "incorrect type size");
    constexpr int words_no = sizeof(T) / sizeof(int);


    T output;
    #pragma unroll
    for(int i = 0; i < words_no; i++) {
        int word;
        __builtin_memcpy(&word, reinterpret_cast<const char*>(&input) + i * sizeof(int), sizeof(int));
        word = SHFL(word, src_lane);
        __builtin_memcpy(reinterpret_cast<char*>(&output) + i * sizeof(int), &word, sizeof(int));
    }

    return output;
}

// HIP-TODO: See comments in HipContext::createModule. The workaround does not help because hipRTC
// does not pass -mllvm -amdgpu-dpp-combine=false to the compiler.
// Remove when the compiler issue is fixed.
#if defined(__HIPCC_RTC__)
#define USE_DPP 0
#else
#define USE_DPP 1
#endif

template<int Subwarp, class T>
static __inline__ __device__
typename std::enable_if<!(USE_DPP && Subwarp == 64), T>::type
warpRotateLeft(const T& input) {
  int i = ((threadIdx.x + 1) & (Subwarp - 1)) | (threadIdx.x & ~(Subwarp - 1));
  return warpShuffle(input, i);
}

template<int Subwarp, class T>
static __inline__ __device__
typename std::enable_if<(USE_DPP && Subwarp == 64), T>::type
warpRotateLeft(const T& input) {
    // Wavefront rotate left by 1 thread
    // RDNA does not support it, shuffle-based implementation is used instead
    return warpMoveDpp<T, 0x134>(input);
}
