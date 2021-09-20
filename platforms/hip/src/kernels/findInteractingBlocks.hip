#define GROUP_SIZE 64
#define BUFFER_SIZE 256

// type compat.
#if TILE_SIZE == 32
__device__ inline int __TILEFLAGS_FFS(unsigned int x) {
    return __ffs(x);
}
__device__ inline int __TILEFLAGS_CLZ(unsigned int x) {
    return __clz(x);
}
__device__ inline int __TILEFLAGS_POPC(unsigned int x) {
    return __popc(x);
}
#else
__device__ inline int __TILEFLAGS_FFS(unsigned long long int x) {
    return __ffsll(x);
}
__device__ inline int __TILEFLAGS_CLZ(unsigned long long int x) {
    return __clzll(x);
}
__device__ inline int __TILEFLAGS_POPC(unsigned long long int x) {
    return __popcll(x);
}
#endif

/**
 * Find a bounding box for the atoms in each block.
 */
extern "C" __global__ void findBlockBounds(int numAtoms, real4 periodicBoxSize, real4 invPeriodicBoxSize, real4 periodicBoxVecX, real4 periodicBoxVecY, real4 periodicBoxVecZ,
        const real4* __restrict__ posq, real4* __restrict__ blockCenter, real4* __restrict__ blockBoundingBox, int* __restrict__ rebuildNeighborList,
        real2* __restrict__ sortedBlocks) {
    __shared__ real4 sPos[TILE_SIZE];
    int index = blockIdx.x;
    int base = index * TILE_SIZE;

    sPos[threadIdx.x] = ((base + threadIdx.x) < numAtoms) ? posq[base + threadIdx.x] : make_real4(0, 0, 0, 0);
    __syncthreads();
    if (threadIdx.x == 0) {
        real4 pos = sPos[0];
#ifdef USE_PERIODIC
        APPLY_PERIODIC_TO_POS(pos)
#endif
        real4 minPos = pos;
        real4 maxPos = pos;
        for (int i = 1; i < TILE_SIZE; i++) {
            pos = sPos[i];
#ifdef USE_PERIODIC
            real4 center = 0.5f*(maxPos+minPos);
            APPLY_PERIODIC_TO_POS_WITH_CENTER(pos, center)
#endif
            minPos = make_real4(min(minPos.x,pos.x), min(minPos.y,pos.y), min(minPos.z,pos.z), 0);
            maxPos = make_real4(max(maxPos.x,pos.x), max(maxPos.y,pos.y), max(maxPos.z,pos.z), 0);
        }
        real4 blockSize = 0.5f*(maxPos-minPos);
        real4 center = 0.5f*(maxPos+minPos);
        center.w = 0;
        for (int i = 0; i < TILE_SIZE; i++) {
            real4 delta = sPos[i]-center;
#ifdef USE_PERIODIC
            APPLY_PERIODIC_TO_DELTA(delta)
#endif
            center.w = max(center.w, delta.x*delta.x+delta.y*delta.y+delta.z*delta.z);
        }
        center.w = SQRT(center.w);
        blockBoundingBox[index] = blockSize;
        blockCenter[index] = center;
        sortedBlocks[index] = make_real2(blockSize.x+blockSize.y+blockSize.z, index);
    }
    if (blockIdx.x == 0 && threadIdx.x == 0)
        rebuildNeighborList[0] = 0;
}


/**
 * Sort the data about bounding boxes so it can be accessed more efficiently in the next kernel.
 */
extern "C" __global__ void sortBoxData(const real2* __restrict__ sortedBlock, const real4* __restrict__ blockCenter,
        const real4* __restrict__ blockBoundingBox, real4* __restrict__ sortedBlockCenter,
        real4* __restrict__ sortedBlockBoundingBox, const real4* __restrict__ posq, const real4* __restrict__ oldPositions,
        unsigned int* __restrict__ interactionCount, int* __restrict__ rebuildNeighborList, bool forceRebuild) {
    int i = threadIdx.x+blockIdx.x*blockDim.x;
    if (i < NUM_BLOCKS) {
        int index = (int) sortedBlock[i].y;
        sortedBlockCenter[i] = blockCenter[index];
        sortedBlockBoundingBox[i] = blockBoundingBox[index];
    }

    // Also check whether any atom has moved enough so that we really need to rebuild the neighbor list.

    bool rebuild = forceRebuild;
    if (i < NUM_ATOMS) {
        real4 delta = oldPositions[i]-posq[i];
        if (delta.x*delta.x + delta.y*delta.y + delta.z*delta.z > 0.25f*PADDING*PADDING)
            rebuild = true;
    }

    if (rebuild) {
        rebuildNeighborList[0] = 1;
        interactionCount[0] = 0;
        interactionCount[1] = 0;
    }
}

