/* -------------------------------------------------------------------------- *
 *                           OpenMMHipCompiler                               *
 * -------------------------------------------------------------------------- *
 * This is part of the OpenMM molecular simulation toolkit originating from   *
 * Simbios, the NIH National Center for Physics-Based Simulation of           *
 * Biological Structures at Stanford, funded under the NIH Roadmap for        *
 * Medical Research, grant U54 GM072970. See https://simtk.org.               *
 *                                                                            *
 * Portions copyright (c) 2015-2016 Stanford University and the Authors.      *
 * Portions copyright (c) 2021 Advanced Micro Devices, Inc. All Rights        *
 * Reserved.                                                                  *
 * Authors: Peter Eastman                                                     *
 * Contributors:                                                              *
 *                                                                            *
 * This program is free software: you can redistribute it and/or modify       *
 * it under the terms of the GNU Lesser General Public License as published   *
 * by the Free Software Foundation, either version 3 of the License, or       *
 * (at your option) any later version.                                        *
 *                                                                            *
 * This program is distributed in the hope that it will be useful,            *
 * but WITHOUT ANY WARRANTY; without even the implied warranty of             *
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              *
 * GNU Lesser General Public License for more details.                        *
 *                                                                            *
 * You should have received a copy of the GNU Lesser General Public License   *
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.      *
 * -------------------------------------------------------------------------- */

#include "HipCompilerKernelFactory.h"
#include "HipCompilerKernels.h"
#include "internal/windowsExportHipCompiler.h"
#include "openmm/internal/ContextImpl.h"
#include "openmm/OpenMMException.h"

using namespace OpenMM;

#ifdef OPENMM_HIPCOMPILER_BUILDING_STATIC_LIBRARY
static void registerKernelFactories() {
#else
extern "C" OPENMM_EXPORT_HIPCOMPILER void registerKernelFactories() {
#endif
    try {
        Platform& platform = Platform::getPlatformByName("HIP");
        HipCompilerKernelFactory* factory = new HipCompilerKernelFactory();
        platform.registerKernelFactory(HipCompilerKernel::Name(), factory);
    }
    catch (std::exception ex) {
        // Ignore
    }
}

#ifdef OPENMM_HIPCOMPILER_BUILDING_STATIC_LIBRARY
extern "C" void registerHipCompilerKernelFactories() {
    registerKernelFactories();
}
#else
extern "C" OPENMM_EXPORT_HIPCOMPILER void registerHipCompilerKernelFactories() {
    registerKernelFactories();
}
extern "C" OPENMM_EXPORT_HIPCOMPILER void registerPlatforms() {
}
#endif

KernelImpl* HipCompilerKernelFactory::createKernelImpl(std::string name, const Platform& platform, ContextImpl& context) const {
    if (name == HipCompilerKernel::Name())
        return new HipRuntimeCompilerKernel(name, platform);
    throw OpenMMException((std::string("Tried to create kernel with illegal kernel name '")+name+"'").c_str());
}
