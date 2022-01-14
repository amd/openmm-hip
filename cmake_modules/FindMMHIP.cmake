# - Find AMD's HIP library
#   Piggybacks on existing HIP cmake support to simplify
#   build support for AMD GPUs.
#
#   Specifically this is needed because the HIP Cmake modules currently assume
#   you are using the hipcc "compiler" for compilation of your whole program
#
#   Since OpenMM uses a different host compiler, and uses hipcc to generate
#   JIT'd code objects, it is more convenient to simply determine the libraries /
#   include paths we need this way
#
#   The following important variables are defined by the call to FindHIP.cmake
#   (along with the HIP / rocFFT modules):
#
#   HIP_FOUND                - Whether we found a HIP installation through the system
#                              cmake modules or not
#   HIP_HIPCONFIG_EXECUTABLE - path to hipconfig
#   HIP_INCLUDE_DIRS         - include directories for HIP runtime
#   ROCFFT_INCLUDE_DIRS      - include directories for rocFFT
#   HIP_COMPILER             - HIP-clang
#
#   In addition to what is defined by FindHIP.cmake, this module:
#
#   Defines:
#       MMHIP_INCLUDE_DIRS   - The full list of paths to include when building the
#                              HIP platform
#       MMHIP_LINK_DIRS      - The full list of library paths to search when
#                              building the HIP platform
#       MMHIP_LIBS           - The full list of HIP librarys to link against
#       HIPCXXFLAGS          - List of compile time flags to pass to the host
#                              compiler when compiling HIP API code
#       HIP_ROOT_PATH        - The root directory of the HIP installation
#
#   Modifies:
#       CMAKE_MODULE_PATH    - to point to hipfft / HIP cmake modules


FIND_PACKAGE(HIP CONFIG)

IF(${HIP_COMPILER} STREQUAL "clang")
    MESSAGE(STATUS "Using HIP-Clang compiler")
ELSE()
    MESSAGE(FATAL_ERROR "HIP compiler ${HIP_COMPILER} not recognized!")
ENDIF()
LIST(APPEND CMAKE_MODULE_PATH "${HIP_ROOT_DIR}/lib/cmake/hip")
LIST(APPEND CMAKE_MODULE_PATH "${HIP_ROOT_DIR}/../hipfft/lib/cmake/hipfft")

FIND_PACKAGE(HIP REQUIRED)
FIND_PACKAGE(ROCFFT REQUIRED)
EXECUTE_PROCESS(COMMAND ${HIP_HIPCONFIG_EXECUTABLE} -C OUTPUT_VARIABLE HIPCXXFLAGS)
EXECUTE_PROCESS(COMMAND ${HIP_HIPCONFIG_EXECUTABLE} -p OUTPUT_VARIABLE HIP_ROOT_PATH)

# set HIP include dirs
# this includes HIP, hipFFT, and the roctracer includes
SET(MMHIP_INCLUDE_DIRS ${HIP_ROOT_PATH}/../hipfft/include ${HIP_INCLUDE_DIRS} ${HIP_ROOT_PATH}/../hsa/include/hsa ${HIP_ROOT_PATH}/../roctracer/include)
# set HIP link directories
# this includes HIP, hipFFT, and the roctracer
SET(MMHIP_LINK_DIRS ${HIP_ROOT_PATH}/lib ${HIP_ROOT_PATH}/../hipfft/lib ${HIP_ROOT_PATH}/../hsa/lib ${HIP_ROOT_PATH}/../roctracer/lib)
# set HIP libraries
# this includes HIP, hipFFT, and the roctracer
SET(MMHIP_LIBS amdhip64 hipfft roctracer64)

find_package_handle_standard_args(MMHIP DEFAULT_MSG HIP_ROOT_PATH)
