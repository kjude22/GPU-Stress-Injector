# [GPU-Stress-Injector] 텐서 코어(Tensor Core) 전용 스트레스 모듈 고도화 구현 계획

## 1. 개요 및 목표 (Goal)
기존 CUDA 코어(FP32/FP64) 기반의 `gpu_util` 모듈과 차별화되는, **텐서 코어(Tensor Core)** 전용 부하 주입 모듈을 추가합니다. 최신 AI 워크로드(LLM 추론/학습 등)와 가장 유사한 극한의 발열 및 전력 스파이크(Power Spike) 시나리오를 안전하게 모사하여, 이상 탐지 시스템 및 인프라 모니터링 체계를 고도화하는 것을 목표로 합니다.

## 2. 핵심 안전 장치 및 엣지 케이스 방어 설계 (Safety & Edge-Case Defenses)
이전 계획 대비 텐서 코어의 물리적 특성과 OS/드라이버의 한계를 고려하여 훨씬 방어적으로 설계되었습니다.

- **점진적 부하 증가 (Graceful Ramp-up):** 시작 시 1% Duty Cycle에서 출발하여 수 초간 선형적으로 부하를 증가시켜 파워서플라이(PSU)의 OCP(과전류 보호) 트리거를 방지합니다.
- **OS 스케줄러 한계 극복 (Busy-Wait & CUDA Event):** 일반적인 `std::this_thread::sleep_for`는 OS 틱(Tick)에 종속되어 10~15ms의 오차가 발생합니다. 텐서 코어를 마이크로초(µs) 단위로 정교하게 제어하기 위해, **CPU Spin-lock (Busy-wait)** 또는 **CUDA Event 동기화**를 활용하여 Duty Cycle 제어의 해상도를 극한으로 높입니다.
- **VRAM 고립 (Memory Isolation):** 외부 데이터 이동에 따른 병목과 추가 발열을 방지하기 위해, FP16 행렬 데이터를 L1(Shared Memory)과 레지스터에만 고정하고 무한 WMMA 연산을 수행합니다.
- **NVML 지연 시간(Latency) 보완:** NVML을 통한 전력/온도 폴링은 드라이버 단에서 10~100ms의 지연(Lag)이 발생할 수 있습니다. 소프트웨어 제어 루프가 늦게 반응하여 전력 튐(Spike)이 발생하는 것을 막기 위해, 프로그램 시작 시 `nvmlDeviceSetPowerManagementLimit` API를 호출하여 **하드웨어 수준의 Power Limit (예: TDP의 60~70%)**을 일시적으로 강제 설정하는 하드웨어 락(Lock)을 이중으로 겁니다.
- **펌웨어 스로틀링 충돌 방지:** 텐서 코어 가동 중 온도가 오르면 GPU 펌웨어가 자체적으로 코어 클럭(Clock)을 낮춥니다. 이때 제어 루프가 "목표 전력/부하가 안 나오네?"라고 착각하여 부하를 무리하게 더 밀어넣지 않도록, **현재 GPU Clock Speed를 읽어와서 피드백 루프의 가중치를 동적으로 하향 조정**합니다.
- **이중 안전망 (Kill-Switch & ΔT 감시):** 기존 75°C 절대 온도 상한선 외에, 1초당 온도 상승폭(ΔT/Δt)이 비정상적으로 가파를 경우 즉시 커널 실행을 차단하는 로직을 도입합니다.

## 3. 코드 변경 사항 (Proposed Changes)

### 3.1. 신규 파일 생성
#### [NEW] `src/gpu_tensor.h`
- 텐서 코어 부하를 추상화한 `GpuTensorStressor` 클래스 선언.
- 하드웨어 Power Limit 설정/복원 및 스레드 안전성(Thread-safety)을 보장하는 라이프사이클 관리.

#### [NEW] `src/gpu_tensor.cu`
- **WMMA 커널 구현:** `nvcuda::wmma` 네임스페이스를 활용하여 FP16 기반 16x16x16 행렬 곱셈-누산(MMA)을 쉼없이 수행하는 하드웨어 가속 커널(`tensor_stress_kernel`) 작성.
- **마이크로초 해상도 제어 루프:** OS 타이머 오차를 우회하기 위해 `cudaStreamSynchronize`와 고해상도 타이머(High-Resolution Clock) 기반 Spin-wait를 조합하여 타임 슬라이싱 정확도를 확보.

### 3.2. 기존 코드 수정
#### [MODIFY] `src/main.cpp`
- 터미널 인자 파싱에 `--type tensor` 옵션 추가.
- 대화형(Interactive) CLI 메뉴에 "6. Tensor Core Fault" 항목 추가.
- 프로그램 종료(또는 SIGINT/Ctrl+C) 시 **반드시 변경했던 하드웨어 Power Limit을 원래 상태로 복구(Rollback)**하는 클린업 로직 강화.
- 메인 모니터링 루프에 **온도 변화율(ΔT) 및 클럭 드롭(Clock Drop) 감지 알고리즘** 추가.

#### [MODIFY] `Makefile`
- `gpu_tensor.cu`를 빌드 목록에 포함.
- 텐서 코어 WMMA API 사용을 위해 최소 요구 아키텍처 컴파일 플래그(`-arch=sm_70` 이상) 추가.

#### [MODIFY] `README.md` & `User_Guide.md`
- 텐서 코어 부하 모듈의 원리 및 안전을 위해 프로그램 실행 시 `sudo` 권한(NVML Power Limit 제어용)이 권장된다는 점 명시.

## 4. 검증 계획 (Verification Plan)
- **DCGM 메트릭 확인:** 워크로드 실행 중 Grafana에서 `DCGM_FI_PROF_PIPE_TENSOR_ACTIVE` 지표가 타겟팅한 수치(%) 부근에 도달하는지 관찰.
- **제어 루프 정밀도 테스트:** OS 스케줄러 간섭 상태(백그라운드에서 CPU 100% 로드 발생)에서도 텐서 부하량이 요동치지 않고 일정한 Duty Cycle을 유지하는지 검증.
- **하드웨어 락(Lock) 검증:** NVML 모니터링 주기를 고의로 지연시켰을 때에도, 시작 시 걸어둔 Hardware Power Limit 덕분에 절대 전력 상한을 초과하지 않는지 확인.
- **이중 안전망 테스트:** 쿨링팬 속도를 외부에서 임의로 낮춘 후(발열 유도), 온도 급상승 기울기(ΔT) 방어 로직이 작동해 75°C 이전에 선제적으로 종료되는지 확인.
