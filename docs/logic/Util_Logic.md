# GPU 연산(Utilization) 부하 모듈 상세 로직

이 문서는 사용자가 지정한 **목표 코어 이용률(%)**을 맞추기 위해, C++/CUDA 단에서 GPU 연산(Util) 부하 모듈이 어떻게 동작하는지 그 핵심 제어 로직을 간단히 설명합니다.

---

## 1. 부하 생성의 핵심: 무거운 수학 연산 (GEMM)

GPU의 핵심 계산 유닛(SM, Streaming Multiprocessor)을 바쁘게 만들기 위해서는 매우 무거운 병렬 수학 연산을 시켜야 합니다. 이를 위해 주로 NVIDIA의 수학 라이브러리인 **cuBLAS**를 활용하여 대규모 **행렬 곱셈(GEMM, General Matrix Multiply)**을 반복적으로 수행합니다.

이 커널 연산이 실행되는 동안 GPU의 Core Utilization은 일시적으로 100%까지 치솟게 됩니다.

## 2. 목표치 맞추기: 듀티 사이클(Duty Cycle) 제어

목표 이용률이 60%인데 무작정 연산을 돌리면 100%가 되어버립니다. 따라서 1초를 아주 잘게 쪼개어 **'연산하는 시간(Active Phase)'**과 **'아무것도 안 하고 쉬는 시간(Sleep Phase)'**의 비율을 조절합니다. 

이 방식을 **듀티 사이클(Duty Cycle)** 제어라고 합니다.

### 🕒 제어 주기 예시 (100ms 기준)
100ms(0.1초)를 하나의 주기로 삼고, 목표치가 **60%** 라면 다음과 같이 행동합니다.

1. **Active Phase (60ms)**:
   - 60ms 동안 행렬 곱셈 연산(커널)을 미친 듯이 반복해서 GPU를 100%로 혹사시킵니다.
2. **Sleep Phase (40ms)**:
   - 남은 40ms 동안은 `std::this_thread::sleep_for`를 호출해 CPU와 GPU 모두 얌전히 대기합니다.

이 100ms 주기를 1초에 10번 반복하면, 평균적으로 그 1초 동안의 GPU 이용률(Utilization)은 약 60%로 측정되게 됩니다.

### 💻 의사 코드 (Pseudo Code)

```cpp
double target_percent = 60.0; // 60%
double cycle_time_ms = 100.0; // 100ms 주기

// 연산을 해야 할 시간 계산 (60ms)
double active_time_ms = cycle_time_ms * (target_percent / 100.0);
// 쉬어야 할 시간 계산 (40ms)
double sleep_time_ms = cycle_time_ms - active_time_ms;

while (!stop_signal) {
    auto start_time = std::chrono::high_resolution_clock::now();

    // 1. Active Phase: 정해진 시간(60ms) 동안 연산 커널 무한 반복
    while (elapsed_time < active_time_ms) {
        cuBLAS_GEMM_kernel(); // 행렬 곱셈 실행
        cudaDeviceSynchronize(); // 완료 대기
        elapsed_time = current_time - start_time;
    }

    // 2. Sleep Phase: 남은 시간(40ms) 동안 강제 대기(스로틀링)
    if (sleep_time_ms > 0) {
        std::this_thread::sleep_for(std::chrono::milliseconds(static_cast<int>(sleep_time_ms)));
    }
}
```

### ⚠️ 왜 하필 100ms로 짧게 쪼개는가? (모니터링 에일리어싱 방지)

DCGM Exporter나 `nvidia-smi` 같은 모니터링 도구는 찰나의 순간이 아니라 **1/6초 ~ 1초 단위의 '과거 평균값(Integral)'**을 수집하여 보여줍니다.
- 만약 제어 주기를 아주 길게 잡아 **10초**(예: 6초 연산, 4초 휴식)로 설정했다면, 모니터링 시스템은 특정 순간에는 100%, 특정 순간에는 0%로 측정하여 그래프가 크게 요동치는 **에일리어싱(Aliasing) 현상**을 겪게 됩니다.
- 하지만 우리의 제어 주기는 **100ms(0.1초)**로 매우 짧습니다. 이는 모니터링 도구의 수집 주기나 NVIDIA 드라이버 내부의 롤링 평균화 주기(약 166ms)보다 짧습니다. 
- 따라서 DCGM이 어느 시점에 값을 요청하더라도 그 1초라는 창(Window) 안에는 연산과 휴식이 우리가 의도한 비율(예: 60:40)대로 완벽히 섞여 들어가게 됩니다. 그 결과, 0%나 100%로 수치가 튀는 현상 없이 **매끄럽고 안정적인 60%라는 평균 부하량**만을 관측할 수 있게 됩니다.

## 3. 동적 피드백 보정 (NVML)

GPU의 연산 속도나 스케줄링 차이 때문에 위 공식처럼 딱 맞아떨어지지 않고, 목표는 60%인데 실제(nvidia-smi 기준)로는 50%나 70%가 나올 수도 있습니다.

이를 해결하기 위해, 백그라운드에서 **NVML 라이브러리**를 사용해 1초마다 진짜 현재 이용률을 읽어옵니다.
- **실제 이용률 < 목표 이용률**: 다음 주기의 `active_time_ms`를 조금 늘립니다.
- **실제 이용률 > 목표 이용률**: 다음 주기의 `active_time_ms`를 조금 줄입니다.

이러한 피드백 루프를 통해 프로그램은 빠르고 안정적으로 사용자가 지정한 정확한 %에 수렴하게 됩니다.
