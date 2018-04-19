# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2018 Software Assurance Marketplace

watch -d "ps -eHo ppid,pid,pgrp,command | egrep 'perl.*vmu_|condor|mysql' | grep -v grep"
