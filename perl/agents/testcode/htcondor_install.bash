# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

condor_brand='swampcondor'
condor_root='/opt/swamp/htcondor'
condor_local_dir="$condor_root/local"
./condor_install --overwrite --prefix=$condor_root --make-personal-condor --local-dir=$condor_local_dir
mkdir -p $condor_local_dir/config
cp ~tbricker/swamp/swampinabox_10_main.conf $condor_local_dir/config/.
sed \
-e "s?# condor?# $condor_brand?" \
-e "s?config: /etc/condor?config: $condor_root/etc?" \
-e "s?pidfile: /var/run/condor?pidfile: $condor_local_dir/execute?" \
-e "s?Provides: condor?Provides: $condor_brand?" \
-e "s?lockfile=/var/lock/subsys/condor?lockfile=/var/lock/subsys/$condor_brand?" \
-e "s?pidfile=/var/run/condor?pidfile=$condor_local_dir/execute?" \
-e "s?-f /etc/sysconfig/condor?-f $condor_root/condor.sh?" \
-e "s?. /etc/sysconfig/condor?. $condor_root/condor.sh?" \
< $condor_root/etc/examples/condor.init > /etc/init.d/$condor_brand
chmod +x /etc/init.d/$condor_brand
