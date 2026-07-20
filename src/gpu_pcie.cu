#include "gpu_pcie.h"
#include <iostream>
#include <chrono>
#include <cuda_runtime.h>
#include <algorithm>

GpuPcieStressor::GpuPcieStressor(int gpu_index)
    : gpu_index_(gpu_index), target_mbps_(0), stop_signal_(false),
      host_buffer_(nullptr), device_buffer_(nullptr), buffer_size_(0) {}

GpuPcieStressor::~GpuPcieStressor() {
    stop();
}

bool GpuPcieStressor::start_percent(double percent) {
    // 안전 상한선 25%
    percent = std::min(percent, 25.0);
    if (percent <= 0.0) return true; // No stress requested

    // Assume max PCIe Bandwidth is around 16000 MB/s for Gen3/Gen4 average
    double max_mbps = 16000.0;
    target_mbps_ = max_mbps * (percent / 100.0);
    stop_signal_ = false;

    // Use a fixed buffer size, e.g., 64 MB
    buffer_size_ = 64 * 1024 * 1024;

    cudaError_t err = cudaSetDevice(gpu_index_);
    if (err != cudaSuccess) {
        std::cerr << "PCIe: cudaSetDevice failed: " << cudaGetErrorString(err) << std::endl;
        return false;
    }

    err = cudaMallocHost(&host_buffer_, buffer_size_);
    if (err != cudaSuccess) {
        std::cerr << "PCIe: cudaMallocHost failed: " << cudaGetErrorString(err) << std::endl;
        return false;
    }

    err = cudaMalloc(&device_buffer_, buffer_size_);
    if (err != cudaSuccess) {
        std::cerr << "PCIe: cudaMalloc failed: " << cudaGetErrorString(err) << std::endl;
        cudaFreeHost(host_buffer_);
        host_buffer_ = nullptr;
        return false;
    }

    worker_thread_ = std::thread(&GpuPcieStressor::worker_thread_func, this);
    return true;
}

void GpuPcieStressor::stop() {
    if (worker_thread_.joinable()) {
        stop_signal_ = true;
        worker_thread_.join();
    }

    if (device_buffer_) {
        cudaFree(device_buffer_);
        device_buffer_ = nullptr;
    }
    if (host_buffer_) {
        cudaFreeHost(host_buffer_);
        host_buffer_ = nullptr;
    }
}

void GpuPcieStressor::worker_thread_func() {
    cudaSetDevice(gpu_index_);

    cudaStream_t stream_h2d;
    cudaStreamCreate(&stream_h2d);

    double cycle_time_sec = 0.1; // 100ms
    // Calculate total bytes to send per cycle (MB to bytes)
    double mb_per_cycle = target_mbps_ * cycle_time_sec;
    // H2D 단방향이므로 나누기 2 없이 목표 대역폭 전부를 H2D로 할당합니다.
    size_t bytes_per_cycle = static_cast<size_t>(mb_per_cycle * 1024 * 1024);

    // Clamp bytes_per_cycle to buffer_size
    bytes_per_cycle = std::min(bytes_per_cycle, buffer_size_);

    while (!stop_signal_) {
        auto start_time = std::chrono::high_resolution_clock::now();

        // Asynchronous unidirectional transfer (H2D)
        cudaMemcpyAsync(device_buffer_, host_buffer_, bytes_per_cycle, cudaMemcpyHostToDevice, stream_h2d);

        cudaStreamSynchronize(stream_h2d);

        auto end_time = std::chrono::high_resolution_clock::now();
        std::chrono::duration<double> elapsed = end_time - start_time;

        // Sleep to throttle if completed faster than cycle time
        double sleep_time_sec = cycle_time_sec - elapsed.count();
        if (sleep_time_sec > 0.0) {
            std::this_thread::sleep_for(std::chrono::duration<double>(sleep_time_sec));
        }
    }

    cudaStreamDestroy(stream_h2d);
}
