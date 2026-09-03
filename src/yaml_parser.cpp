#include "yaml_parser.h"
#include <yaml-cpp/yaml.h>
#include <stdexcept>
#include <iostream>

ScenarioConfig YamlParser::parse(const std::string& filepath) {
    ScenarioConfig config;
    try {
        YAML::Node root = YAML::LoadFile(filepath);

        if (root["name"]) {
            config.name = root["name"].as<std::string>();
        }
        if (root["description"]) {
            config.description = root["description"].as<std::string>();
        }

        if (!root["sequence"] || !root["sequence"].IsSequence()) {
            throw std::runtime_error("YAML parsing error: 'sequence' key is missing or not a sequence array.");
        }

        for (std::size_t i = 0; i < root["sequence"].size(); i++) {
            YAML::Node step_node = root["sequence"][i];
            StressStep step;

            if (!step_node["step"] || !step_node["type"] || !step_node["percent"] || !step_node["duration"]) {
                throw std::runtime_error("YAML parsing error: missing required fields (step, type, percent, duration) in sequence element.");
            }

            step.step_index = step_node["step"].as<int>();
            step.type = step_node["type"].as<std::string>();
            step.percent = step_node["percent"].as<double>();
            step.duration_sec = step_node["duration"].as<int>();

            // Validation (Fail-Fast)
            if (step.type != "memory" && step.type != "util" && step.type != "pcie" && step.type != "power" && step.type != "thermal" && step.type != "tensor") {
                throw std::runtime_error("YAML parsing error: unknown fault type '" + step.type + "' at step " + std::to_string(step.step_index));
            }
            if (step.percent <= 0) {
                throw std::runtime_error("YAML parsing error: percent must be greater than 0 at step " + std::to_string(step.step_index));
            }
            if (step.duration_sec <= 0) {
                throw std::runtime_error("YAML parsing error: duration must be greater than 0 at step " + std::to_string(step.step_index));
            }

            config.sequence.push_back(step);
        }
    } catch (const YAML::Exception& e) {
        throw std::runtime_error(std::string("YAML Exception: ") + e.what());
    }

    return config;
}
