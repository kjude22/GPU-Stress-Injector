# Workflow Engine Logic (다중 벡터 연쇄 워크플로우 로직 설명)

이 문서는 사용자가 정의한 복잡한 시나리오(YAML)를 파싱하고, 시간의 흐름에 따라 GPU 스트레스 모듈들을 순차적으로 전환하며 실행하는 **워크플로우 엔진(Workflow Engine)**의 동작 원리를 설명합니다.

---

## 1. 아키텍처 원리 (Workflow Architecture)

기존의 방식은 `--type` 인자를 받아 한 가지 부하만을 지속하는 정적(Static) 테스트에 머물렀습니다. 하지만 실제 클라우드 인프라나 AI 애플리케이션 장애는 여러 자원 병목이 연쇄적으로 발생합니다. (예: PCIe 전송 폭주 → GPU 메모리 누수 → 연산 코어 과부하로 인한 다운).

워크플로우 엔진은 이러한 시계열적인 복합 부하 상황을 모사하기 위해 고안된 **상태 머신(State Machine)** 기반의 자동화 러너(Runner)입니다.

---

## 2. 파싱 및 제어 로직 (Parsing & State Machine)

### ① IaC (Infrastructure as Code) 친화적 파싱
사용자의 입력 방식이 복잡해지는 것을 막고자 **YAML 구조**를 채택했습니다. C++ 내부에서 `yaml-cpp` 라이브러리를 통해 이 파일을 읽어들입니다. 이 구조는 쿠버네티스의 `ConfigMap`을 통해 파일 자체를 컨테이너 안으로 주입(Mount)하는 데 완벽하게 호환됩니다.

### ② Fail-Fast 사전 검증 (Validation)
시나리오가 3시간짜리인데 2시간 50분 시점에 오타나 잘못된 타입(Type)으로 인해 프로그램이 터진다면 큰 손해입니다. 엔진은 실제 부하 주입을 시작하기 전에 YAML 스키마의 무결성(필수 키 누락, 존재하지 않는 부하 종류, 음수 등)을 한 번에 검증하여, 에러가 있다면 즉시 실행을 거부합니다.

### ③ 우아한 전환 (Graceful Teardown & Transition)
가장 중요한 핵심은 스텝 간의 매끄러운 전환입니다.
- **Teardown**: Step 1이 끝나면 현재 돌고 있는 스트레스 스레드(Thread)에 `stop()` 시그널을 보내 할당된 VRAM과 점유 중인 자원을 완전히 운영체제에 반환(Release)합니다.
- **Transition**: 이후 메모리 누수나 좀비 프로세스가 남지 않은 깨끗한 상태에서 곧바로 Step 2 모듈의 객체를 생성하여 부하를 다시 주입합니다. 이 전환 과정은 단 몇 밀리초(ms) 만에 갭(Gap) 없이 이루어집니다.

---

## 3. 이중 중앙 감시 장치 (Centralized Safety Watchdog)

각각의 단일 모듈 내부에 안전망이 존재하지만, 워크플로우 엔진은 전체 시나리오를 총괄하는 **마스터 감시 루프**를 가동합니다.
- 특정 스텝 진행 중, GPU 전체 온도가 75°C를 초과하거나 최대 전력(Max Power)을 돌파하면 해당 스텝뿐만 아니라 **예정된 이후의 모든 스텝(시나리오 전체)을 즉각 취소(Abort)**하고 프로그램을 긴급 종료합니다.

---

## 4. 사용 가이드 (Usage Guide)

먼저 사용자가 원하는 시계열 부하 패턴을 YAML 파일로 작성합니다. (예: `scenarios/my_test.yaml`)

```yaml
name: "My Workflow"
sequence:
  - step: 1
    type: pcie
    percent: 25
    duration: 30
  - step: 2
    type: tensor
    percent: 20
    duration: 60
```

작성이 완료되면 프로그램 실행 시 `--scenario` 인자에 해당 파일의 경로를 넘겨주면 워크플로우 엔진이 자동으로 이를 파싱하여 연속 실행합니다.

```bash
# YAML 시나리오 파일을 인자로 넘겨 자동 워크플로우 실행
sudo ./build/gpu-stressor --scenario scenarios/my_test.yaml
```
