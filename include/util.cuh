#pragma once
#include <cooperative_groups.h>
#include <cuda.h>
#include <stdio.h>
#include <stdlib.h>
#include <set>
#include <tuple>
#include <utility>
#include <iostream>
#include <assert.h>

// #include <nvml.h>

// #define u64 unsigned long long int
using u64 = unsigned long long int;
using ll = long long;
using uint = unsigned int;
// using vtx_t = unsigned int;
using vtx_t = int;
using edge_t = unsigned int;
using weight_t = float;
using ulong = unsigned long;

// #define USING_HALF
#ifdef USING_HALF
#include <cuda_fp16.h>
using prob_t = __half;
using offset_t = uint16_t; // 65535
#else
using prob_t = float;
using offset_t = uint32_t;
#endif // USING_HALF

#define SPEC_EXE
// #define RECORD_SPEC_FAIL

#define SASYNC_EXE

#define TID (threadIdx.x + blockIdx.x * blockDim.x)
#define LTID (threadIdx.x)
#define BID (blockIdx.x)
#define LID (threadIdx.x % 32)
#define WID (threadIdx.x / 32)
#define GWID (TID / 32)
#define MIN(x, y) ((x < y) ? x : y)
#define MAX(x, y) ((x > y) ? x : y)
// #define P printf("%d\n", __LINE__)
#define paster(n) printf("var: " #n " =  %d\n", n)

#define WARP_SIZE 32
// #define BLOCK_SIZE 256
#define BLOCK_SIZE 512
#define WARP_PER_BLK (BLOCK_SIZE / 32)
#define FULL_WARP_MASK 0xffffffff

#define CUDA_RT_CALL(call)                                                     \
	{                                                                          \
		cudaError_t cudaStatus = call;                                         \
		if (cudaSuccess != cudaStatus)                                         \
		{                                                                      \
			fprintf(stderr,                                                    \
					"%s:%d ERROR: CUDA RT call \"%s\" failed "                 \
					"with "                                                    \
					"%s (%d).\n",                                              \
					__FILE__, __LINE__, #call, cudaGetErrorString(cudaStatus), \
					cudaStatus);                                               \
			exit(cudaStatus);                                                  \
		}                                                                      \
	}

#define H_ERR(ans)                            \
	{                                         \
		gpuAssert((ans), __FILE__, __LINE__); \
	}

namespace print
{
	template <typename... Args>
	__host__ __device__ __forceinline__ void myprintf(const char *file, int line,
													  const char *__format,
													  Args... args)
	{
#if defined(__CUDA_ARCH__)
		// if (LID == 0)
		{
			printf("%s:%d GPU: ", file, line);
			printf(__format, args...);
		}
#else
		printf("%s:%d HOST: ", file, line);
		printf(__format, args...);
#endif
	}

} // namespace print
#define LOG(...) \
	print::myprintf(__FILE__, __LINE__, __VA_ARGS__)

#include <stdlib.h>
#include <sys/time.h>
double wtime();

#define FULL_WARP_MASK 0xffffffff

template <typename T>
__inline__ __device__ T warpReduce(T val)
{
	// T val_shuffled;
	for (int offset = 16; offset > 0; offset /= 2)
		val += __shfl_down_sync(FULL_WARP_MASK, val, offset);
	return val;
}
template <typename T>
__inline__ __device__ T warpReduceMax(T val)
{
	for (int mask = WARP_SIZE / 2; mask > 0; mask >>= 1)
		val = max(val, __shfl_xor_sync(FULL_WARP_MASK, val, mask, WARP_SIZE));
	return val;
}

__device__ uint binary_search(float *prob, int size, float target);

size_t get_avail_mem();

__global__ void warm_up_gpu();

// int zipf(double alpha, int n); // Returns a Zipf random variable
// double rand_val(int seed);	   // Jain's RNG

void zipf(float *rand_array, int len, float alpha, int n);

int get_clk();

class metrics
{
public:
	int block_num;

	int *b_thread_cnt;
	int *b_warp_cnt;
	int *b_block_cnt;

