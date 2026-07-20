#pragma once

#include <cstddef>
#include <atomic>
#include <thread>

class GpuUtilStressor {
public:
    explicit GpuUtilStressor(int gpu_index);
    ~GpuUtilStressor();

    // 목표 이용률(%)로 부하 발생 시작
    bool start_percent(double percent);
    // 부하 발생 중단
    void stop();

private:
    void stress_worker(double percent);

    int gpu_index_;
    std::atomic<bool> is_running_;
    std::thread worker_thread_;
};
