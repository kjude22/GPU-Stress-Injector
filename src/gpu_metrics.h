#pragma once

#include <string>

struct GpuMetrics {
    unsigned int utilization_percent = 0;
    unsigned int temperature_celsius = 0;
    unsigned int power_milliwatts = 0;
    unsigned long long memory_used_bytes = 0;
    unsigned long long memory_total_bytes = 0;
};

class GpuMetricReader {
public:
    explicit GpuMetricReader(int gpu_index);
    ~GpuMetricReader();

    bool read(GpuMetrics& metrics);

private:
    int gpu_index_;
    bool initialized_;
    void* nvml_device_; 
};
