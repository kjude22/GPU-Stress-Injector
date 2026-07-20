#pragma once

#include <atomic>
#include <thread>

class GpuPowerStressor {
public:
    explicit GpuPowerStressor(int gpu_index);
    ~GpuPowerStressor();

    // 목표 전력 비율(%)로 부하 발생 시작
    bool start_percent(double percent);
    // 부하 발생 중단
    void stop();

private:
    void stress_worker(double percent);

    int gpu_index_;
    std::atomic<bool> is_running_;
    std::thread worker_thread_;
};
