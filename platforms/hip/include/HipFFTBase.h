#ifndef __OPENMM_HIPFFTBASE_H__
#define __OPENMM_HIPFFTBASE_H__

/* -------------------------------------------------------------------------- *
 *                                   OpenMM                                   *
 * -------------------------------------------------------------------------- *
 * This is part of the OpenMM molecular simulation toolkit originating from   *
 * Simbios, the NIH National Center for Physics-Based Simulation of           *
 * Biological Structures at Stanford, funded under the NIH Roadmap for        *
 * Medical Research, grant U54 GM072970. See https://simtk.org.               *
 *                                                                            *
 * Portions copyright (c) 2009-2015 Stanford University and the Authors.      *
 * Portions copyright (C) 2021 Advanced Micro Devices, Inc. All Rights        *
 * Reserved.                                                                  *
 * Authors:                                                                   *
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

#include "HipArray.h"

namespace OpenMM {

/**
 * This class performs three dimensional Fast Fourier Transforms.
 * <p>
 * Note that this class performs an unnormalized transform.  That means that if you perform
 * a forward transform followed immediately by an inverse transform, the effect is to
 * multiply every value of the original data set by the total number of data points.
 */

class OPENMM_EXPORT_COMMON HipFFTBase {
public:
    /**
     * Create an HipFFTBase object for performing transforms of a particular size.
     * <p>
     * The transform cannot be done in-place: the input and output
     * arrays must be different.  Also, the input array is used as workspace, so its contents
     * are destroyed.  This also means that both arrays must be large enough to hold complex values,
     * even when performing a real-to-complex transform.
     * <p>
     * When performing a real-to-complex transform, the output data is of size xsize*ysize*(zsize/2+1)
     * and contains only the non-redundant elements.
     *
     * @param context the context in which to perform calculations
     * @param xsize   the first dimension of the data sets on which FFTs will be performed
     * @param ysize   the second dimension of the data sets on which FFTs will be performed
     * @param zsize   the third dimension of the data sets on which FFTs will be performed
     * @param realToComplex  if true, a real-to-complex transform will be done.  Otherwise, it is complex-to-complex.
     * @param stream  HIP stream
     * @param in      the data to transform, ordered such that in[x*ysize*zsize + y*zsize + z] contains element (x, y, z)
     * @param out     on exit, this contains the transformed data
     */
    HipFFTBase(HipContext& context, int xsize, int ysize, int zsize, bool realToComplex, hipStream_t stream, HipArray& in, HipArray& out)
        : context(context), stream(stream), in(in), out(out) { };
    virtual ~HipFFTBase() = 0;
    /**
     * Perform a Fourier transform.
     *
     * @param forward  true to perform a forward transform, false to perform an inverse transform
     */
    virtual void execFFT(bool forward = true) = 0;
protected:
    hipStream_t stream;
    HipContext& context;
    HipArray& in;
    HipArray& out;
};

} // namespace OpenMM

#endif // __OPENMM_HIPFFTBASE_H__