/**
 * Compare the bounding boxes for each pair of atom blocks (comprised of TILE_SIZE atoms each), forming a tile. If the two
 * atom blocks are sufficiently far apart, mark them as non-interacting. There are two stages in the algorithm.
 *
 * STAGE 1:
 *
 * A coarse grained atom block against interacting atom block neighbour list is constructed.
 *
 * Each warp first loads in some block X of interest. Each thread within the warp then loads
 * in a different atom block Y. If Y has exclusions with X, then Y is not processed.  If the bounding boxes
 * of the two atom blocks are within the cutoff distance, then the two atom blocks are considered to be
 * interacting and Y is added to the buffer for X.
 *
 * STAGE 2:
 *
 * A fine grained atom block against interacting atoms neighbour list is constructed.
 *
 * The warp loops over atom blocks Y that were found to (possibly) interact with atom block X.  Each thread
 * in the warp loops over the TILE_SIZE atoms in X and compares their positions to one particular atom from block Y.
 * If it finds one closer than the cutoff distance, the atom is added to the list of atoms interacting with block X.
 * This continues until the buffer fills up, at which point the results are written to global memory.
 *
 * [in] periodicBoxSize        - size of the rectangular periodic box
 * [in] invPeriodicBoxSize     - inverse of the periodic box
 * [in] blockCenter            - the center of each bounding box
 * [in] blockBoundingBox       - bounding box of each atom block
 * [out] interactionCount      - total number of tiles that have interactions
 * [out] interactingTiles      - set of blocks that have interactions
 * [out] interactingAtoms      - a list of atoms that interact with each atom block
 * [in] posq                   - x,y,z coordinates of each atom and charge q
 * [in] maxTiles               - maximum number of tiles to process, used for multi-GPUs
 * [in] startBlockIndex        - first block to process, used for multi-GPUs,
 * [in] numBlocks              - total number of atom blocks
 * [in] sortedBlocks           - a sorted list of atom blocks based on volume
 * [in] sortedBlockCenter      - sorted centers, duplicated for fast access to avoid indexing
 * [in] sortedBlockBoundingBox - sorted bounding boxes, duplicated for fast access
 * [in] exclusionIndices       - maps into exclusionRowIndices with the starting position for a given atom
 * [in] exclusionRowIndices    - stores the a continuous list of exclusions
 *           eg: block 0 is excluded from atom 3,5,6
 *               block 1 is excluded from atom 3,4
 *               block 2 is excluded from atom 1,3,5,6
 *              exclusionIndices[0][3][5][8]
 *           exclusionRowIndices[3][5][6][3][4][1][3][5][6]
 *                         index 0  1  2  3  4  5  6  7  8
 * [out] oldPos                - stores the positions of the atoms in which this neighbourlist was built on
 *                             - this is used to decide when to rebuild a neighbourlist
 * [in] rebuildNeighbourList   - whether or not to execute this kernel
 *
 */
