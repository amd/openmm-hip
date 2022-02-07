/* -------------------------------------------------------------------------- *
 *                                   OpenMM                                   *
 * -------------------------------------------------------------------------- *
 * This is part of the OpenMM molecular simulation toolkit originating from   *
 * Simbios, the NIH National Center for Physics-Based Simulation of           *
 * Biological Structures at Stanford, funded under the NIH Roadmap for        *
 * Medical Research, grant U54 GM072970. See https://simtk.org.               *
 *                                                                            *
 * Portions copyright (c) 2015-2021 Stanford University and the Authors.      *
 * Portions copyright (c) 2021 Advanced Micro Devices, Inc. All Rights        *
 * Reserved.                                                                  *
 * Authors: Peter Eastman                                                     *
 * Contributors:                                                              *
 *                                                                            *
 * Permission is hereby granted, free of charge, to any person obtaining a    *
 * copy of this software and associated documentation files (the "Software"), *
 * to deal in the Software without restriction, including without limitation  *
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,   *
 * and/or sell copies of the Software, and to permit persons to whom the      *
 * Software is furnished to do so, subject to the following conditions:       *
 *                                                                            *
 * The above copyright notice and this permission notice shall be included in *
 * all copies or substantial portions of the Software.                        *
 *                                                                            *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR *
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   *
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    *
 * THE AUTHORS, CONTRIBUTORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,    *
 * DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR      *
 * OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE  *
 * USE OR OTHER DEALINGS IN THE SOFTWARE.                                     *
 * -------------------------------------------------------------------------- */

#include "HipCompilerKernels.h"
#include "openmm/OpenMMException.h"
#include <sstream>
#include <hip/hiprtc.h>

using namespace OpenMM;
using namespace std;

#define CHECK_RESULT(result, prefix) \
    if (result != HIPRTC_SUCCESS) { \
        stringstream m; \
        m<<prefix<<": "<<getErrorString(result)<<" ("<<result<<")"<<" at "<<__FILE__<<":"<<__LINE__; \
        throw OpenMMException(m.str());\
    }

static string getErrorString(hiprtcResult result) {
    return hiprtcGetErrorString(result);
}

HipRuntimeCompilerKernel::HipRuntimeCompilerKernel(const std::string& name, const Platform& platform) : HipCompilerKernel(name, platform) {
}

vector<char> HipRuntimeCompilerKernel::createModule(const string& source, const string& flags, HipContext& cu) {
    // Split the command line flags into an array of options.
    
    stringstream flagsStream(flags);
    string flag;
    vector<string> splitFlags;
    while (flagsStream >> flag)
        splitFlags.push_back(flag);
    int numOptions = splitFlags.size();
    vector<const char*> options(numOptions);
    for (int i = 0; i < numOptions; i++)
        options[i] = &splitFlags[i][0];
    
    // Compile the program to HSACO.

    hiprtcProgram program;
    CHECK_RESULT(hiprtcCreateProgram(&program, source.c_str(), NULL, 0, NULL, NULL), "Error creating program");
    try {
        hiprtcResult result = hiprtcCompileProgram(program, options.size(), &options[0]);
        if (result != HIPRTC_SUCCESS) {
            size_t logSize;
            hiprtcGetProgramLogSize(program, &logSize);
            vector<char> log(logSize);
            hiprtcGetProgramLog(program, &log[0]);
            throw OpenMMException("Error compiling program: "+string(&log[0]));
        }
        size_t codeSize;
        hiprtcGetCodeSize(program, &codeSize);
        vector<char> code(codeSize);
        hiprtcGetCode(program, &code[0]);
        hiprtcDestroyProgram(&program);
        return code;
    }
    catch (...) {
        hiprtcDestroyProgram(&program);
        throw;
    }
}
