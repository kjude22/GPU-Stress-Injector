#pragma once

#include <cstddef>
#include <atomic>
#include <thread>

class GpuPcieStressor {
public:
    explicit GpuPcieStressor(int gpu_index);
    ~GpuPcieStressor();

    bool start_percent(double percent);
    void stop();

private:
    void worker_thread_func();

    int gpu_index_;
    double target_mbps_;
    std::atomic<bool> stop_signal_;
    std::thread worker_thread_;

    void* host_buffer_;
    void* device_buffer_;
    size_t buffer_size_;
};
