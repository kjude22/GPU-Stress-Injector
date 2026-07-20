#pragma once

#include <cstddef>

class GpuMemoryStressor {
public:
    explicit GpuMemoryStressor(int gpu_index);
    ~GpuMemoryStressor();

    bool allocate_percent(double percent);
    void release();

    std::size_t allocated_bytes() const;
    std::size_t total_bytes() const;

private:
    int gpu_index_;
    void* buffer_;
    std::size_t allocated_bytes_;
    std::size_t total_bytes_;
};
