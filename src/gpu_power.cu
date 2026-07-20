#include "gpu_power.h"
#include <iostream>
#include <algorithm>
#include <chrono>
#include <cuda_runtime.h>
#include <nvml.h>

__global__ void power_stress_kernel(int iterations, float* dummy_data) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    float val = dummy_data[idx];
    for (int i = 0; i < iterations; ++i) {
        val = val * val + 0.0001f;
    }
    dummy_data[idx] = val;
}

GpuPowerStressor::GpuPowerStressor(int gpu_index)
    : gpu_index_(gpu_index), is_running_(false) {
}

GpuPowerStressor::~GpuPowerStressor() {
    stop();
}

bool GpuPowerStressor::start_percent(double percent) {
    cudaError_t err = cudaSetDevice(gpu_index_);
    if (err != cudaSuccess) return false;

    // 안전 상한선 60%
    percent = std::min(std::max(percent, 0.0), 60.0);
    is_running_ = true;
    worker_thread_ = std::thread(&GpuPowerStressor::stress_worker, this, percent);

    return true;
}

void GpuPowerStressor::stop() {
    if (is_running_) {
        is_running_ = false;
        if (worker_thread_.joinable()) {
            worker_thread_.join();
        }
    }
}

void GpuPowerStressor::stress_worker(double percent) {
    cudaSetDevice(gpu_index_);
    
    // NVML 초기화 및 핸들 획득
    nvmlInit();
    nvmlDevice_t device;
    if (nvmlDeviceGetHandleByIndex(gpu_index_, &device) != NVML_SUCCESS) {
        return; // 실패 시 안전하게 종료
    }
    
    unsigned int tdp_limit = 0;
    nvmlDeviceGetPowerManagementLimit(device, &tdp_limit);
    
    // 오차 범위를 둔 목표 전력 (예: 목표 70% -> 65% ~ 75%)
    unsigned int target_power_min = (unsigned int)(tdp_limit * std::max(0.0, percent - 5.0) / 100.0);
    unsigned int target_power_max = (unsigned int)(tdp_limit * std::min(100.0, percent + 5.0) / 100.0);
    
    int num_blocks = 1024;
    int threads_per_block = 256;
    float* d_dummy_data;
    cudaMalloc(&d_dummy_data, num_blocks * threads_per_block * sizeof(float));
    
    int sleep_time_ms = 5;
    
    while (is_running_) {
        unsigned int power = 0;
        nvmlDeviceGetPowerUsage(device, &power);
        
        if (power < target_power_min) {
            sleep_time_ms = std::max(0, sleep_time_ms - 1);
        } else if (power > target_power_max) {
            sleep_time_ms += 2;
        }
        
        power_stress_kernel<<<num_blocks, threads_per_block>>>(5000, d_dummy_data);
        cudaDeviceSynchronize();
        
        if (sleep_time_ms > 0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(sleep_time_ms));
        }
    }
    
    cudaFree(d_dummy_data);
}
