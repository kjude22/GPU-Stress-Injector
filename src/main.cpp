#include "gpu_memory.h"
#include "gpu_util.h"
#include "gpu_pcie.h"
#include "gpu_metrics.h"
#include "gpu_power.h"
#include "gpu_thermal.h"
#include "gpu_tensor.h"
#include "yaml_parser.h"
#include "workflow_engine.h"
#include <iostream>
#include <string>
#include <cstdlib>
#include <thread>
#include <chrono>

// 대화형 메뉴 출력
void print_menu() {
    std::cout << "======================================" << std::endl;
    std::cout << " GPU Fault Injector" << std::endl;
    std::cout << "======================================" << std::endl;
    std::cout << "1. GPU Memory Utilization Fault" << std::endl;
    std::cout << "2. GPU Core Utilization Fault" << std::endl;
    std::cout << "3. PCIe Bandwidth Fault" << std::endl;
    std::cout << "4. GPU Power Fault" << std::endl;
    std::cout << "5. GPU Thermal Fault" << std::endl;
    std::cout << "6. GPU Tensor Core Fault" << std::endl;
    std::cout << "======================================" << std::endl;
    std::cout << "Select a fault type (1-6): ";
}

int main(int argc, char** argv) {
    int gpu_index = 0;
    std::string fault_type = "";
    double percent = 0.0;
    int duration = 60;
    unsigned int max_power = 0;
    unsigned int max_temp = 0;

    std::string scenario_file = "";

    // 플래그(인자) 기반 파싱
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--gpu-index" && i + 1 < argc) {
            gpu_index = std::stoi(argv[++i]);
        } else if (arg == "--type" && i + 1 < argc) {
            fault_type = argv[++i];
        } else if (arg == "--percent" && i + 1 < argc) {
            percent = std::stod(argv[++i]);
        } else if (arg == "--duration" && i + 1 < argc) {
            duration = std::stoi(argv[++i]);
        } else if (arg == "--max-power" && i + 1 < argc) {
            max_power = std::stoul(argv[++i]);
        } else if (arg == "--max-temp" && i + 1 < argc) {
            max_temp = std::stoul(argv[++i]);
        } else if (arg == "--scenario" && i + 1 < argc) {
            scenario_file = argv[++i];
        }
    }

    // 시나리오 파일이 주어진 경우 워크플로우 엔진 실행 후 종료
    if (!scenario_file.empty()) {
        try {
            ScenarioConfig config = YamlParser::parse(scenario_file);
            WorkflowEngine engine(gpu_index, max_power, max_temp);
            engine.run(config);
            return 0;
        } catch (const std::exception& e) {
            std::cerr << "Failed to run scenario: " << e.what() << std::endl;
            return 1;
        }
    }

    // 인자가 충분히 주어지지 않았을 경우 대화형 메뉴로 진입
    if (fault_type.empty() || percent == 0.0) {
        int choice = 0;
        print_menu();
        std::cin >> choice;

        if (choice == 1) fault_type = "memory";
        else if (choice == 2) fault_type = "util";
        else if (choice == 3) fault_type = "pcie";
        else if (choice == 4) fault_type = "power";
        else if (choice == 5) fault_type = "thermal";
        else if (choice == 6) fault_type = "tensor";
        else {
            std::cerr << "Invalid choice. Exiting." << std::endl;
            return 1;
        }

        std::cout << "Enter target value (percent or temperature C): ";
        std::cin >> percent;

        std::cout << "Enter duration in seconds (e.g., 60): ";
        std::cin >> duration;
        
        std::cout << "Enter GPU index (default 0): ";
        std::cin >> gpu_index;
    }

    std::cout << "======================================" << std::endl;
    std::cout << "Starting GPU Fault Injector" << std::endl;
    std::cout << "Type: " << fault_type << std::endl;
    std::cout << "GPU Index: " << gpu_index << std::endl;
    std::cout << "Target Percent: " << percent << "%" << std::endl;
    std::cout << "Duration: " << duration << " seconds" << std::endl;
    std::cout << "======================================" << std::endl;

    GpuMemoryStressor* mem_stressor = nullptr;
    GpuUtilStressor* util_stressor = nullptr;
    GpuPcieStressor* pcie_stressor = nullptr;
    GpuPowerStressor* power_stressor = nullptr;
    GpuThermalStressor* thermal_stressor = nullptr;
    GpuTensorStressor* tensor_stressor = nullptr;

    if (fault_type == "memory") {
        mem_stressor = new GpuMemoryStressor(gpu_index);
        if (!mem_stressor->allocate_percent(percent)) return 1;
        std::cout << "[Target: " << percent << "%] Memory Fault active." << std::endl;
    } else if (fault_type == "util") {
        util_stressor = new GpuUtilStressor(gpu_index);
        if (!util_stressor->start_percent(percent)) return 1;
        std::cout << "[Target: " << percent << "%] Util Fault active." << std::endl;
    } else if (fault_type == "pcie") {
        pcie_stressor = new GpuPcieStressor(gpu_index);
        if (!pcie_stressor->start_percent(percent)) return 1;
        std::cout << "[Target: " << percent << "%] PCIe Bandwidth Fault active." << std::endl;
    } else if (fault_type == "power") {
        power_stressor = new GpuPowerStressor(gpu_index);
        if (!power_stressor->start_percent(percent)) return 1;
        std::cout << "[Target: " << percent << "%] Power Fault active." << std::endl;
    } else if (fault_type == "thermal") {
        thermal_stressor = new GpuThermalStressor(gpu_index);
        if (!thermal_stressor->start_target_temp((unsigned int)percent)) return 1;
        std::cout << "[Target: " << percent << " C] Thermal Fault active." << std::endl;
    } else if (fault_type == "tensor") {
        tensor_stressor = new GpuTensorStressor(gpu_index);
        if (!tensor_stressor->start_percent(percent)) return 1;
        std::cout << "[Target: " << percent << "%] Tensor Core Fault active." << std::endl;
    } else {
        std::cerr << "Unknown fault type: " << fault_type << std::endl;
        return 1;
    }

    GpuMetricReader metric_reader(gpu_index);

    for (int elapsed = 0; elapsed < duration; ++elapsed) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
        
        GpuMetrics metrics;
        if (metric_reader.read(metrics)) {
            if ((max_temp > 0 && metrics.temperature_celsius >= max_temp) ||
                (max_power > 0 && (metrics.power_milliwatts / 1000) >= max_power)) {
                std::cerr << "\n[SAFETY TRIGGERED] Limit exceeded!" << std::endl;
                std::cerr << "Current Temp: " << metrics.temperature_celsius << "C, Power: " << metrics.power_milliwatts / 1000 << "W" << std::endl;
                break; // abort loop safely
            }
        }

        if ((elapsed + 1) % 10 == 0 || elapsed == 0) {
            std::cout << "Elapsed: " << elapsed + 1 << " / " << duration << " seconds." << std::endl;
        }
    }

    if (mem_stressor) { mem_stressor->release(); delete mem_stressor; }
    if (util_stressor) { util_stressor->stop(); delete util_stressor; }
    if (pcie_stressor) { pcie_stressor->stop(); delete pcie_stressor; }
    if (power_stressor) { power_stressor->stop(); delete power_stressor; }
    if (thermal_stressor) { thermal_stressor->stop(); delete thermal_stressor; }
    if (tensor_stressor) { tensor_stressor->stop(); delete tensor_stressor; }

    std::cout << "Fault injection complete. Exiting..." << std::endl;
    return 0;
}
