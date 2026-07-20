# GPU Fault Injector 가이드 (User Guide)

GPU Fault Injector는 쿠버네티스 등 클라우드 네이티브 환경에서 GPU 기반 애플리케이션의 모니터링 및 이상 탐지(Anomaly Detection) 규칙이 제대로 동작하는지 검증하기 위한 도구입니다.

이 도구를 사용하면 손쉽게 **GPU 메모리 부족**, **GPU 코어 과부하**, **PCIe 병목 현상**, **전력 과부하**, **온도 상승(발열)** 등의 하드웨어 스트레스를 인위적으로 발생시킬 수 있습니다.

---

## ⚠️ 안전 가이드 (Safety Guidelines)

본 도구는 실제 하드웨어 자원을 극도로 소모시키는 장애 주입기입니다. 시스템 전체가 먹통이 되거나 하드웨어가 손상되는 것을 방지하기 위해 다음과 같은 **안전 상한선(Upper Limit) 및 Kill-Switch**가 공통으로 적용되어 있습니다.

- **안전 제한선 (Hard-coded Limits)**: 모듈별로 시스템 보호를 위한 최대 상한선이 하드코딩되어 있습니다 (Memory: 20%, Util: 50%, PCIe: 25%, Power: 60%, Thermal: 65°C). 사용자가 이보다 높은 수치를 입력하더라도 상한선으로 자동 조정됩니다.
- **온도 제어 (Kill-Switch)**: 모니터링 중 GPU 온도가 75°C 이상으로 치솟을 경우, 즉시 모든 부하 프로세스를 멈추고 프로그램을 안전하게 강제 종료합니다.
- **전력 제어**: 전력 스파이크를 방지하기 위해 배치(Batch) 사이즈와 커널 호출 주기를 보수적으로 제한하며, 목표 전력치 초과 시 스스로 연산을 쉬어갑니다(Sleep).

---

## 🛠 빌드 방법 (Build Instructions)

NVIDIA GPU와 CUDA Toolkit이 설치된 환경에서 아래 명령어를 실행하여 빌드합니다.

```bash
cd gpu-stress-injector
make clean
make
```

빌드가 완료되면 `build/gpu-stressor` 실행 파일이 생성됩니다.

---

## 🚀 사용 방법 및 인자 상세 (Usage & Arguments)

프로그램은 인자(Flag)를 통한 실행과 대화형(Interactive) 실행 두 가지를 지원합니다. Kubernetes `args` 설정이나 자동화 쉘 스크립트 작성 시에는 **인자(Flag) 기반 실행 방식**을 적극 권장합니다.

### 1. 기본 명령어 구조

```bash
./build/gpu-stressor --type <모듈_타입> --percent <목표수치> --duration <지속시간> [추가 옵션]
```

### 2. 전체 입력 인자(Flag) 설명 표

| 인자 (Flag) | 설명 | 예시 |
| :--- | :--- | :--- |
| `--type` | 주입할 장애(부하)의 종류를 지정합니다. (`memory`, `util`, `pcie`, `power`, `thermal`) | `--type power` |
| `--percent` | 각 모듈별 목표 수치를 지정합니다. (일반적으로 %, thermal 모드에서는 °C) | `--percent 70` |
| `--duration` | 부하를 지속할 시간입니다. (초 단위) | `--duration 60` |
| `--gpu-index` | (선택) 부하를 가할 대상 GPU의 인덱스 번호입니다. (기본값: 0) | `--gpu-index 0` |
| `--max-temp` | (선택) 공통 안전 옵션. 지정한 온도(°C) 도달 시 프로그램을 즉시 종료합니다. | `--max-temp 80` |
| `--max-power` | (선택) 공통 안전 옵션. 지정한 전력(W) 도달 시 프로그램을 즉시 종료합니다. | `--max-power 150` |

---

### 3. 모듈별 상세 설명 및 실행 예시

