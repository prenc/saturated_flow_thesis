#ifndef SATURATED_FLOW_THESIS_STATISTICS_H
#define SATURATED_FLOW_THESIS_STATISTICS_H

#include <string>
#include <vector>

#include "timer.h"
#include "../../params.h"
#include "file_helper.h"

struct StatPoint
{
    double coverage;
    double stepTime;
    double transitionTime;
    double findACTime;
};

void writeStatisticsToFile(vector<StatPoint> &stats, string filename);

#endif //SATURATED_FLOW_THESIS_STATISTICS_H
