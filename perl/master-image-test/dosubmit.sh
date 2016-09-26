#!/bin/bash

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

# debian-7.0-64
# rhel-6.4-64
# scientificwkstn-6.4sysprep-64
# debianwkstn-7.0sysprep-64
# ubuntuwkstn-12.04sysprep-64
# rhelwkstn-6.4sysprep-32
# windows-7.SP1-64
# scientificwkstn-5.9sysprep-64
# fedora-18.0-64
# rhelwkstn-6.4sysprep-64
# fedorawkstn-18.0sysprep-64
# scientific-6.4-64
# rhel-6.4-32
# scientific-5.9-64
# ubuntu-12.04-64

set -x
if [ "$1" = "" ]
then 
    vm=rhel-6.4-64
else 
    vm=$1
fi
# Replace the platform in the job
sed -e"s/^vmplatform.*$/vmplatform=$vm/" startvm.sh > tmp.sh && mv tmp.sh startvm.sh
# and submit it
condor_submit vmsubmit.sub
