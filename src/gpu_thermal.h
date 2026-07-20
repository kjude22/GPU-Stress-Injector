#pragma once

#include <atomic>
#include <thread>

class GpuThermalStressor {
public:
    explicit GpuThermalStressor(int gpu_index);
    ~GpuThermalStressor();

    // 목표 온도(섭씨)로 부하 발생 시작
    bool start_target_temp(unsigned int target_temp_c);
    // 부하 발생 중단
    void stop();

private:
    void stress_worker(unsigned int target_temp_c);

    int gpu_index_;
    std::atomic<bool> is_running_;
    std::thread worker_thread_;
};
