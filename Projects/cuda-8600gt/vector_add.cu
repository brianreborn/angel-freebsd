/* CUDA 6.5, sm_11. No C++ runtime, no printf from the device. */
#include <stdio.h>
#include <cuda_runtime.h>

__global__ void vadd(const float *a, const float *b, float *c, int n)
{
	int i = blockIdx.x * blockDim.x + threadIdx.x;

	if (i < n)
		c[i] = a[i] + b[i];
}

int main(void)
{
	const int n = 256;
	float a[256], b[256], c[256];
	float *da, *db, *dc;
	int i;
	cudaDeviceProp prop;
	cudaError_t err;

	err = cudaGetDeviceProperties(&prop, 0);
	if (err != cudaSuccess) {
		fprintf(stderr, "no CUDA device: %s\n", cudaGetErrorString(err));
		return 1;
	}
	printf("%s compute %d.%d\n", prop.name, prop.major, prop.minor);
	if (prop.major != 1) {
		fprintf(stderr, "expected compute 1.x (8600 GT is 1.1)\n");
		return 1;
	}

	for (i = 0; i < n; i++) {
		a[i] = (float)i;
		b[i] = 1.0f;
	}

	if (cudaMalloc((void **)&da, n * sizeof(float)) != cudaSuccess ||
	    cudaMalloc((void **)&db, n * sizeof(float)) != cudaSuccess ||
	    cudaMalloc((void **)&dc, n * sizeof(float)) != cudaSuccess) {
		fprintf(stderr, "cudaMalloc failed\n");
		return 1;
	}
	cudaMemcpy(da, a, n * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(db, b, n * sizeof(float), cudaMemcpyHostToDevice);
	vadd<<<1, n>>>(da, db, dc, n);
	err = cudaDeviceSynchronize();
	if (err != cudaSuccess) {
		fprintf(stderr, "kernel: %s\n", cudaGetErrorString(err));
		return 1;
	}
	cudaMemcpy(c, dc, n * sizeof(float), cudaMemcpyDeviceToHost);

	if (c[0] != 1.0f || c[255] != 256.0f) {
		fprintf(stderr, "bad result %f %f\n", c[0], c[255]);
		return 1;
	}
	printf("ok\n");
	return 0;
}
