# GPU Fault Injector (GPU 자원 부하 제어 프레임워크)

이 프로젝트는 클라우드 네이티브(Kubernetes, Docker) 및 로컬 환경에서 GPU 자원에 인위적인 부하(Fault)를 주입하여, 시스템의 모니터링 체계와 이상 탐지(Anomaly Detection) 모델이 올바르게 작동하는지 검증하기 위한 장애 주입(Fault Injection) 도구입니다.

---

## 📁 디렉토리 구조 (Directory Structure)

전체 프로젝트는 유지보수 및 확장이 용이하도록 객체 지향적인 C++/CUDA 모듈 단위로 구성되어 있습니다.

```text
gpu-stress-injector/
├── 📄 README.md                 # 본 문서 (프로젝트 개요 및 디렉토리 안내)
├── 📄 User_Guide.md             # 💡 사용법, 파라미터 옵션, 실행 예시가 담긴 상세 가이드 문서
├── 📄 Makefile                  # 소스 코드를 빌드(컴파일)하기 위한 Make 스크립트
├── 📄 Dockerfile                # 컨테이너 환경으로 배포하기 위한 Docker 빌드 파일
├── 📄 .gitignore                # Git 추적 제외 대상 설정
├── 📂 kubernetes/               # Kubernetes(k8s, kind) 배포용 매니페스트 폴더
│   └── gpu-stress-job.yaml      # Kubernetes Job을 통해 부하를 주입하기 위한 설정 파일
├── 📂 scenarios/                # YAML 기반 워크플로우 시나리오 파일 모음
│   ├── ai_workload_spike.yaml   # AI 배치 처리 시뮬레이션 시나리오
│   └── memory_leak_to_crash.yaml# 메모리 누수 → 텐서 코어 스파이크 시나리오
├── 📂 docs/                     # 설계 문서 및 구현 계획서
└── 📂 src/                      # 부하 주입기 핵심 소스 코드 (C++ / CUDA)
    ├── main.cpp                 # 프로그램 진입점 (인자 파싱, 메뉴 제공, 안전 모니터링 루프 통합)
    ├── gpu_metrics.h / .cpp     # NVML 기반 GPU 모니터링 래퍼 (안전 장치용 현재 전력/온도 측정)
    ├── gpu_memory.h / .cu       # [모듈] VRAM 할당 부하 (Memory Stress)
    ├── gpu_util.h / .cu         # [모듈] CUDA 코어 연산 부하 (Core Util Stress)
    ├── gpu_pcie.h / .cu         # [모듈] Host-to-Device 데이터 복사 부하 (PCIe Bandwidth Stress)
    ├── gpu_power.h / .cu        # [모듈] 전력 소모 부하 (Power Stress - Duty Cycle 피드백 제어)
    ├── gpu_thermal.h / .cu      # [모듈] 온도 상승 부하 (Thermal Stress - 기판 발원지 분산 유도)
    ├── gpu_tensor.h / .cu       # [모듈] 텐서 코어 부하 (Tensor Core Stress - WMMA 기반)
    ├── yaml_parser.h / .cpp     # YAML 시나리오 파일 파서 (yaml-cpp 기반)
    └── workflow_engine.h / .cpp # 시나리오 순차 실행 엔진 (WorkflowEngine)
```

---

## 🛠 주요 특징 (Key Features)

1. **6가지 모듈식 부하 주입 (Multi-Vector Stress)**:  
   Memory, Core Util, PCIe Bandwidth, Power, Thermal, **Tensor Core** 등 다양한 방식의 하드웨어 스트레스를 목적에 맞게 개별적으로 주입할 수 있습니다.
2. **YAML 기반 워크플로우 시나리오 실행**:  
   `--scenario` 플래그로 YAML 시나리오 파일을 지정하면, 여러 부하를 **순차적으로 자동 실행**하여 복합 장애 상황을 재현할 수 있습니다.
3. **엄격한 하드웨어 보호 (Built-in Safety Limits)**:
   - 시스템 전체가 마비(Hang)되는 것을 방지하기 위해 각 소스 코드 내부에 **최대 상한선**(Memory 20%, Util 50%, PCIe 25%, Power 60%, Thermal 65°C, Tensor 30%)이 하드코딩되어 있습니다. 사용자가 더 높은 값을 입력하더라도 이 상한선을 넘지 않습니다.
   - 런타임 중 온도가 75°C를 초과할 경우 즉시 커널을 중지하고 프로그램을 종료하는 **Kill-Switch**가 `main.cpp`에 탑재되어 있습니다.
4. **클라우드 네이티브 친화적 배포**:  
   제공되는 `Dockerfile`을 통해 이미지를 생성한 뒤, `kubernetes/` 매니페스트를 이용해 즉시 `kind`나 `k8s` 클러스터의 Pod/Job 형태로 띄워 분산 모니터링 환경을 테스트할 수 있습니다.

---

## 📦 의존성 (Dependencies)

| 항목 | 최소 버전 | 설치 방법 (Ubuntu) |
| :--- | :--- | :--- |
| NVIDIA GPU Driver | - | `apt-get install nvidia-driver-XXX` |
| CUDA Toolkit | 11.0+ (WMMA 지원) | [NVIDIA CUDA Downloads](https://developer.nvidia.com/cuda-downloads) |
| `g++` | C++17 지원 | `apt-get install g++` |
| `make` | - | `apt-get install make` |
| `yaml-cpp` | 0.6+ | `apt-get install libyaml-cpp-dev` |
| NVML (libnvidia-ml) | - | CUDA Toolkit 또는 드라이버에 포함 |

---

## 📖 시작하기 (Getting Started)

프로그램의 구체적인 빌드(Make) 방법, 실행 파라미터 옵션(`--type`, `--percent`, `--duration`, `--scenario` 등), 모드별 상세 동작 원리와 Grafana 확인 지표에 대해서는 반드시 **[User_Guide.md](./User_Guide.md)** 문서를 참고해 주시기 바랍니다.
