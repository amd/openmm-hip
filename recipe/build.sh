#!/bin/bash

set -ex

# Install ROCm if inside conda-forge docker (CI or build-locally.py)
if [[ ! -z "$CONFIG" ]]; then
    # EPEL repository is required for perl-File-BaseDir and perl-URI-Encode
    sudo yum -y install epel-release
    sudo yum -y repolist
    # Install all required ROCm packages
    sudo yum -y install https://repo.radeon.com/amdgpu-install/21.50.2/rhel/7.9/amdgpu-install-21.50.2.50002-1.el7.noarch.rpm
    sudo yum -y install rocm-device-libs hip-devel hip-runtime-amd rocfft-devel hipfft-devel
fi

CMAKE_FLAGS="${CMAKE_ARGS} -DOPENMM_DIR=${PREFIX} -DCMAKE_INSTALL_PREFIX=${PREFIX}"
if [[ "$with_test_suite" == "true" ]]; then
    CMAKE_FLAGS+=" -DOPENMM_BUILD_HIP_TESTS=ON"
else
    CMAKE_FLAGS+=" -DOPENMM_BUILD_HIP_TESTS=OFF"
fi

# Do not check references to libamdhip64 dependencies for tests, conda-build's ld can not find them
# because it does not use system paths (/etc/ld.so.conf.d/rocm.conf and amdgpu.conf).
# We run the tests later so no linkage errors will be missed.
CMAKE_FLAGS+=" -DCMAKE_EXE_LINKER_FLAGS=-Wl,--allow-shlib-undefined"

# HIP config uses find_path() and find_library() but conda-build sets
# CMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY making it impossible to find headers and libraries
# in ROCm directories.
CMAKE_FLAGS+=" -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH"

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
