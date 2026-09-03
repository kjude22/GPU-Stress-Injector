#include "workflow_engine.h"
#include "gpu_memory.h"
#include "gpu_util.h"
#include "gpu_pcie.h"
#include "gpu_power.h"
#include "gpu_thermal.h"
#include "gpu_tensor.h"
#include "gpu_metrics.h"
#include <iostream>
#include <thread>
#include <chrono>

WorkflowEngine::WorkflowEngine(int gpu_idx, unsigned int max_pwr, unsigned int max_tmp)
    : gpu_index(gpu_idx), max_power(max_pwr), max_temp(max_tmp) {}

void WorkflowEngine::run(const ScenarioConfig& scenario) {
    std::cout << "\n======================================" << std::endl;
    std::cout << "[Workflow] Starting Scenario: " << scenario.name << std::endl;
    if (!scenario.description.empty()) {
        std::cout << "Description: " << scenario.description << std::endl;
    }
    std::cout << "======================================\n" << std::endl;

    GpuMetricReader metric_reader(gpu_index);

    for (const auto& step : scenario.sequence) {
        std::cout << ">>> [Step " << step.step_index << "] Executing Type: " 
                  << step.type << " @ " << step.percent << "% (or C) for " 
                  << step.duration_sec << "s" << std::endl;

        // 상태 변수 (현재 스텝의 스트레서 포인터들)
        GpuMemoryStressor* mem_stressor = nullptr;
        GpuUtilStressor* util_stressor = nullptr;
        GpuPcieStressor* pcie_stressor = nullptr;
        GpuPowerStressor* power_stressor = nullptr;
        GpuThermalStressor* thermal_stressor = nullptr;
        GpuTensorStressor* tensor_stressor = nullptr;

        // 모듈 할당 및 실행
        if (step.type == "memory") {
            mem_stressor = new GpuMemoryStressor(gpu_index);
            mem_stressor->allocate_percent(step.percent);
        } else if (step.type == "util") {
            util_stressor = new GpuUtilStressor(gpu_index);
            util_stressor->start_percent(step.percent);
        } else if (step.type == "pcie") {
            pcie_stressor = new GpuPcieStressor(gpu_index);
            pcie_stressor->start_percent(step.percent);
        } else if (step.type == "power") {
            power_stressor = new GpuPowerStressor(gpu_index);
            power_stressor->start_percent(step.percent);
        } else if (step.type == "thermal") {
            thermal_stressor = new GpuThermalStressor(gpu_index);
            thermal_stressor->start_target_temp((unsigned int)step.percent);
        } else if (step.type == "tensor") {
            tensor_stressor = new GpuTensorStressor(gpu_index);
            tensor_stressor->start_percent(step.percent);
        }

        bool safety_triggered = false;

        // 지정된 시간만큼 대기 및 모니터링 루프
        for (int elapsed = 0; elapsed < step.duration_sec; ++elapsed) {
            std::this_thread::sleep_for(std::chrono::seconds(1));

            GpuMetrics metrics;
            if (metric_reader.read(metrics)) {
                if ((max_temp > 0 && metrics.temperature_celsius >= max_temp) ||
                    (max_power > 0 && (metrics.power_milliwatts / 1000) >= max_power)) {
                    std::cerr << "\n[SAFETY TRIGGERED] Limit exceeded during Step " << step.step_index << "!" << std::endl;
                    std::cerr << "Current Temp: " << metrics.temperature_celsius << "C, Power: " << metrics.power_milliwatts / 1000 << "W" << std::endl;
                    safety_triggered = true;
                    break;
                }
            }

            if ((elapsed + 1) % 10 == 0 || elapsed == 0) {
                std::cout << "  - Step " << step.step_index << " Elapsed: " << elapsed + 1 << " / " << step.duration_sec << " seconds." << std::endl;
            }
        }

        // Graceful Teardown (모듈 해제)
        std::cout << "<<< [Step " << step.step_index << "] Teardown complete.\n" << std::endl;
        
        if (mem_stressor) { mem_stressor->release(); delete mem_stressor; }
        if (util_stressor) { util_stressor->stop(); delete util_stressor; }
        if (pcie_stressor) { pcie_stressor->stop(); delete pcie_stressor; }
        if (power_stressor) { power_stressor->stop(); delete power_stressor; }
        if (thermal_stressor) { thermal_stressor->stop(); delete thermal_stressor; }
        if (tensor_stressor) { tensor_stressor->stop(); delete tensor_stressor; }

        if (safety_triggered) {
            std::cerr << "[Workflow] Aborting remaining scenario due to safety limits." << std::endl;
            break;
        }
    }
    
    std::cout << "======================================" << std::endl;
    std::cout << "[Workflow] Scenario execution completed." << std::endl;
    std::cout << "======================================\n" << std::endl;
}