	u64 *b_thread_degree;
	u64 *b_warp_degree;
	u64 *b_block_degree;

	u64 *b_thread_clock;
	u64 *b_warp_clock;
	u64 *b_block_clock;

	u64 *b_start_clock;
	u64 *b_sample_clock;
	u64 *b_end_clock;

public:
	metrics()
	{
	}
	metrics(int _block_num)
	{
		block_num = _block_num;

		CUDA_RT_CALL(cudaMallocManaged(&b_thread_cnt, block_num * sizeof(int)));
		CUDA_RT_CALL(cudaMallocManaged(&b_warp_cnt, block_num * sizeof(int)));
		CUDA_RT_CALL(cudaMallocManaged(&b_block_cnt, block_num * sizeof(int)));

		CUDA_RT_CALL(cudaMallocManaged(&b_thread_degree, block_num * sizeof(u64)));
		CUDA_RT_CALL(cudaMallocManaged(&b_warp_degree, block_num * sizeof(u64)));
		CUDA_RT_CALL(cudaMallocManaged(&b_block_degree, block_num * sizeof(u64)));

		CUDA_RT_CALL(cudaMallocManaged(&b_thread_clock, block_num * sizeof(u64)));
		CUDA_RT_CALL(cudaMallocManaged(&b_warp_clock, block_num * sizeof(u64)));
		CUDA_RT_CALL(cudaMallocManaged(&b_block_clock, block_num * sizeof(u64)));

		CUDA_RT_CALL(cudaMallocManaged(&b_start_clock, block_num * sizeof(u64)));
		CUDA_RT_CALL(cudaMallocManaged(&b_sample_clock, block_num * sizeof(u64)));
		CUDA_RT_CALL(cudaMallocManaged(&b_end_clock, block_num * sizeof(u64)));

		CUDA_RT_CALL(cudaMemset(b_thread_cnt, 0, block_num * sizeof(int)));
		CUDA_RT_CALL(cudaMemset(b_warp_cnt, 0, block_num * sizeof(int)));
		CUDA_RT_CALL(cudaMemset(b_block_cnt, 0, block_num * sizeof(int)));

		CUDA_RT_CALL(cudaMemset(b_thread_degree, 0, block_num * sizeof(u64)));
		CUDA_RT_CALL(cudaMemset(b_warp_degree, 0, block_num * sizeof(u64)));
		CUDA_RT_CALL(cudaMemset(b_block_degree, 0, block_num * sizeof(u64)));

		CUDA_RT_CALL(cudaMemset(b_thread_clock, 0, block_num * sizeof(u64)));
		CUDA_RT_CALL(cudaMemset(b_warp_clock, 0, block_num * sizeof(u64)));
		CUDA_RT_CALL(cudaMemset(b_block_clock, 0, block_num * sizeof(u64)));

		CUDA_RT_CALL(cudaMemset(b_start_clock, 0, block_num * sizeof(u64)));
		CUDA_RT_CALL(cudaMemset(b_sample_clock, 0, block_num * sizeof(u64)));
		CUDA_RT_CALL(cudaMemset(b_end_clock, 0, block_num * sizeof(u64)));
	}
	// void print(int peak_clk)
	// {
	// 	printf("thread_cnt=%llu\nwarp_cnt=%llu\nblock_cnt=%llu\npeak clock rate: %d kHz\nthread time=%f ms\nwarp time=%f ms\nblock time=%f ms\n", thread_cnt, warp_cnt, block_cnt, peak_clk, thread_clock / (float)peak_clk, warp_clock / (float)peak_clk, block_clock / (float)peak_clk);
	// }
	void print_all(int peak_clk)
	{
		u64 thread_cnt = 0;
		u64 warp_cnt = 0;
		u64 block_cnt = 0;
		u64 thread_clock = 0;
		u64 warp_clock = 0;
		u64 block_clock = 0;
		ll thread_degree = 0;
		ll warp_degree = 0;
		ll block_degree = 0;

		ll b_max = 0;
		ll b_min = 0x7fffffffffffffff;
		int max_idx = 0;
		int min_idx = 0;

		std::set<std::pair<ll, int>> s;
		for (int i = 0; i < block_num; i++)
		{
			s.insert(std::make_pair(b_thread_degree[i] + b_warp_degree[i] + b_block_degree[i], i));
		}

		printf("=================block info=============\n");
		for (auto &p : s)
		{
			int i = p.second;

			printf("bid:%d,time:%f ms,cnt:%d-%lld(t:%d-%lld-%f ms,w:%d-%lld-%f ms,b:%d-%lld-%f ms)\n",
				   i, b_sample_clock[i] / (float)peak_clk,
				   (b_thread_cnt[i] + b_warp_cnt[i] + b_block_cnt[i]),
				   (b_thread_degree[i] + b_warp_degree[i] + b_block_degree[i]),
				   b_thread_cnt[i], b_thread_degree[i], b_thread_clock[i] / (float)peak_clk,
				   b_warp_cnt[i], b_warp_degree[i], b_warp_clock[i] / (float)peak_clk,
				   b_block_cnt[i], b_block_degree[i], b_block_clock[i] / (float)peak_clk);

			thread_cnt += b_thread_cnt[i];
			warp_cnt += b_warp_cnt[i];
			block_cnt += b_block_cnt[i];
			thread_clock += b_thread_clock[i];
			warp_clock += b_warp_clock[i];
			block_clock += b_block_clock[i];
			thread_degree += b_thread_degree[i];
			warp_degree += b_warp_degree[i];
			block_degree += b_block_degree[i];
			if (b_max < b_sample_clock[i])
			{
				b_max = b_sample_clock[i];
				max_idx = i;
			}
			if (b_min > b_sample_clock[i])
			{
				b_min = b_sample_clock[i];
				min_idx = i;
			}
		}
		printf("max:%d (%f ms),min:%d (%f ms), gap: %f ms\n", max_idx, b_max / (float)peak_clk, min_idx, b_min / (float)peak_clk, (b_max - b_min) / (float)peak_clk);

		printf("=================global info=============\n");
		printf("thread_cnt=%llu\nwarp_cnt=%llu\nblock_cnt=%llu\npeak clock rate: %d kHz\nthread time=%f ms\nwarp time=%f ms\nblock time=%f ms\n", thread_cnt, warp_cnt, block_cnt, peak_clk, thread_clock / (float)peak_clk, warp_clock / (float)peak_clk, block_clock / (float)peak_clk);
		printf("thread degree:%lld\nwarp degree:%lld\nblock degree:%lld\n", thread_degree, warp_degree, block_degree);
	}

