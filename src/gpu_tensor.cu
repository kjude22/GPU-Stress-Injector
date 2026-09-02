#include "gpu_tensor.h"
#include <iostream>
#include <chrono>
#include <mma.h>
#include <nvml.h>

using namespace nvcuda;

// FP16 WMMA 기반의 텐서 코어 스트레스 커널
// 글로벌 메모리 접근 없이 레지스터와 공유 메모리에서만 동작하여 VRAM 고립 달성
__global__ void tensor_stress_kernel(unsigned int iterations) {
    // 16x16x16 행렬 곱셈-누산(MMA) 선언
    wmma::fragment<wmma::matrix_a, 16, 16, 16, half, wmma::row_major> a_frag;
    wmma::fragment<wmma::matrix_b, 16, 16, 16, half, wmma::col_major> b_frag;
    wmma::fragment<wmma::accumulator, 16, 16, 16, half> c_frag;

    // 프래그먼트 초기화
    wmma::fill_fragment(a_frag, __float2half(1.0f));
    wmma::fill_fragment(b_frag, __float2half(1.0f));
    wmma::fill_fragment(c_frag, __float2half(0.0f));

    // 무한 텐서 코어 연산 루프 (Micro-duty 동안 실행)
    for (unsigned int i = 0; i < iterations; ++i) {
        wmma::mma_sync(c_frag, a_frag, b_frag, c_frag);
    }
}

GpuTensorStressor::GpuTensorStressor(int index) 
    : gpu_index(index), keep_running(false), power_limit_locked(false), original_power_limit(0) {
    cudaSetDevice(gpu_index);
}

GpuTensorStressor::~GpuTensorStressor() {
    stop();
}

void GpuTensorStressor::lock_hardware_power_limit() {
    // NVML을 통해 현재 GPU의 Power Limit을 임시로 60% 등으로 락(Lock)하는 로직
    // 실제 구현에서는 nvmlDeviceGetPowerManagementLimit / nvmlDeviceSetPowerManagementLimit 사용
    // (보안 권한 필요)
    if (nvmlInit() == NVML_SUCCESS) {
        nvmlDevice_t device;
        if (nvmlDeviceGetHandleByIndex(gpu_index, &device) == NVML_SUCCESS) {
            unsigned int current_limit;
            if (nvmlDeviceGetPowerManagementLimit(device, &current_limit) == NVML_SUCCESS) {
                original_power_limit = current_limit;
                // 하드웨어 스파이크 방지를 위해 기존 전력의 70% 수준으로 하드 락
                unsigned int safe_limit = current_limit * 0.7; 
                if (nvmlDeviceSetPowerManagementLimit(device, safe_limit) == NVML_SUCCESS) {
                    power_limit_locked = true;
                    std::cout << "[TensorSafety] Hardware power limit temporarily locked to " << (safe_limit / 1000) << " W" << std::endl;
                } else {
                    std::cerr << "[TensorSafety] Warning: Need sudo to lock power limit. Relying solely on software control." << std::endl;
                }
            }
        }
    }
}

void GpuTensorStressor::restore_hardware_power_limit() {
    if (power_limit_locked) {
        nvmlDevice_t device;
        if (nvmlDeviceGetHandleByIndex(gpu_index, &device) == NVML_SUCCESS) {
            nvmlDeviceSetPowerManagementLimit(device, original_power_limit);
            std::cout << "[TensorSafety] Hardware power limit restored to " << (original_power_limit / 1000) << " W" << std::endl;
        }
        power_limit_locked = false;
    }
    nvmlShutdown();
}

void GpuTensorStressor::stress_loop(double target_percent) {
    cudaSetDevice(gpu_index);
    cudaStream_t stream;
    cudaStreamCreate(&stream);

    // 내부 상한선: 텐서 코어는 30% Duty Cycle만으로도 시스템 전체를 풀로드 시킬 수 있음
    if (target_percent > 30.0) target_percent = 30.0;
    
    // 점진적 부하(Ramp-up): 1%부터 시작
    double current_duty = 1.0;
    auto ramp_start = std::chrono::steady_clock::now();

    // 주기: 10ms (10,000 마이크로초)
    const int period_us = 10000; 

    while (keep_running) {
        auto now = std::chrono::steady_clock::now();
        std::chrono::duration<double> elapsed = now - ramp_start;
        
        // 5초에 걸쳐 선형 Ramp-up
        if (elapsed.count() < 5.0) {
            current_duty = 1.0 + (target_percent - 1.0) * (elapsed.count() / 5.0);
        } else {
            current_duty = target_percent;
        }

        int active_us = (current_duty / 100.0) * period_us;
        int sleep_us = period_us - active_us;

        // 커널 런치 (Block: 128 (4 warps), Grid: SM개수 * 4)
        int num_sms;
        cudaDeviceGetAttribute(&num_sms, cudaDevAttrMultiProcessorCount, gpu_index);
        
        if (active_us > 0) {
            // iterations를 조절하여 대략적인 active_us를 맞춥니다.
            tensor_stress_kernel<<<num_sms * 4, 128, 0, stream>>>(500);
            cudaStreamSynchronize(stream); // 커널 실행 종료까지 동기화 (Sleep 오차 극복)
        }

        if (sleep_us > 0) {
            // CPU Spin-wait 또는 OS Sleep (마이크로초 단위)
            std::this_thread::sleep_for(std::chrono::microseconds(sleep_us));
        }
    }

    cudaStreamDestroy(stream);
}

bool GpuTensorStressor::start_percent(double percent) {
    if (keep_running) return false;
    
    lock_hardware_power_limit();

    keep_running = true;
    stress_thread = std::thread(&GpuTensorStressor::stress_loop, this, percent);
    return true;
}

void GpuTensorStressor::stop() {
    if (keep_running) {
        keep_running = false;
        if (stress_thread.joinable()) {
            stress_thread.join();
        }
        restore_hardware_power_limit();
    }
}
