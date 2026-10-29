# [GPU-Stress-Injector] 다중 벡터 연쇄 부하(YAML 시나리오) 구현 계획

## 1. 개요 및 목표 (Goal)
기존의 단일 부하 주입 방식을 뛰어넘어, 시간에 따라 여러 종류의 부하(Memory, Util, PCIe, Tensor 등)를 순차적으로 혹은 복합적으로 주입할 수 있는 **워크플로우 엔진(Workflow Engine)**을 도입합니다.
클라우드 네이티브 생태계(Kubernetes)와의 완벽한 호환성 및 뛰어난 가독성을 확보하기 위해, 사용자의 복잡한 시나리오 입력을 **YAML 파일 기반**으로 처리하는 것을 목표로 합니다.

## 2. 주요 설계 원칙 (Design Principles)
- **Infrastructure as Code (IaC) 친화적 (ConfigMap 연동):** 쿠버네티스의 `ConfigMap`에 YAML 시나리오 텍스트를 주입하여 Pod 내부에 파일로 마운트합니다. **(중요: 쿠버네티스가 자체적으로 이 커스텀 YAML 스키마를 해석하는 것이 아닙니다. 쿠버네티스는 단지 파일을 전달하는 역할만 수행하며, 실제 `sequence` 등의 내용 해석은 컨테이너 내부의 C++ 프로그램이 직접 수행합니다.)**
- **의존성 최소화 및 경량 파서 적용:** 전달받은 YAML 파일을 읽고 해석하기 위해, C++ 환경에서 안정적으로 검증된 경량 라이브러리인 `yaml-cpp`를 도입하여 파싱을 수행합니다.
- **Graceful Transition (우아한 전환):** Step 1(예: Memory)에서 Step 2(예: Util)로 넘어갈 때, 기존에 점유했던 자원(VRAM 할당, 스레드 등)을 깔끔하게 해제(Teardown)하고 다음 모듈을 가동하는 상태 머신(State Machine) 구조를 적용합니다.
- **스키마 검증(Validation):** 사용자가 YAML에 오타를 내거나 잘못된 수치(예: percent: 200)를 입력했을 경우, 런타임 중간에 터지지 않도록 파싱 단계에서 미리 검증(Fail-Fast)합니다.

## 3. 코드 변경 사항 (Proposed Changes)

### 3.1. 신규 파일 및 디렉토리 생성
#### [NEW DIRECTORY] `scenarios/`
- 사용자가 즉시 테스트해볼 수 있는 기본 템플릿 파일들을 제공합니다.
- `scenarios/ai_workload_spike.yaml`, `scenarios/memory_leak_to_crash.yaml` 등.

#### [NEW] `src/yaml_parser.h` & `src/yaml_parser.cpp`
- `yaml-cpp` 라이브러리를 활용하여 YAML 파일을 읽고, 내부 C++ 구조체(`std::vector<StressStep>`)로 변환하는 파서 모듈.
- 필수 키(Key) 누락, 지원하지 않는 type, 제한선을 초과한 percent 값 등을 검사하는 예외 처리(Validation) 로직 포함.

#### [NEW] `src/workflow_engine.h` & `src/workflow_engine.cpp`
- 파싱된 `StressStep` 배열을 순서대로 실행하는 메인 러너(Runner).
- 각 스텝마다 적절한 모듈(예: `GpuMemoryStressor`, `GpuUtilStressor`)의 인스턴스를 생성해 가동하고, `duration` 타이머가 끝나면 `stop()`을 호출해 안전하게 메모리와 스레드를 정리하는 역할.

### 3.2. 기존 코드 수정
#### [MODIFY] `src/main.cpp`
- 명령어 실행 인자 파싱 부분에 `--scenario <yaml_file_path>` 옵션 추가.
- 프로그램이 `--scenario` 모드로 실행될 경우, 기존의 단일 모듈 실행 로직 대신 `WorkflowEngine::Run()`을 호출하도록 분기 처리.

#### [MODIFY] `Makefile`
- `yaml_parser.cpp`, `workflow_engine.cpp` 빌드 규칙 추가.
- `yaml-cpp` 라이브러리 링킹을 위한 플래그(`-lyaml-cpp`) 추가.

#### [MODIFY] `kubernetes/gpu-stress-job.yaml`
- 쿠버네티스 배포 예시에 `ConfigMap`을 생성하여 시나리오 YAML을 컨테이너 내부에 볼륨 마운트(Volume Mount)하고, `--scenario` 인자로 실행하는 템플릿으로 업데이트.

#### [MODIFY] `README.md` & `User_Guide.md`
- "YAML 시나리오 기능" 가이드 추가 및 `yaml-cpp` 의존성 설치 안내(`sudo apt-get install libyaml-cpp-dev`) 명시.

## 4. 검증 계획 (Verification Plan)
1. **스키마 예외 테스트:** `duration`이 없는 YAML, 오타가 있는 YAML을 입력했을 때, 부하 주입 시작 전에 즉시 에러 메세지를 뿜고 안전하게 종료(Fail-Fast)되는지 확인.
2. **트랜지션(Transition) 안정성 검증:** 
   - `Memory 80%` (1분) -> `Util 90%` (1분) 시나리오 실행 시.
   - 1분이 끝나는 시점에 DCGM 지표상 VRAM 사용량이 0으로 뚝 떨어짐과 동시에, CUDA Core 점유율이 90%로 치솟는 즉각적인(Gapless) 전환이 정상적으로 이루어지는지 Grafana를 통해 확인.
3. **메모리 누수 검사:** 워크플로우 엔진이 각 스텝을 교체할 때마다 C++ 내부 메모리 릭(Leak)이나 좀비 스레드가 남지 않는지 `Valgrind`나 `htop`을 통해 장기 테스트 진행.
