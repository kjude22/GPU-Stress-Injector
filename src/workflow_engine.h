#ifndef WORKFLOW_ENGINE_H
#define WORKFLOW_ENGINE_H

#include "yaml_parser.h"

class WorkflowEngine {
private:
    int gpu_index;
    unsigned int max_power;
    unsigned int max_temp;

public:
    WorkflowEngine(int gpu_idx, unsigned int max_pwr, unsigned int max_tmp);
    
    // 시나리오를 받아 순차적으로 스텝을 실행합니다.
    void run(const ScenarioConfig& scenario);
};

#endif // WORKFLOW_ENGINE_H