#### ① GPU 메모리 부하 (`--type memory`)
- **원리**: VRAM 공간을 인위적으로 할당하여 메모리 부족(OOM) 현상을 시뮬레이션합니다.
- `--percent`: 점유할 GPU 메모리의 비율 (%)
```bash
# 메모리를 80% 채우고 60초간 대기
./build/gpu-stressor --type memory --percent 80 --duration 60
```

#### ② GPU 코어 과부하 (`--type util`)
- **원리**: CUDA 코어(SM)에 끊임없는 부동소수점 연산을 쏟아부어 코어 점유율을 높입니다.
- `--percent`: 목표 GPU 코어 이용률 (%)
```bash
# GPU 코어 이용률을 90%로 300초(5분)간 유지
./build/gpu-stressor --type util --percent 90 --duration 300
```

#### ③ PCIe 병목 현상 (`--type pcie`)
- **원리**: 호스트(CPU/RAM)와 디바이스(GPU) 간 거대한 배열 데이터를 지속적으로 복사하여 대역폭을 포화시킵니다.
- `--percent`: 목표 PCIe 대역폭 점유율 (%)
```bash
# PCIe 대역폭을 50% 수준으로 120초간 점유
./build/gpu-stressor --type pcie --percent 50 --duration 120
```

#### ④ GPU 전력 부하 (`--type power`) (신규)
- **원리**: Duty Cycle 제어 방식을 통해 무거운 연산의 타이밍을 실시간으로 조율하여, GPU가 소모하는 전력량(W)을 타겟에 맞게 올립니다.
- `--percent`: GPU 전체 TDP(최대 전력) 대비 목표 전력 소모 비율 (%)
```bash
# GPU TDP의 70% 수준으로 전력을 소모하며 120초간 유지 (NVML 권한을 위해 sudo 권장)
sudo ./build/gpu-stressor --type power --percent 70 --duration 120
```

#### ⑤ GPU 온도 부하 (`--type thermal`) (신규)
- **원리**: 코어 연산과 대규모 VRAM 접근을 동시에 수행하여 기판 전체에 강력한 발열을 일으킨 뒤, 피드백 루프를 통해 목표 온도 근처에서 열을 유지합니다.
- `--percent`: **목표 유지 온도 (°C)** (주의: thermal 모드에서 percent 인자는 %가 아닌 섭씨 온도로 취급됩니다.)
```bash
# GPU 온도를 70°C로 끌어올리고 300초간 해당 온도를 안정적으로 유지
sudo ./build/gpu-stressor --type thermal --percent 70 --duration 300
```

---

### 4. 대화형(Interactive) 실행
터미널에서 아무런 인자 없이 `./build/gpu-stressor`를 실행하면 번호를 입력하여 직관적으로 모듈을 선택할 수 있는 메뉴가 나타납니다.

```bash
$ ./build/gpu-stressor
======================================
 GPU Fault Injector
======================================
1. GPU Memory Utilization Fault
2. GPU Core Utilization Fault
3. PCIe Bandwidth Fault
4. GPU Power Fault
5. GPU Thermal Fault
======================================
Select a fault type (1-5): 
```

---

## 📊 Grafana / DCGM 연동 확인 지표

Kubernetes(k8s) 등에 장애를 주입한 뒤, Grafana 모니터링 대시보드(DCGM Exporter 연동)에서 아래 지표들이 의도대로 치솟는지 관찰하여 모니터링 및 알람 시스템을 검증할 수 있습니다.

1. **Memory 모드**: `DCGM_FI_DEV_FB_USED` (프레임 버퍼 사용량 급증)
2. **Util 모드**: `DCGM_FI_DEV_GPU_UTIL` (GPU Utilization 점유율 상승)
3. **PCIe 모드**: `DCGM_FI_DEV_PCIE_TX_THROUGHPUT` / `DCGM_FI_DEV_PCIE_RX_THROUGHPUT` (PCIe 송수신 대역폭 피크 도달)
4. **Power 모드**: `DCGM_FI_DEV_POWER_USAGE` (전력 소모량 Watt 상승)
5. **Thermal 모드**: `DCGM_FI_DEV_GPU_TEMP` (GPU 온도 상승 및 평형 유지)