extern "C" __global__ void findBlocksWithInteractions(real4 periodicBoxSize, real4 invPeriodicBoxSize, real4 periodicBoxVecX, real4 periodicBoxVecY, real4 periodicBoxVecZ,
        unsigned int* __restrict__ interactionCount, int* __restrict__ interactingTiles, unsigned int* __restrict__ interactingAtoms,
        int2* __restrict__ singlePairs, const real4* __restrict__ posq, unsigned int maxTiles, unsigned int maxSinglePairs,
        unsigned int startBlockIndex, unsigned int numBlocks, real2* __restrict__ sortedBlocks, const real4* __restrict__ sortedBlockCenter,
        const real4* __restrict__ sortedBlockBoundingBox, const unsigned int* __restrict__ exclusionIndices, const unsigned int* __restrict__ exclusionRowIndices,
        real4* __restrict__ oldPositions, const int* __restrict__ rebuildNeighborList) {

    if (rebuildNeighborList[0] == 0)
        return; // The neighbor list doesn't need to be rebuilt.

    const int indexInWarp = threadIdx.x%TILE_SIZE;
    const int warpStart = threadIdx.x-indexInWarp;
    const int warpIndex = (blockIdx.x*blockDim.x+threadIdx.x)/TILE_SIZE;
    const tileflags warpMask = (static_cast<tileflags>(1)<<indexInWarp)-1;
    __shared__ int workgroupBuffer[BUFFER_SIZE*(GROUP_SIZE/TILE_SIZE)];
    __shared__ int warpExclusions[MAX_EXCLUSIONS*(GROUP_SIZE/TILE_SIZE)];
    __shared__ real4 posBuffer[GROUP_SIZE];
    int* buffer = workgroupBuffer+BUFFER_SIZE*(warpStart/TILE_SIZE);
    int* exclusionsForX = warpExclusions+MAX_EXCLUSIONS*(warpStart/TILE_SIZE);

    // Loop over blocks.

    int block1 = startBlockIndex+warpIndex/NUM_TILES_IN_BATCH;
    if (block1 < startBlockIndex+numBlocks) {
        // Load data for this block.  Note that all threads in a warp are processing the same block.

        real2 sortedKey = sortedBlocks[block1];
        int x = (int) sortedKey.y;
        real4 blockCenterX = sortedBlockCenter[block1];
        real4 blockSizeX = sortedBlockBoundingBox[block1];
        int neighborsInBuffer = 0;
        real4 pos1 = posq[x*TILE_SIZE+indexInWarp];
    #ifdef USE_PERIODIC
        const bool singlePeriodicCopy = (0.5f*periodicBoxSize.x-blockSizeX.x >= PADDED_CUTOFF &&
                                         0.5f*periodicBoxSize.y-blockSizeX.y >= PADDED_CUTOFF &&
                                         0.5f*periodicBoxSize.z-blockSizeX.z >= PADDED_CUTOFF);
        if (singlePeriodicCopy) {
            // The box is small enough that we can just translate all the atoms into a single periodic
            // box, then skip having to apply periodic boundary conditions later.

            APPLY_PERIODIC_TO_POS_WITH_CENTER(pos1, blockCenterX)
        }
    #endif
        pos1.w = 0.5f * (pos1.x * pos1.x + pos1.y * pos1.y + pos1.z * pos1.z);
        posBuffer[warpStart+indexInWarp] = pos1;

        // Load exclusion data for block x.

        const int exclusionStart = exclusionRowIndices[x];
        const int exclusionEnd = exclusionRowIndices[x+1];
        const int numExclusions = exclusionEnd-exclusionStart;
        for (int j = indexInWarp; j < numExclusions; j += TILE_SIZE)
            exclusionsForX[j] = exclusionIndices[exclusionStart+j];
        if (MAX_EXCLUSIONS > TILE_SIZE)
            __syncthreads();

        // Loop over atom blocks to search for neighbors.  The threads in a warp compare block1 against TILE_SIZE
        // other blocks in parallel.
        // For small systems multiple warps (NUM_TILES_IN_BATCH = 4, 2...) process one block1 reducing the overall
        // duration of the kernel because first blocks block1 have to process more block2 blocks so most of compute
        // units are idle at the end of the kernel (the kernel works on the upper triangle of
        // the NUM_BLOCKS x NUM_BLOCKS matrix).

        for (int block2Base = block1+1+(warpIndex%NUM_TILES_IN_BATCH); block2Base < NUM_BLOCKS; block2Base += TILE_SIZE*NUM_TILES_IN_BATCH) {
            int block2 = block2Base+indexInWarp*NUM_TILES_IN_BATCH;
            bool includeBlock2 = (block2 < NUM_BLOCKS);
            bool forceInclude = false;
            if (includeBlock2) {
                real4 blockCenterY = sortedBlockCenter[block2];
                real4 blockSizeY = sortedBlockBoundingBox[block2];
                real4 blockDelta = blockCenterX-blockCenterY;
    #ifdef USE_PERIODIC
                APPLY_PERIODIC_TO_DELTA(blockDelta)
    #endif
                includeBlock2 &= (blockDelta.x*blockDelta.x+blockDelta.y*blockDelta.y+blockDelta.z*blockDelta.z < (PADDED_CUTOFF+blockCenterX.w+blockCenterY.w)*(PADDED_CUTOFF+blockCenterX.w+blockCenterY.w));
                blockDelta.x = max(0.0f, fabs(blockDelta.x)-blockSizeX.x-blockSizeY.x);
                blockDelta.y = max(0.0f, fabs(blockDelta.y)-blockSizeX.y-blockSizeY.y);
                blockDelta.z = max(0.0f, fabs(blockDelta.z)-blockSizeX.z-blockSizeY.z);
                includeBlock2 &= (blockDelta.x*blockDelta.x+blockDelta.y*blockDelta.y+blockDelta.z*blockDelta.z < PADDED_CUTOFF_SQUARED);
    #ifdef TRICLINIC
                // The calculation to find the nearest periodic copy is only guaranteed to work if the nearest copy is less than half a box width away.
                // If there's any possibility we might have missed it, do a detailed check.

                if (periodicBoxSize.z/2-blockSizeX.z-blockSizeY.z < PADDED_CUTOFF || periodicBoxSize.y/2-blockSizeX.y-blockSizeY.y < PADDED_CUTOFF)
                    includeBlock2 = forceInclude = true;
    #endif
                if (includeBlock2) {
                    int y = (int) sortedBlocks[block2].y;
                    for (int k = 0; k < numExclusions; k++)
                        includeBlock2 &= (exclusionsForX[k] != y);
                }
            }

            // Loop over any blocks we identified as potentially containing neighbors.

            tileflags includeBlockFlags = BALLOT(includeBlock2);
            tileflags forceIncludeFlags = BALLOT(forceInclude);
            while (includeBlockFlags != 0) {
                int i = __TILEFLAGS_FFS(includeBlockFlags)-1;
                includeBlockFlags &= includeBlockFlags-1;
                forceInclude = (unsigned int)(forceIncludeFlags>>i) & 1;
                int y = (int) sortedBlocks[block2Base+i*NUM_TILES_IN_BATCH].y;

                // Check each atom in block Y for interactions.

                int atom2 = y*TILE_SIZE+indexInWarp;
                real4 pos2 = posq[atom2];
    #ifdef USE_PERIODIC
                if (singlePeriodicCopy) {
                    APPLY_PERIODIC_TO_POS_WITH_CENTER(pos2, blockCenterX)
                }
    #endif
                pos2.w = 0.5f * (pos2.x * pos2.x + pos2.y * pos2.y + pos2.z * pos2.z);
                real4 blockCenterY = sortedBlockCenter[block2Base+i*NUM_TILES_IN_BATCH];
                real3 atomDelta = trimTo3(posBuffer[warpStart+indexInWarp])-trimTo3(blockCenterY);
    #ifdef USE_PERIODIC
                APPLY_PERIODIC_TO_DELTA(atomDelta)
    #endif
                tileflags atomFlags = BALLOT(forceInclude || atomDelta.x*atomDelta.x+atomDelta.y*atomDelta.y+atomDelta.z*atomDelta.z < (PADDED_CUTOFF+blockCenterY.w)*(PADDED_CUTOFF+blockCenterY.w));
                tileflags interacts = 0;
                if (atom2 < NUM_ATOMS && atomFlags != 0) {
    #ifdef USE_PERIODIC
                    if (!singlePeriodicCopy) {
                        while (atomFlags) {
                            int j = __TILEFLAGS_FFS(atomFlags)-1;
                            atomFlags = atomFlags ^ (static_cast<tileflags>(1) << j);
                            real3 delta = trimTo3(pos2)-trimTo3(posBuffer[warpStart+j]);
                            APPLY_PERIODIC_TO_DELTA(delta)
                            interacts |= (delta.x*delta.x+delta.y*delta.y+delta.z*delta.z < PADDED_CUTOFF_SQUARED ? static_cast<tileflags>(1)<<j : 0);
                        }
                    }
                    else {
    #endif
                        const real lim = 0.5f * PADDED_CUTOFF_SQUARED - pos2.w;
                        if (__TILEFLAGS_POPC(atomFlags) < TILE_SIZE/2 && TILE_SIZE == warpSize) {
                            while (atomFlags) {
                                int j = __TILEFLAGS_FFS(atomFlags)-1;
                                atomFlags = atomFlags ^ (static_cast<tileflags>(1) << j);
                                real4 posj = posBuffer[warpStart+j];
                                real halfDist2 = posj.w - posj.x*pos2.x - posj.y*pos2.y - posj.z*pos2.z;
                                interacts |= (halfDist2 < lim ? static_cast<tileflags>(1)<<j : 0);
                            }
                        }
                        else {
                            #pragma unroll
                            for (int j = 0; j < TILE_SIZE; j++) {
                                real4 posj = posBuffer[warpStart+j];
                                real halfDist2 = posj.w - posj.x*pos2.x - posj.y*pos2.y - posj.z*pos2.z;
                                interacts |= (halfDist2 < lim ? static_cast<tileflags>(1)<<j : 0);
                            }
                        }
    #ifdef USE_PERIODIC
                    }
    #endif
                }

                const int interactCount = __TILEFLAGS_POPC(interacts);

                // Record interactions that should be computed as single pairs rather than in blocks.
    #if MAX_BITS_FOR_PAIRS > 0
                const bool storeAsSinglePair = interactCount > 0 && interactCount <= MAX_BITS_FOR_PAIRS;
                if (BALLOT(storeAsSinglePair)) {
                    int sum = (storeAsSinglePair ? interactCount : 0);
                    for (int i = 1; i < TILE_SIZE; i *= 2) {
                        int n = SHFL(sum, indexInWarp - i);
                        if (indexInWarp >= i)
                            sum += n;
                    }
                    int pairStartIndex = 0;
                    if (indexInWarp == TILE_SIZE - 1)
                        pairStartIndex = atomicAdd(&interactionCount[1], (unsigned int)sum);
                    pairStartIndex = SHFL(pairStartIndex, TILE_SIZE - 1);
                    int prevSum = SHFL(sum, indexInWarp - 1);
                    int pairIndex = pairStartIndex + (indexInWarp > 0 ? prevSum : 0);
                    if (storeAsSinglePair && pairIndex+interactCount <= maxSinglePairs) {
                        while (interacts != 0) {
                            int j = __TILEFLAGS_FFS(interacts)-1;
                            singlePairs[pairIndex] = make_int2(atom2, x*TILE_SIZE+j);
                            interacts = interacts ^ (static_cast<tileflags>(1) << j);
                            pairIndex++;
                        }
                    }
                }
    #endif

                // Add any interacting atoms to the buffer.

                tileflags includeAtomFlags = BALLOT(interactCount > MAX_BITS_FOR_PAIRS);
                if (interactCount > MAX_BITS_FOR_PAIRS) {
                    int index = neighborsInBuffer+__TILEFLAGS_POPC(includeAtomFlags&warpMask);
                    buffer[index] = atom2;
                }
                neighborsInBuffer += __TILEFLAGS_POPC(includeAtomFlags);
                if (neighborsInBuffer > BUFFER_SIZE-TILE_SIZE) {
                    // Store the new tiles to memory.

                    int tilesToStore = neighborsInBuffer/TILE_SIZE;
                    int tileStartIndex = 0;
                    if (indexInWarp == 0)
                        tileStartIndex = atomicAdd(&interactionCount[0], tilesToStore);
                    int newTileStartIndex = SHFL(tileStartIndex, 0);
                    if (newTileStartIndex+tilesToStore <= maxTiles) {
                        if (indexInWarp < tilesToStore)
                            interactingTiles[newTileStartIndex+indexInWarp] = x;
                        for (int j = 0; j < tilesToStore; j++)
                            interactingAtoms[newTileStartIndex*TILE_SIZE+j*TILE_SIZE+indexInWarp] = buffer[j*TILE_SIZE+indexInWarp];
                    }
                    if (indexInWarp+TILE_SIZE*tilesToStore < BUFFER_SIZE)
                        buffer[indexInWarp] = buffer[indexInWarp+TILE_SIZE*tilesToStore];
                    neighborsInBuffer -= TILE_SIZE*tilesToStore;
                }
            }
        }

        // If we have a partially filled buffer,  store it to memory.

        if (neighborsInBuffer > 0) {
            int tilesToStore = (neighborsInBuffer+TILE_SIZE-1)/TILE_SIZE;
            int tileStartIndex = 0;
            if (indexInWarp == 0)
                tileStartIndex = atomicAdd(&interactionCount[0], tilesToStore);
            int newTileStartIndex = SHFL(tileStartIndex, 0);
            if (newTileStartIndex+tilesToStore <= maxTiles) {
                if (indexInWarp < tilesToStore)
                    interactingTiles[newTileStartIndex+indexInWarp] = x;
                for (int j = 0; j < tilesToStore; j++)
                    interactingAtoms[newTileStartIndex*TILE_SIZE+j*TILE_SIZE+indexInWarp] = (j*TILE_SIZE+indexInWarp < neighborsInBuffer ? buffer[j*TILE_SIZE+indexInWarp] : PADDED_NUM_ATOMS);
            }
        }
    }

    // Record the positions the neighbor list is based on.

    int i = threadIdx.x+blockIdx.x*blockDim.x;
    if (i < NUM_ATOMS) {
        oldPositions[i] = posq[i];
    }
}
