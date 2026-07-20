#include "gpu_memory.h"
#include <iostream>
#include <algorithm>
#include <cuda_runtime.h>

GpuMemoryStressor::GpuMemoryStressor(int gpu_index)
    : gpu_index_(gpu_index), buffer_(nullptr), allocated_bytes_(0), total_bytes_(0) {
}

GpuMemoryStressor::~GpuMemoryStressor() {
    release();
}

bool GpuMemoryStressor::allocate_percent(double percent) {
    cudaError_t err = cudaSetDevice(gpu_index_);
    if (err != cudaSuccess) {
        std::cerr << "cudaSetDevice failed: " << cudaGetErrorString(err) << std::endl;
        return false;
    }

    std::size_t free_byte;
    std::size_t total_byte;
    err = cudaMemGetInfo(&free_byte, &total_byte);
    if (err != cudaSuccess) {
        std::cerr << "cudaMemGetInfo failed: " << cudaGetErrorString(err) << std::endl;
        return false;
    }

    total_bytes_ = total_byte;

    // 안전 상한선 20%
    percent = std::min(percent, 20.0);
    percent = std::max(percent, 0.0);

    allocated_bytes_ = static_cast<std::size_t>(total_bytes_ * (percent / 100.0));

    if (allocated_bytes_ == 0) return true;

    err = cudaMalloc(&buffer_, allocated_bytes_);
    if (err != cudaSuccess) {
        std::cerr << "cudaMalloc failed: " << cudaGetErrorString(err) << std::endl;
        buffer_ = nullptr;
        allocated_bytes_ = 0;
        return false;
    }

    // 실제 데이터를 써서 할당을 강제함
    err = cudaMemset(buffer_, 1, allocated_bytes_);
    if (err != cudaSuccess) {
        std::cerr << "cudaMemset failed: " << cudaGetErrorString(err) << std::endl;
        cudaFree(buffer_);
        buffer_ = nullptr;
        allocated_bytes_ = 0;
        return false;
    }

    return true;
}

void GpuMemoryStressor::release() {
    if (buffer_) {
        cudaFree(buffer_);
        buffer_ = nullptr;
        allocated_bytes_ = 0;
    }
}

std::size_t GpuMemoryStressor::allocated_bytes() const {
    return allocated_bytes_;
}

std::size_t GpuMemoryStressor::total_bytes() const {
    return total_bytes_;
}
