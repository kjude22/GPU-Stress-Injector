#ifndef GPU_TENSOR_H
#define GPU_TENSOR_H

#include <atomic>
#include <thread>
#include <cuda_runtime.h>

class GpuTensorStressor {
private:
    int gpu_index;
    std::atomic<bool> keep_running;
    std::thread stress_thread;

    // 하드웨어 Power Limit 복원을 위한 변수
    bool power_limit_locked;
    unsigned int original_power_limit;

    void stress_loop(double target_percent);
    void lock_hardware_power_limit();
    void restore_hardware_power_limit();

public:
    GpuTensorStressor(int index);
    ~GpuTensorStressor();

    // 부하를 시작합니다. percent는 Duty Cycle (0~100, 내부적으로 상한선 적용)
    bool start_percent(double percent);
    
    // 부하를 중지하고 스레드를 정리합니다.
    void stop();
};

#endif // GPU_TENSOR_H
