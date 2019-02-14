# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2019 Software Assurance Marketplace

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Remove all condor jobs"
condor_rm -all

echo "Delete all condor collector records"
$DIR/../../../../deployment/swampinabox/singleserver/health_scripts/invalidateAllSWAMPClassAds.pl

echo "Stop condor service"
service condor stop
sleep 5

echo "Delete condor logs"
\rm -f /var/log/condor/*

echo "Stop swamp service"
service swamp stop
sleep 5

echo "Delete swamp logs"
\rm -f /opt/swamp/log/*
\rm -rf /opt/swamp/run/*

echo "Set all database execution records launch_flag = 0, complete_flag = 1"
mysql -u root -p <<EOF
UPDATE assessment.execution_record SET launch_flag = 0, complete_flag = 1 WHERE launch_flag = 1 OR complete_flag = 0;
EOF

sleep 5
echo "Start condor service"
service condor start

sleep 5
echo "Start swamp service"
service swamp start

echo "Swamp system has been reset"
