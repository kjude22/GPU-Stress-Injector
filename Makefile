TARGET := build/gpu-stressor
NVCC := nvcc
CXX := g++

CXXFLAGS := -std=c++17 -O2
NVCCFLAGS := -arch=sm_70
LDFLAGS := -lnvidia-ml -lyaml-cpp

SOURCES := src/main.cpp src/gpu_memory.cu src/gpu_pcie.cu src/gpu_util.cu src/gpu_metrics.cpp src/gpu_power.cu src/gpu_thermal.cu src/gpu_tensor.cu src/yaml_parser.cpp src/workflow_engine.cpp

all:
	mkdir -p build
	$(NVCC) $(CXXFLAGS) $(NVCCFLAGS) $(SOURCES) -o $(TARGET) $(LDFLAGS)

clean:
	rm -rf build
