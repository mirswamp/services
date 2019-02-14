# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2019 Software Assurance Marketplace


echo "args: $@"
watch_string='perl.*vmu_|condor|mysql'
if [ ! -z "$@" ]
then
	if [ "$1" == "-s" ]
	then
		watch_string='perl.*vmu_'
	elif [ "$1" == "-c" ]
	then
		watch_string='condor'
	elif [ "$1" == "-m" ]
	then
		watch_string='mysql'
	fi
fi
watch -d "ps -eHo ppid,pid,pgid,command | egrep '$watch_string' | grep -v grep"
