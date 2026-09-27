/* Vector add for CUDA 6.5 / sm_11 (compute 1.1).
 * No C++ standard library, no device printf, no doubles.
 * cc 1.x: 512 threads/block max; this launch is 1 x 256.
 */
#include <stdio.h>

__global__ void vadd(const float *a, const float *b, float *c, int n)
{
	int i = blockIdx.x * blockDim.x + threadIdx.x;

	if (i < n)
		c[i] = a[i] + b[i];
}

int
main(void)
{
	const int n = 256;
	float a[256], b[256], c[256];
	float *da, *db, *dc;
	cudaError_t err;
	cudaDeviceProp prop;
	int i, dev;

	err = cudaGetDevice(&dev);
	if (err != cudaSuccess) {
		printf("cudaGetDevice: %s\n", cudaGetErrorString(err));
		return 1;
	}
	err = cudaGetDeviceProperties(&prop, dev);
	if (err != cudaSuccess) {
		printf("cudaGetDeviceProperties: %s\n", cudaGetErrorString(err));
		return 1;
	}
	printf("%s %d.%d\n", prop.name, prop.major, prop.minor);
	if (prop.major != 1) {
		printf("need compute 1.x\n");
		return 1;
	}

	for (i = 0; i < n; i++) {
		a[i] = (float)i;
		b[i] = 1.0f;
		c[i] = -1.0f;
	}

	err = cudaMalloc((void **)&da, (size_t)n * sizeof(float));
	if (err != cudaSuccess) {
		printf("cudaMalloc a: %s\n", cudaGetErrorString(err));
		return 1;
	}
	err = cudaMalloc((void **)&db, (size_t)n * sizeof(float));
	if (err != cudaSuccess) {
		printf("cudaMalloc b: %s\n", cudaGetErrorString(err));
		return 1;
	}
	err = cudaMalloc((void **)&dc, (size_t)n * sizeof(float));
	if (err != cudaSuccess) {
		printf("cudaMalloc c: %s\n", cudaGetErrorString(err));
		return 1;
	}

	cudaMemcpy(da, a, (size_t)n * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(db, b, (size_t)n * sizeof(float), cudaMemcpyHostToDevice);

	vadd<<<1, 256>>>(da, db, dc, n);
	err = cudaDeviceSynchronize();
	if (err != cudaSuccess) {
		printf("kernel: %s\n", cudaGetErrorString(err));
		return 1;
	}

	cudaMemcpy(c, dc, (size_t)n * sizeof(float), cudaMemcpyDeviceToHost);
	cudaFree(da);
	cudaFree(db);
	cudaFree(dc);

	/* c[i] must be i+1. Spot-check both ends. */
	if (c[0] != 1.0f || c[3] != 4.0f || c[255] != 256.0f) {
		printf("bad %f %f %f\n", c[0], c[3], c[255]);
		return 1;
	}
	printf("ok c[3]=%f\n", c[3]);
	return 0;
}
