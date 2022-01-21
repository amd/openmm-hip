OpenMM HIP Plugin
=====================

This plugin adds HIP platform that allows to run [OpenMM](https://openmm.org) on CDNA and RDNA
AMD GPUs on [AMD ROCm™ open software platform](https://rocmdocs.amd.com).

Installing
----------

The plugin can be installed using Conda:

```sh
conda create -n openmm-env -c streamhpc -c conda-forge openmm-hip
```

This command creates a new environment and install the plugin.

Verify your installation (HIP must be one of available plaforms):

```sh
python -m openmm.testInstallation
```

Run benchmarks (see more options `python benchmark.py --help`):

```sh
cd $CONDA_PREFIX/share/openmm/examples/
python benchmark.py --platform=HIP
```

To remove OpenMM and the HIP plugin, run:

```sh
conda uninstall openmm-hip openmm
```

Building
--------

This project uses [CMake](http://www.cmake.org) for its build system.

The plugin requires source code of OpenMM, it can be downloaded as an archive
[here](https://github.com/openmm/openmm/releases) or as a Git repository:

```sh
git clone https://github.com/openmm/openmm.git
```

<!-- TODO Update when HIP-related changes are merged into the main repository -->
Currently the main repository of OpenMM does not include all changes required for the HIP platform
so [this branch](https://github.com/StreamHPC/openmm/tree/develop_stream_hip_split) must be used:

```sh
git clone https://github.com/StreamHPC/openmm.git -b develop_stream_hip_split
```

To build the plugin, follow these steps:

1. Create a directory in which to build the plugin.

2. Run the CMake GUI or ccmake, specifying your new directory as the build directory and the top
level directory of this project as the source directory.

3. Press "Configure".

4. Set OPENMM_DIR to point to the directory where OpenMM is installed.  This is needed to locate
the OpenMM header files and libraries.

5. Set OPENMM_SOURCE_DIR to point to the directory where OpenMM source code is located.

6. Set CMAKE_INSTALL_PREFIX to the directory where the plugin should be installed.  Usually,
this will be the same as OPENMM_DIR, so the plugin will be added to your OpenMM installation.

7. Press "Configure" again if necessary, then press "Generate".

8. Use the build system you selected to build and install the plugin.  For example, if you
selected Unix Makefiles, type `make install`.

Here are all commands required for building and installing OpenMM with HIP support from the latest
source code:

```sh
mkdir build build-hip install

git clone https://github.com/StreamHPC/openmm.git -b develop_stream_hip_split
cd build
cmake ../openmm/ -D CMAKE_INSTALL_PREFIX=../install -D OPENMM_PYTHON_USER_INSTALL=ON
make
make install
make PythonInstall
cd ..

git clone https://github.com/StreamHPC/openmm-hip.git
cd build-hip
cmake ../openmm-hip/ -D OPENMM_DIR=../install -D OPENMM_SOURCE_DIR=../openmm -D CMAKE_INSTALL_PREFIX=../install
make
make install
```

If you do not want to install OpenMM Python libraries into the user site-packages directory
remove `-D OPENMM_PYTHON_USER_INSTALL=ON`.

Use `ROCM_PATH` environment variable if ROCm is not installed in the default directory (/opt/rocm).

Testing
-------

To run all the test cases build the "test" target, for example by typing `make test`.
