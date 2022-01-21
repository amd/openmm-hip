#---------------------------------------------------
# OpenMM HIP Platform
#----------------------------------------------------

CMAKE_MINIMUM_REQUIRED(VERSION 3.17)

PROJECT(OpenMMHIPPlugin)

INCLUDE(Dart)
MARK_AS_ADVANCED(DART_ROOT)

ENABLE_TESTING()

SET(X86 ON)

# We need to know where OpenMM is installed so we can access the headers and libraries.
SET(OPENMM_DIR "/usr/local/openmm" CACHE PATH "Where OpenMM is installed")

# We need to know where OpenMM source code is located so we can access required files.
SET(OPENMM_SOURCE_DIR "${CMAKE_SOURCE_DIR}/../openmm" CACHE PATH "Where OpenMM source code is located")

INCLUDE_DIRECTORIES(${OPENMM_DIR}/include)
INCLUDE_DIRECTORIES(${OPENMM_DIR}/include/openmm/reference)
LINK_DIRECTORIES("${OPENMM_DIR}/lib" "${OPENMM_DIR}/lib/plugins")

# Specify the C++ version we are building for.
SET(CMAKE_CXX_STANDARD 11)

IF(MSVC)
    SET(EXTRA_COMPILE_FLAGS)
    # Use warning level 2, not whatever warning level CMake picked.
    STRING(REGEX REPLACE "/W[0-4]" "/W2" CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")
    # Explicitly suppress warnings 4305 and 4244.
    SET(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /wd4305 /wd4244")
ELSEIF(X86)
    SET(EXTRA_COMPILE_FLAGS "-msse2")
ELSE()
    SET(EXTRA_COMPILE_FLAGS)
ENDIF()

# Make sure that Lepton::CompiledExpression class has the same structure as in the main library
IF(X86 AND NOT (WIN32 AND OPENMM_BUILD_STATIC_LIB))
    INCLUDE_DIRECTORIES(BEFORE ${OPENMM_SOURCE_DIR}/libraries/asmjit)
    SET(EXTRA_COMPILE_FLAGS "${EXTRA_COMPILE_FLAGS} -DLEPTON_USE_JIT")
ENDIF()

IF(UNIX AND NOT CMAKE_BUILD_TYPE)
    SET(CMAKE_BUILD_TYPE Release CACHE STRING "Debug or Release build" FORCE)
ENDIF (UNIX AND NOT CMAKE_BUILD_TYPE)

IF (NOT CMAKE_CXX_FLAGS_DEBUG)
    SET(CMAKE_CXX_FLAGS_DEBUG "-g" CACHE STRING "To use when CMAKE_BUILD_TYPE=Debug" FORCE)
ENDIF (NOT CMAKE_CXX_FLAGS_DEBUG)

IF (NOT CMAKE_CXX_FLAGS_RELEASE)
    SET(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG" CACHE STRING "To use when CMAKE_BUILD_TYPE=Release" FORCE)
ENDIF (NOT CMAKE_CXX_FLAGS_RELEASE)

# Select where to install
IF(${CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT})
    IF(WIN32)
        SET(CMAKE_INSTALL_PREFIX "$ENV{ProgramFiles}/OpenMM" CACHE PATH "Where to install the plugin" FORCE)
    ELSE(WIN32)
        SET(CMAKE_INSTALL_PREFIX "/usr/local/openmm" CACHE PATH "Where to install the plugin" FORCE)
    ENDIF(WIN32)
ENDIF(${CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT})

# What type of libraries to build
SET(OPENMM_BUILD_SHARED_LIB ON CACHE BOOL "Whether to build shared OpenMM libraries")
SET(OPENMM_BUILD_STATIC_LIB OFF CACHE BOOL "Whether to build static OpenMM libraries")

# We have custom cmake modules for FindMMHIP
SET(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_SOURCE_DIR}/cmake_modules")

SET(OPENMM_LIBRARY_NAME OpenMM)

IF(NOT EXECUTABLE_OUTPUT_PATH)
  SET(EXECUTABLE_OUTPUT_PATH ${PROJECT_BINARY_DIR}
      CACHE INTERNAL "Single output directory for building all executables.")
ENDIF(NOT EXECUTABLE_OUTPUT_PATH)

# Include OpenMM utiliity libraries
SET(OPENMM_LIB_SUBDIRS libraries/jama libraries/quern libraries/hilbert libraries/csha1 libraries/lbfgs)
FOREACH(subdir ${OPENMM_LIB_SUBDIRS})
    INCLUDE_DIRECTORIES(BEFORE ${OPENMM_SOURCE_DIR}/${subdir}/include)
ENDFOREACH(subdir)

LIST(APPEND CMAKE_PREFIX_PATH $ENV{ROCM_PATH} /opt/rocm)

FIND_PACKAGE(HIP CONFIG REQUIRED)
FIND_PACKAGE(HIPFFT CONFIG REQUIRED)

IF(${HIP_COMPILER} STREQUAL "clang")
    MESSAGE(STATUS "Using HIP-Clang compiler")
ELSE()
    MESSAGE(FATAL_ERROR "HIP compiler ${HIP_COMPILER} not recognized!")
ENDIF()

ADD_SUBDIRECTORY(platforms/hip)

# Amoeba plugin

SET(OPENMM_BUILD_AMOEBA_PLUGIN ON CACHE BOOL "Build Amoeba plugin")
IF(OPENMM_BUILD_AMOEBA_PLUGIN)
    ADD_SUBDIRECTORY(plugins/amoeba/platforms/hip)
ENDIF(OPENMM_BUILD_AMOEBA_PLUGIN)

# RPMD plugin

SET(OPENMM_BUILD_RPMD_PLUGIN ON CACHE BOOL "Build RPMD plugin")
IF(OPENMM_BUILD_RPMD_PLUGIN)
   ADD_SUBDIRECTORY(plugins/rpmd/platforms/hip)
ENDIF(OPENMM_BUILD_RPMD_PLUGIN)

# Drude plugin

SET(OPENMM_BUILD_DRUDE_PLUGIN ON CACHE BOOL "Build Drude plugin")
IF(OPENMM_BUILD_DRUDE_PLUGIN)
   ADD_SUBDIRECTORY(plugins/drude/platforms/hip)
ENDIF(OPENMM_BUILD_DRUDE_PLUGIN)

# HIP compiler plugin

SET(OPENMM_BUILD_HIP_COMPILER_PLUGIN ON CACHE BOOL "Build HIP runtime compiler plugin")
IF(OPENMM_BUILD_HIP_COMPILER_PLUGIN)
   ADD_SUBDIRECTORY(plugins/hipcompiler)
ENDIF(OPENMM_BUILD_HIP_COMPILER_PLUGIN)
