#include "gpu_metrics.h"
#include <iostream>
#include <nvml.h>

GpuMetricReader::GpuMetricReader(int gpu_index)
    : gpu_index_(gpu_index), initialized_(false), nvml_device_(nullptr) {
    
    nvmlReturn_t result = nvmlInit();
    if (result != NVML_SUCCESS) {
        std::cerr << "Failed to initialize NVML: " << nvmlErrorString(result) << std::endl;
        return;
    }

    nvmlDevice_t device;
    result = nvmlDeviceGetHandleByIndex(gpu_index_, &device);
    if (result != NVML_SUCCESS) {
        std::cerr << "Failed to get device handle: " << nvmlErrorString(result) << std::endl;
        nvmlShutdown();
        return;
    }

    nvml_device_ = device;
    initialized_ = true;
}

GpuMetricReader::~GpuMetricReader() {
    if (initialized_) {
        nvmlShutdown();
    }
}

bool GpuMetricReader::read(GpuMetrics& metrics) {
    if (!initialized_ || !nvml_device_) return false;

    nvmlDevice_t device = static_cast<nvmlDevice_t>(nvml_device_);
    nvmlReturn_t result;

    // Temperature
    unsigned int temp = 0;
    result = nvmlDeviceGetTemperature(device, NVML_TEMPERATURE_GPU, &temp);
    if (result == NVML_SUCCESS) metrics.temperature_celsius = temp;

    // Power
    unsigned int power = 0;
    result = nvmlDeviceGetPowerUsage(device, &power);
    if (result == NVML_SUCCESS) metrics.power_milliwatts = power;

    // Utilization
    nvmlUtilization_t util;
    result = nvmlDeviceGetUtilizationRates(device, &util);
    if (result == NVML_SUCCESS) metrics.utilization_percent = util.gpu;

    // Memory
    nvmlMemory_t mem;
    result = nvmlDeviceGetMemoryInfo(device, &mem);
    if (result == NVML_SUCCESS) {
        metrics.memory_used_bytes = mem.used;
        metrics.memory_total_bytes = mem.total;
    }

    return true;
}
