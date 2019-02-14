#!/bin/bash

args=("$@")
launcher_name="${args[0]}"
launcher_file="/opt/swamp/bin/vmu_${launcher_name}.pl"
launcher_args=("${args[@]:1}")
execrunuid="${launcher_args[0]}"
clusterid="${launcher_args[3]}"
# for viewers remove vrun_ prefix and _CodeDX suffix
execrunuid=${execrunuid//vrun_/}
execrunuid=${execrunuid//_CodeDX/}
logfile="/opt/swamp/log/${execrunuid}_${clusterid}.log"

echo "execrunuid: " $execrunuid
echo "logfile: " $logfile
