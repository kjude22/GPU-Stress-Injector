#include "gpu_util.h"
#include <iostream>
#include <algorithm>
#include <chrono>
#include <cuda_runtime.h>

// 간단한 연산을 수행하여 GPU 코어에 부하를 주는 더미 커널
__global__ void stress_kernel(int iterations, float* dummy_data) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    float val = dummy_data[idx];
    for (int i = 0; i < iterations; ++i) {
        // 복잡한 연산을 반복하여 SM을 바쁘게 만듭니다.
        val = sinf(val) * cosf(val) + tanf(val);
        val = sqrtf(fabsf(val)) + 1.0f;
    }
    dummy_data[idx] = val;
}

GpuUtilStressor::GpuUtilStressor(int gpu_index)
    : gpu_index_(gpu_index), is_running_(false) {
}

GpuUtilStressor::~GpuUtilStressor() {
    stop();
}

bool GpuUtilStressor::start_percent(double percent) {
    cudaError_t err = cudaSetDevice(gpu_index_);
    if (err != cudaSuccess) {
        std::cerr << "cudaSetDevice failed: " << cudaGetErrorString(err) << std::endl;
        return false;
    }

    // 시스템 한계를 넘지 않도록 최대 이용률을 50%로 제한
    percent = std::min(percent, 50.0);
    percent = std::max(percent, 0.0);

    is_running_ = true;
    worker_thread_ = std::thread(&GpuUtilStressor::stress_worker, this, percent);

    return true;
}

void GpuUtilStressor::stop() {
    if (is_running_) {
        is_running_ = false;
        if (worker_thread_.joinable()) {
            worker_thread_.join();
        }
    }
}

void GpuUtilStressor::stress_worker(double percent) {
    cudaSetDevice(gpu_index_);

    int num_blocks = 1024;
    int threads_per_block = 256;
    int total_threads = num_blocks * threads_per_block;
    int kernel_iterations = 1000; // 커널 1회당 연산량

    float* d_dummy_data;
    cudaMalloc(&d_dummy_data, total_threads * sizeof(float));
    cudaMemset(d_dummy_data, 1, total_threads * sizeof(float));

    // Duty Cycle 주기 (예: 100ms)
    // 100ms 주기 내에서 목표 퍼센트만큼만 커널을 돌리고 나머지는 Sleep합니다.
    const int CYCLE_MS = 100;
    const double target_active_ms = CYCLE_MS * (percent / 100.0);

    while (is_running_) {
        auto cycle_start = std::chrono::steady_clock::now();
        
        // 목표 활성 시간(target_active_ms) 동안 커널을 반복 실행
        while (is_running_) {
            auto now = std::chrono::steady_clock::now();
            auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(now - cycle_start).count();
            
            if (elapsed_ms >= target_active_ms) {
                break; // 목표한 시간만큼 부하를 주었으면 탈출
            }

            // 커널 실행
            stress_kernel<<<num_blocks, threads_per_block>>>(kernel_iterations, d_dummy_data);
            cudaDeviceSynchronize();
        }

        // 주기의 남은 시간 동안 휴식(Sleep)하여 퍼센트를 맞춤
        auto now = std::chrono::steady_clock::now();
        auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(now - cycle_start).count();
        if (elapsed_ms < CYCLE_MS) {
            std::this_thread::sleep_for(std::chrono::milliseconds(CYCLE_MS - elapsed_ms));
        }
    }

    cudaFree(d_dummy_data);
}
