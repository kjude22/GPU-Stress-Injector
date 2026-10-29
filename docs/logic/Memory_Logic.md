# GPU 메모리(VRAM) 부하 모듈 상세 로직

이 문서는 사용자가 지정한 **목표 메모리 점유율(%)**을 맞추기 위해, C++/CUDA 단에서 GPU 메모리 부하 모듈(`gpu_memory.cu`)이 어떻게 동작하는지 그 핵심 제어 로직을 친절하게 설명합니다.

---

## 1. 부하 생성의 핵심: VRAM 할당과 초기화 (Lazy Allocation 방지)

GPU의 VRAM(비디오 메모리)을 차지하기 위해 가장 먼저 해야 할 일은 메모리를 할당하는 것입니다. CUDA에서는 이를 위해 `cudaMalloc` 함수를 사용합니다.

### ⚠️ 주의할 점: 지연 할당 (Lazy Allocation)
운영체제와 드라이버는 매우 똑똑해서, `cudaMalloc`으로 메모리 공간만 예약해 두고 실제로 데이터를 쓰지 않으면 물리적인 VRAM을 즉시 점유하지 않는 경우가 있습니다. 이를 **지연 할당(Lazy Allocation)**이라고 부릅니다. 
이 상태에서는 `nvidia-smi`를 켜봐도 메모리 사용량이 늘어나지 않은 것처럼 보일 수 있습니다.

### 💡 해결책: 더미 데이터 덮어쓰기 (`cudaMemset`)
이를 방지하고 확실하게 물리적 메모리를 점유(Lock-in)하기 위해, 할당 직후에 `cudaMemset`을 사용하여 예약된 공간 전체에 의미 없는 더미 데이터(예: 숫자 `1`)를 꽉꽉 채워 넣습니다.

```cpp
// 1. 메모리 공간 예약
float* device_buffer;
cudaMalloc(&device_buffer, bytes_to_allocate);

// 2. 예약된 공간에 실제로 데이터를 써서 물리 메모리 점유 확정 (Lazy Allocation 방지)
cudaMemset(device_buffer, 1, bytes_to_allocate);
```

## 2. 목표치 맞추기: 동적 할당량 계산

사용자는 바이트(Byte) 단위가 아니라 "전체 메모리의 50%를 점유해 줘"라고 퍼센트(%) 단위로 요청합니다. 이를 위해 현재 GPU가 가진 전체 VRAM 용량을 먼저 알아내야 합니다.

```cpp
double target_percent = 50.0; // 50%

// 1. GPU의 현재 메모리 상태 조회
size_t free_byte;
size_t total_byte;
cudaMemGetInfo(&free_byte, &total_byte);

// 2. 할당해야 할 바이트(Byte) 수 계산
size_t bytes_to_allocate = static_cast<size_t>(total_byte * (target_percent / 100.0));
```

## 3. 메모리 해제 (Graceful Release)

테스트가 끝났거나, 사용자가 종료 요청을 보내면 점유했던 VRAM을 즉시 반환해야 다른 정상적인 애플리케이션들이 GPU를 사용할 수 있습니다. `cudaFree`를 통해 깔끔하게 메모리를 비워줍니다.

```cpp
// 점유했던 메모리 해제
if (device_buffer != nullptr) {
    cudaFree(device_buffer);
    device_buffer = nullptr;
}
```

## 🎯 요약
GPU 메모리 부하 로직은 아주 직관적입니다. **"원하는 퍼센트만큼 용량을 계산(`cudaMemGetInfo`)하고, 할당(`cudaMalloc`)한 뒤, 가짜 데이터를 채워 넣어(`cudaMemset`) 꼼수를 막는다!"** 이것이 메모리 스트레스 인젝션의 핵심입니다.
