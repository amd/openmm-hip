#!/bin/bash
set -ex

# Existence tests
test -f $PREFIX/lib/plugins/libOpenMMHIP$SHLIB_EXT
test -f $PREFIX/lib/plugins/libOpenMMHipCompiler$SHLIB_EXT
test -f $PREFIX/lib/plugins/libOpenMMAmoebaHIP$SHLIB_EXT
test -f $PREFIX/lib/plugins/libOpenMMDrudeHIP$SHLIB_EXT
test -f $PREFIX/lib/plugins/libOpenMMRPMDHIP$SHLIB_EXT

# Debug silent errors in plugin loading
python -c "import openmm as mm; print('---Loaded---', *mm.pluginLoadedLibNames, '---Failed---', *mm.Platform.getPluginLoadFailures(), sep='\n')"

# Check the HIP platform existence
python -c "from openmm import Platform as P; P.getPlatformByName('HIP')"

# Run only outside conda-forge docker (CI or build-locally.py), i.e. with `conda build`,
# assuming there will be a GPU there
if [[ -z "$CONFIG" ]]; then
    # Check all platforms
    python -m openmm.testInstallation

    # Run a small MD
    cd ${PREFIX}/share/openmm/examples
    python benchmark.py --test=rf --seconds=10 --platform=Reference
    python benchmark.py --test=rf --seconds=10 --platform=CPU
    python benchmark.py --test=rf --seconds=10 --platform=HIP

    if [[ $with_test_suite == "true" ]]; then
        cd $PREFIX/share/openmm/tests
        bash test_openmm_hip.sh
    fi
fi
