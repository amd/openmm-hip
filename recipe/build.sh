#!/bin/bash

set -ex

CMAKE_FLAGS="${CMAKE_ARGS} -DOPENMM_DIR=${PREFIX} -DCMAKE_INSTALL_PREFIX=${PREFIX}"
if [[ "$with_test_suite" == "true" ]]; then
    CMAKE_FLAGS+=" -DOPENMM_BUILD_HIP_TESTS=ON"
else
    CMAKE_FLAGS+=" -DOPENMM_BUILD_HIP_TESTS=OFF"
fi

# Do not check references to libamdhip64 dependencies for tests, conda-build's ld cn not find them
# because it does not use system paths (/etc/ld.so.conf.d/rocm.conf and amdgpu.conf).
# We run the tests later so no linkage errors will be missed.
CMAKE_FLAGS+=" -DCMAKE_EXE_LINKER_FLAGS=-Wl,--allow-shlib-undefined"

# HIP config uses find_path() but conda-build sets CMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY making
# if impossible to find headers in ROCm directories.
CMAKE_FLAGS+=" -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH"

# Build in subdirectory and install.
mkdir -p build
cd build
cmake ${CMAKE_FLAGS} ${SRC_DIR}/openmm-hip
make -j$CPU_COUNT
make -j$CPU_COUNT install

# Fix some overlinking warnings/errors
for lib in ${PREFIX}/lib/plugins/libOpenMM*HIP*${SHLIB_EXT}; do
    ln -s $lib ${PREFIX}/lib/$(basename $lib) || true
done

if [[ "$with_test_suite" == "true" ]]; then
    mkdir -p ${PREFIX}/share/openmm/tests/
    find . -name "TestHip*" -executable -type f -exec cp "{}" $PREFIX/share/openmm/tests/ \;
    cp $RECIPE_DIR/test_openmm_hip.sh $PREFIX/share/openmm/tests/
    chmod +x $PREFIX/share/openmm/tests/test_openmm_hip.sh
    ls -al ${PREFIX}/share/openmm/tests/
fi
