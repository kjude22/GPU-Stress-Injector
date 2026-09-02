TARGET := build/gpu-stressor
NVCC := nvcc
CXX := g++

CXXFLAGS := -std=c++17 -O2
NVCCFLAGS := -arch=sm_70
LDFLAGS := -lnvidia-ml

SOURCES := src/main.cpp src/gpu_memory.cu src/gpu_pcie.cu src/gpu_util.cu src/gpu_metrics.cpp src/gpu_power.cu src/gpu_thermal.cu src/gpu_tensor.cu

all:
	mkdir -p build
	$(NVCC) $(CXXFLAGS) $(NVCCFLAGS) $(SOURCES) -o $(TARGET) $(LDFLAGS)

clean:
	rm -rf build
