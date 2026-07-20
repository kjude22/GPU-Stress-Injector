#include "gpu_thermal.h"
#include <iostream>
#include <algorithm>
#include <chrono>
#include <cuda_runtime.h>
#include <nvml.h>

__global__ void thermal_stress_kernel(float* d_data, int N, int offset) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < N) {
        float val = d_data[(idx + offset) % N];
        for(int i = 0; i < 50; i++) {
             val = val * 1.00001f + 0.001f;
        }
        d_data[idx] = val;
    }
}

GpuThermalStressor::GpuThermalStressor(int gpu_index)
    : gpu_index_(gpu_index), is_running_(false) {
}

GpuThermalStressor::~GpuThermalStressor() {
    stop();
}

bool GpuThermalStressor::start_target_temp(unsigned int target_temp_c) {
    cudaError_t err = cudaSetDevice(gpu_index_);
    if (err != cudaSuccess) return false;

    // 안전 상한선 65도
    target_temp_c = std::min(target_temp_c, (unsigned int)65);

    is_running_ = true;
    worker_thread_ = std::thread(&GpuThermalStressor::stress_worker, this, target_temp_c);

    return true;
}

void GpuThermalStressor::stop() {
    if (is_running_) {
        is_running_ = false;
        if (worker_thread_.joinable()) {
            worker_thread_.join();
        }
    }
}

void GpuThermalStressor::stress_worker(unsigned int target_temp_c) {
    cudaSetDevice(gpu_index_);
    
    nvmlInit();
    nvmlDevice_t device;
    if (nvmlDeviceGetHandleByIndex(gpu_index_, &device) != NVML_SUCCESS) {
        return;
    }
    
    // 넓은 메모리 I/O 유발
    int N = 50000000;
    int blockSize = 256;
    int numBlocks = (N + blockSize - 1) / blockSize;
    
    float* d_dummy_data;
    cudaMalloc(&d_dummy_data, N * sizeof(float));
    
    while (is_running_) {
        unsigned int temp = 0;
        nvmlDeviceGetTemperature(device, NVML_TEMPERATURE_GPU, &temp);
        
        if (temp >= target_temp_c) {
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
        } else {
            thermal_stress_kernel<<<numBlocks, blockSize>>>(d_dummy_data, N, rand() % 1024);
            cudaDeviceSynchronize();
        }
    }
    
    cudaFree(d_dummy_data);
}
