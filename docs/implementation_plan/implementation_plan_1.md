# GPU Stress Injector 전체 구현 계획서 (Full Implementation Plan)

본 문서는 메모리 부하, **GPU 연산(Utilization)**, **PCIe 대역폭(목표치 제어)**, **전력/온도 안전 제어**, 그리고 **Go(Kubebuilder) 기반 Kubernetes Controller 연동**까지 포함하는 전체 GPU Stress Injector 프레임워크에 대한 상세 구현 계획입니다.

---

## 🎯 목표 (Goal Description)
Kubernetes(및 kind) 환경에서 특정 노드의 GPU를 할당받아, 사용자가 원하는 수준의 **GPU 메모리**, **GPU 연산량(이용률)**, **PCIe 대역폭(목표 대역폭 제어)** 부하를 발생시키고 유지할 수 있는 완전한 프레임워크를 구축합니다. 과도한 부하로 인한 하드웨어 손상을 막기 위해 전력과 온도 제한을 설정하고 실시간으로 피드백 제어를 수행합니다.

## 사용자 검토 필요 (User Review Required)

> [!IMPORTANT]
> 설계 방향이 사용자님의 피드백(PCIe 목표치 제어, Go 기반 컨트롤러)을 반영하여 최종 확정되었습니다.
> 본 계획서의 내용을 마지막으로 검토하신 후 승인해 주시면, 바로 **연산 부하(Compute) 및 PCIe 부하 주입 모듈**부터 실제 C++/CUDA 코드 작성을 시작하겠습니다.

---

## 🏗 전체 아키텍처 및 제안하는 변경 사항

크게 두 가지 컴포넌트로 나뉩니다.
1. **Core Stressor (`C++/CUDA`)**: 실제 GPU 부하를 생성하고 세밀하게 조절하는 핵심 바이너리
2. **Kubernetes Operator (`Go / Kubebuilder`)**: `GPUStress` CRD를 정의하고 스트레스 Job을 관리하는 컨트롤러

---

### 1부: Core Stressor 상세 설계 (C++/CUDA)

`gpu-stress-injector/src` 폴더 내에 기능별로 모듈화하여 구현합니다.

#### 1. 메모리 부하 모듈 (`gpu_memory.cu`) [✅ 1단계 완료됨]
- **기능**: `--memory-percent` 에 맞춰 VRAM 할당 (`cudaMalloc`, `cudaMemset`).
- **확장**: 할당된 메모리를 PCIe 모듈이나 Compute 모듈에서 활용할 수 있도록 버퍼 포인터 공유 기능 추가.

#### 2. 연산 부하 모듈 (`gpu_compute.cu`)
- **기능**: `--target-util` (예: 80%)에 맞춰 GPU의 연산 유닛(SM)에 부하를 발생.
- **방식**: `cuBLAS`를 이용한 대규모 행렬 곱셈(GEMM) 커널 반복 실행.
- **제어 로직**: 
  - `active_time`과 `sleep_time`을 나누어 Duty Cycle을 구성.
  - NVML을 통해 현재 이용률을 읽어와서 목표 이용률과 비교한 뒤(피드백), 오차(Error)에 따라 Duty Cycle을 동적으로 늘리거나 줄이는 제어(PI Control) 적용.

#### 3. PCIe 대역폭 부하 모듈 (`gpu_pcie.cu`) [✨ 업데이트됨]
- **기능**: `--target-pcie-mbps` 에 맞춰 호스트(CPU)와 디바이스(GPU) 간의 데이터 전송 대역폭을 제어하며 부하를 발생.
- **방식**: 
  - `cudaMallocHost`를 통해 Page-locked (Pinned) 메모리 할당 (전송 속도 극대화).
  - CUDA Stream을 분리하여 `cudaMemcpyAsync` (Host To Device, Device To Host) 양방향 전송.
- **제어 로직 (목표치 제어)**:
  - 1초(또는 특정 단위 시간) 동안 전송한 총 바이트 수를 측정.
  - 전송 속도가 목표치(MB/s)를 초과하려고 하면, 미세한 `sleep`을 주입하여(Throttling) 목표 대역폭 근처를 유지하도록 능동적으로 제어.

#### 4. 상태 모니터링 및 안전 제어 모듈 (`gpu_metrics.cpp`, `controller.cpp`)
- **기능**: NVML(NVIDIA Management Library) API를 연동하여 GPU의 실시간 상태 조회 및 제어.
- **조회 항목**: GPU 이용률, 전력(Power), 온도(Temperature).
- **안전 제한 (Safety Limits)**:
  - `--max-power 250 --max-temperature 80` 와 같이 상한선을 인자로 받음.
  - 모니터링 루프에서 전력이나 온도가 제한을 초과하면 **부하를 강제로 낮추거나 프로그램을 즉시 안전 종료(Graceful Shutdown)**시킴.

---

### 2부: Kubernetes CRD & Controller 설계 [✨ Go(Kubebuilder) 확정]

Kubebuilder 프레임워크를 사용하여 안정적이고 표준화된 Operator를 개발합니다.

#### 1. Custom Resource Definition (CRD) 설계
```yaml
apiVersion: chaos.example.io/v1alpha1
kind: GPUStress
metadata:
  name: gpu-stress-scenario-1
spec:
  selector:
    nodeNames:
      - gpu-worker-1      # 대상 노드
  target:
    utilization: 80       # 연산 목표 80%
    memoryPercent: 60     # 메모리 점유 60%
    pcieBandwidthMBps: 4000 # PCIe 대역폭 목표 4000 MB/s
  limits:
    maxPowerWatts: 250    # 전력 제한 250W
    maxTemperatureCelsius: 80 # 온도 제한 80도
  duration: 5m            # 유지 시간 5분
```

#### 2. Controller 로직 (Go)
- 클러스터 내에 `GPUStress` 리소스가 생성(Create/Update)되는 것을 Reconcile 루프에서 감지.
- `spec.selector`에 맞는 노드를 찾아 해당 노드에 C++ 스트레서 바이너리를 구동하는 `Job`을 동적으로 생성.
- 주기적으로 Job의 상태를 체크하여 `GPUStress.status`에 현재 상태(진행 중, 안전 종료됨, 완료됨)를 업데이트.
- `duration` 만료 시 또는 리소스 삭제 시 Job 정리(Garbage Collection).

---

## 🧪 검증 계획 (Verification Plan)

### 1단계: 바이너리 단독 검증
1. 로컬(원격 서버) 환경에서 컴파일 후 `gpu-stressor --target-util 80 --target-pcie-mbps 4000 --max-temp 80` 실행.
2. `watch -n 1 nvidia-smi` 및 `dcgm-exporter`를 통해 GPU-Util이 80% 근처를 유지하고, PCIe Tx/Rx 대역폭이 4000MB/s 근처를 유지하는지 확인.
3. 온도가 80도에 도달했을 때 프로그램이 안전 장치에 의해 부하를 멈추는지 확인.

### 2단계: Kubernetes Operator 연동 검증
1. Kubebuilder로 생성한 Operator 배포 후 `GPUStress` CR 적용.
2. Prometheus/Grafana 대시보드에서 `DCGM_FI_DEV_GPU_UTIL`, `DCGM_FI_PROF_PCIE_TX_BYTES` 등의 메트릭이 정확히 타겟 수치로 오르는지 교차 검증.