	__device__ inline void add_thread(int bid, u64 start, int degree)
	{
		atomicAdd(b_thread_clock + bid, clock64() - start);
		atomicAdd(b_thread_cnt + bid, 1);
		atomicAdd(b_thread_degree + bid, degree);
	}

	__device__ inline void add_warp(int bid, u64 start, int degree)
	{
		if (threadIdx.x % WARP_SIZE == 0)
		{
			atomicAdd(b_warp_clock + bid, clock64() - start);
			atomicAdd(b_warp_cnt + bid, 1);
			atomicAdd(b_warp_degree + bid, degree);
		}
	}

	__device__ inline void add_block(int bid, u64 start, int degree)
	{
		if (threadIdx.x == 0)
		{
			atomicAdd(b_block_clock + bid, clock64() - start);
			atomicAdd(b_block_cnt + bid, 1);
			atomicAdd(b_block_degree + bid, degree);
		}
	}
	__device__ inline void block_begin(int bid)
	{
		if (threadIdx.x == 0)
		{
			b_start_clock[bid] = clock64();
		}
	}
	__device__ inline void sample_begin(int bid)
	{
		if (threadIdx.x == 0)
		{
			b_sample_clock[bid] = clock64();
		}
	}

	__device__ inline void block_end(int bid)
	{
		if (threadIdx.x == 0)
		{
			b_end_clock[bid] = clock64();
			b_sample_clock[bid] = b_end_clock[bid] - b_sample_clock[bid];
		}
	}
};
