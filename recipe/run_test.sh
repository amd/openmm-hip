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

# Check all platforms
python -m openmm.testInstallation
n_platforms=4
python -c "from openmm import Platform as P; n = P.getNumPlatforms(); assert n == $n_platforms, f'n_platforms ({n}) != $n_platforms'"
python -c "from openmm import Platform as P; P.getPlatformByName('HIP')"

# Run a small MD
cd ${PREFIX}/share/openmm/examples
python benchmark.py --test=rf --seconds=10 --platform=Reference
python benchmark.py --test=rf --seconds=10 --platform=CPU
python benchmark.py --test=rf --seconds=10 --platform=HIP

if [[ $with_test_suite == "true" ]]; then
    cd $PREFIX/share/openmm/tests
    bash test_openmm_hip.sh
fi
