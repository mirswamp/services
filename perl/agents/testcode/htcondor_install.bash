# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2018 Software Assurance Marketplace

local_dir='tjab_local'
./condor_install --prefix=/opt/swamp/htcondor --make-personal-condor --local-dir=/opt/swamp/htcondor/$local_dir
mkdir /opt/swamp/htcondor/$local_dir/config
cp ~tbricker/swamp/swampinabox_10_main.conf /opt/swamp/htcondor/$local_dir/config/.
