/**
 * This file contains the device function for using DPP
 */

template<class T, int dpp_ctrl, int row_mask = 0xf, int bank_mask = 0xf, bool bound_ctrl = true>
static __inline__ __device__
typename std::enable_if<std::is_trivially_copyable<T>::value && (sizeof(T) % sizeof(int) == 0), T>::type
warpMoveDpp(const T& input) {
    constexpr int words_no = (sizeof(T) + sizeof(int) - 1) / sizeof(int);

    struct V { int words[words_no]; };
    V a = __builtin_bit_cast(V, input);

    #pragma unroll
    for (int i = 0; i < words_no; i++) {
        a.words[i] = __builtin_amdgcn_update_dpp(
          0, a.words[i],
          dpp_ctrl, row_mask, bank_mask, bound_ctrl
        );
    }

    return __builtin_bit_cast(T, a);
}

template<class T, int dpp_ctrl, int row_mask = 0xf, int bank_mask = 0xf, bool bound_ctrl = true>
static __inline__ __device__
typename std::enable_if<!(std::is_trivially_copyable<T>::value && (sizeof(T) % sizeof(int) == 0)), T>::type
warpMoveDpp(const T& input) {
    constexpr int words_no = (sizeof(T) + sizeof(int) - 1) / sizeof(int);

    T output;
    #pragma unroll
    for(int i = 0; i < words_no; i++) {
        const size_t s = std::min(sizeof(int), sizeof(T) - i * sizeof(int));
        int word;
        __builtin_memcpy(&word, reinterpret_cast<const char*>(&input) + i * sizeof(int), s);
        word = __builtin_amdgcn_update_dpp(
          0, word,
          dpp_ctrl, row_mask, bank_mask, bound_ctrl
        );
        __builtin_memcpy(reinterpret_cast<char*>(&output) + i * sizeof(int), &word, s);
    }

    return output;
}

template<class T>
static __inline__ __device__
typename std::enable_if<std::is_trivially_copyable<T>::value && (sizeof(T) % sizeof(int) == 0), T>::type
warpShuffle(const T& input, const int src_lane) {
    constexpr int words_no = (sizeof(T) + sizeof(int) - 1) / sizeof(int);

    struct V { int words[words_no]; };
    V a = __builtin_bit_cast(V, input);

    #pragma unroll
    for (int i = 0; i < words_no; i++) {
        a.words[i] = SHFL(a.words[i], src_lane);
    }

    return __builtin_bit_cast(T, a);
}

template<class T>
static __inline__ __device__
typename std::enable_if<!(std::is_trivially_copyable<T>::value && (sizeof(T) % sizeof(int) == 0)), T>::type
warpShuffle(const T& input, const int src_lane) {
    constexpr int words_no = (sizeof(T) + sizeof(int) - 1) / sizeof(int);

    T output;
    #pragma unroll
    for(int i = 0; i < words_no; i++) {
        const size_t s = std::min(sizeof(int), sizeof(T) - i * sizeof(int));
        int word;
        __builtin_memcpy(&word, reinterpret_cast<const char*>(&input) + i * sizeof(int), s);
        word = SHFL(word, src_lane);
        __builtin_memcpy(reinterpret_cast<char*>(&output) + i * sizeof(int), &word, s);
    }

    return output;
}

template<int Subwarp, class T>
static __inline__ __device__
typename std::enable_if<!(Subwarp == warpSize), T>::type
warpRotateLeft(const T& input) {
  int i = ((threadIdx.x + 1) & (Subwarp - 1)) | (threadIdx.x & ~(Subwarp - 1));
  return warpShuffle(input, i);
}

template<int Subwarp, class T>
static __inline__ __device__
typename std::enable_if<(Subwarp == warpSize), T>::type
warpRotateLeft(const T& input) {
    // Wavefront rotate left by 1 thread
    return warpMoveDpp<T, 0x134>(input);
}
