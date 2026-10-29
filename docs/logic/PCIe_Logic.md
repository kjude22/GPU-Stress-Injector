# GPU PCIe 대역폭 부하 모듈 상세 로직

이 문서는 사용자가 지정한 **목표 대역폭 비율(%)**을 맞추기 위해, C++/CUDA 단에서 PCIe 부하 모듈(`gpu_pcie.cu`)이 어떻게 동작하는지 그 핵심 제어 로직을 친절하게 설명합니다.

---

## 1. 전송 속도의 한계 돌파: Pinned Memory (Page-locked)

CPU와 GPU 사이의 데이터 통로인 PCIe 대역폭을 100% 한계까지 끌어다 쓰려면 일반적인 방식으로는 부족합니다. 
일반적인 CPU 메모리(`malloc`으로 할당)를 쓰면, 운영체제가 언제든 메모리를 디스크로 스왑(Swap)할 수 있어서 CUDA 드라이버가 안전을 위해 임시 버퍼를 한 번 더 거치게 됩니다. 이 과정에서 엄청난 속도 저하(오버헤드)가 발생합니다.

### 💡 해결책: 페이징을 막아버리는 `cudaMallocHost`
이를 해결하기 위해 운영체제가 절대 건드리지 못하도록 메모리를 꽉 잠가버리는 **Pinned Memory(Page-locked Memory)**를 사용합니다. 이렇게 하면 GPU가 CPU 메모리에 직접(Direct) 접근할 수 있어 고속도로가 뚫리게 됩니다.

```cpp
// 꽉 잠긴(Pinned) 호스트(CPU) 메모리 할당
void* host_buffer;
cudaMallocHost(&host_buffer, buffer_size);
```

## 2. 끊김 없는 데이터 쏟아붓기: 비동기 단방향 전송 (H2D)

메모리를 복사하는 동안 CPU가 멈춰서 기다리면(동기식) 효율이 떨어집니다. 따라서 "GPU야, 이 데이터 가져가!" 라고 명령만 던져놓고 CPU는 바로 다음 일을 할 수 있도록 **비동기(Asynchronous)** 함수인 `cudaMemcpyAsync`를 사용합니다.

우리의 구현은 명확한 부하 측정을 위해 **호스트에서 디바이스 방향(H2D, Host-to-Device)** 으로만 단방향 전송을 쏟아붓도록 설계되어 있습니다.

```cpp
cudaStream_t stream_h2d;
cudaStreamCreate(&stream_h2d);

// 단방향(H2D) 비동기 전송
cudaMemcpyAsync(device_buffer, host_buffer, bytes_to_send, cudaMemcpyHostToDevice, stream_h2d);
```

## 3. 핵심: 목표치 스로틀링(Throttling) 제어 로직

목표 비율이 50%인데 무작정 반복문(While)을 돌리면 PCIe 대역폭이 100%까지 꽉 차버립니다. 따라서 **특정 주기(Cycle)**마다 전송량을 정해두고, 너무 빨리 전송했으면 남은 시간 동안 강제로 쉬게 만드는 **스로틀링(Throttling)** 기법을 씁니다.

### 🕒 제어 주기 예시 (100ms 기준)
PCIe 최대 대역폭을 16,000 MB/s라고 가정해 보겠습니다. 50% 부하를 주고 싶다면 1초에 8,000 MB를 보내야 합니다.
100ms(0.1초)를 주기로 잡으면, **0.1초마다 800 MB씩만 전송**하면 됩니다.

1. **전송 단계 (Active Phase)**: 800 MB를 비동기로 전송하라고 명령합니다.
2. **측정 및 휴식 단계 (Sleep Phase)**: 전송이 끝나는 데 걸린 시간을 잽니다 (예: 25ms 소요).
3. 남은 시간(75ms) 동안은 `std::this_thread::sleep_for`를 통해 CPU를 재웁니다. 
   - CPU를 재우기 때문에 **CPU 점유율(오버헤드) 낭비 없이 완벽하게 PCIe 라인만 혹사**시킬 수 있습니다!

### 💻 의사 코드 (Pseudo Code)

```cpp
double cycle_time_sec = 0.1; // 100ms 주기
size_t bytes_per_cycle = 800_MB; 

while (!stop_signal) {
    auto start_time = current_time();

    // 1. 800 MB 데이터 비동기 전송 및 대기
    cudaMemcpyAsync(device_buffer, host_buffer, bytes_per_cycle, cudaMemcpyHostToDevice, stream_h2d);
    cudaStreamSynchronize(stream_h2d);

    // 2. 걸린 시간 측정
    double elapsed_sec = current_time() - start_time;

    // 3. 목표 주기(100ms)에서 남은 시간만큼 스로틀링 (Sleep)
    double sleep_time_sec = cycle_time_sec - elapsed_sec;
    if (sleep_time_sec > 0) {
        std::this_thread::sleep_for(sleep_time_sec);
    }
}
```

## 🎯 요약
PCIe 부하 로직의 핵심은 **"Pinned Memory로 전송 속도 한계를 풀고, 짧은 주기(100ms)마다 할당량만 전송한 뒤, 남은 시간은 깔끔하게 CPU를 재워(Sleep) 목표 대역폭을 맞춘다!"** 입니다.
