#ifndef YAML_PARSER_H
#define YAML_PARSER_H

#include <string>
#include <vector>

struct StressStep {
    int step_index;
    std::string type;
    double percent;
    int duration_sec;
};

struct ScenarioConfig {
    std::string name;
    std::string description;
    std::vector<StressStep> sequence;
};

class YamlParser {
public:
    // YAML 파일을 읽어 파싱 후 ScenarioConfig 객체로 반환합니다.
    // 실패 시 예외(std::runtime_error)를 던집니다.
    static ScenarioConfig parse(const std::string& filepath);
};

#endif // YAML_PARSER_H
