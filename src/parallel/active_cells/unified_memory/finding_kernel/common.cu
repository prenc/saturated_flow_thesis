#include "../../../common/memory_management.cuh"
#include "../../../common/statistics.h"

__device__ unsigned activeCellsIdx[ROWS * COLS];

__global__ void simulation_step_kernel(struct CA ca, double *headsWrite)
{
    unsigned idx_x = blockIdx.x * blockDim.x + threadIdx.x;
    unsigned idx_y = blockIdx.y * blockDim.y + threadIdx.y;
    unsigned idx_g = idx_y * COLS + idx_x;

    if (idx_x < ROWS && idx_y < COLS)
    {
        if (activeCellsIdx[idx_g] == 1)
        {
            double Q{}, diff_head, tmp_t, ht1, ht2;
#ifdef LOOP
            for (int i = 0; i < KERNEL_LOOP_SIZE; i++)
            {
                if (i == KERNEL_LOOP_SIZE - 1)
                {
                    if (Q) { Q = 0; }
                }
#endif
            if (idx_x >= 1)
            {
                diff_head = ca.heads[idx_g - 1] - ca.heads[idx_g];
                tmp_t = ca.K[idx_g] * THICKNESS;
                Q += diff_head * tmp_t;
            }
            if (idx_y >= 1)
            {
                diff_head = ca.heads[(idx_y - 1) * COLS + idx_x] - ca.heads[idx_g];
                tmp_t = ca.K[idx_g] * THICKNESS;
                Q += diff_head * tmp_t;
            }
            if (idx_x + 1 < COLS)
            {
                diff_head = ca.heads[idx_g + 1] - ca.heads[idx_g];
                tmp_t = ca.K[idx_g] * THICKNESS;
                Q += diff_head * tmp_t;
            }
            if (idx_y + 1 < ROWS)
            {
                diff_head = ca.heads[(idx_y + 1) * COLS + idx_x] - ca.heads[idx_g];
                tmp_t = ca.K[idx_g] * THICKNESS;
                Q += diff_head * tmp_t;
            }
#ifdef LOOP
            }
#endif
            Q -= ca.sources[idx_g];
            ht1 = Q * DELTA_T;
            ht2 = AREA * ca.Sy[idx_g];

            headsWrite[idx_g] = ca.heads[idx_g] + ht1 / ht2;
            if (headsWrite[idx_g] < 0)
            { headsWrite[idx_g] = 0; }
        }
    }
}

__global__ void findActiveCells(struct CA d_ca)
{
    unsigned idx_x = blockIdx.x * blockDim.x + threadIdx.x;
    unsigned idx_y = blockIdx.y * blockDim.y + threadIdx.y;
    unsigned idx_g = idx_y * COLS + idx_x;

    if (idx_x < ROWS && idx_y < COLS)
    {
        if (d_ca.heads[idx_g] < INITIAL_HEAD || d_ca.sources[idx_g] != 0)
        {
            activeCellsIdx[idx_g] = 1;
            return;
        }
        if (idx_x > 0)
        {
            if (d_ca.heads[idx_g - 1] < INITIAL_HEAD)
            {
                activeCellsIdx[idx_g] = 1;
                return;
            }
        }
        if (idx_y > 0)
        {
            if (d_ca.heads[idx_g - COLS] < INITIAL_HEAD)
            {
                activeCellsIdx[idx_g] = 1;
                return;
            }
        }
        if (idx_x < COLS - 1)
        {
            if (d_ca.heads[idx_g + 1] < INITIAL_HEAD)
            {
                activeCellsIdx[idx_g] = 1;
                return;
            }
        }
        if (idx_y < ROWS - 1)
        {
            if (d_ca.heads[idx_g + COLS] < INITIAL_HEAD)
            {
                activeCellsIdx[idx_g] = 1;
                return;
            }
        }
        activeCellsIdx[idx_g] = 0;
    }
}

int main(int argc, char *argv[])
{
    auto h_ca = new CA();
    double *headsWrite;
    allocateManagedMemory(h_ca, headsWrite);

    initializeCA(h_ca);
    memcpy(headsWrite, h_ca->heads, sizeof(double) * ROWS * COLS);

    dim3 blockSize(BLOCK_SIZE, BLOCK_SIZE);
    const int blockCount = ceil((double) (ROWS * COLS) / (BLOCK_SIZE * BLOCK_SIZE));
    int gridSize = ceil(sqrt(blockCount));
    dim3 gridDims(gridSize, gridSize);

    std::vector<StatPoint> stats;
    Timer stepTimer, activeCellsEvalTimer, transitionTimer;
    stepTimer.start();

    for (int i{}; i < SIMULATION_ITERATIONS; ++i)
    {
        findActiveCells <<< gridDims, blockSize >>>(*h_ca);
        ERROR_CHECK(cudaDeviceSynchronize());

        transitionTimer.start();
        simulation_step_kernel <<< gridDims, blockSize >>>(*h_ca, headsWrite);
        ERROR_CHECK(cudaDeviceSynchronize());
        transitionTimer.stop();

        double *tmpHeads = h_ca->heads;
        h_ca->heads = headsWrite;
        headsWrite = tmpHeads;

        if (i % STATISTICS_WRITE_FREQ == STATISTICS_WRITE_FREQ - 1)
        {
            stepTimer.stop();
            auto stat = new StatPoint(
                    -1,
                    stepTimer.elapsedNanoseconds(),
                    transitionTimer.elapsedNanoseconds(),
                    activeCellsEvalTimer.elapsedNanoseconds());
            stats.push_back(*stat);
            stepTimer.start();
        }
    }

    if (WRITE_OUTPUT_TO_FILE)
    {
        saveHeadsInFile(h_ca->heads, argv[0]);
    }

    if (WRITE_STATISTICS_TO_FILE)
    {
        writeStatisticsToFile(stats, argv[0]);
    }

    freeAllocatedMemory(h_ca, headsWrite);
}