#!/bin/bash

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

set -x
vmplatform=debian-7.0-64
vmname=db_condortest_$$
echo Running on `hostname -f` at `date`
/usr/libexec/condor/condor_chirp set_job_attr VMState creating
echo Extracting output at `date`
tar xzvf input.tgz
#sudo /usr/sbin/start_vm --name $vmname in-arun rhel-6.4-64
echo Launching VM at `date`
sudo /usr/sbin/start_vm --name $vmname input $vmplatform
echo Done launching VM at `date`
/usr/libexec/condor/condor_chirp set_job_attr VMState starting
# Here we need to vm_watch $vmname test until it finishes
# this loop will block until the VM shuts down
sudo virsh domstate $vmname | grep running
/usr/libexec/condor/condor_chirp set_job_attr VMState `sudo virsh domstate $vmname`
aborted=0
while [ $? = 0 ]
do
    /usr/libexec/condor/condor_chirp set_job_attr VMState `sudo virsh domstate $vmname`
    /usr/libexec/condor/condor_chirp statfs stop.txt
    if [ $? = 0 ]
    then
        echo "Saw the stop file, stopping"
        sudo virsh destroy $vmname
        aborted=1
        break
    fi
    sleep 15
    sudo virsh domstate $vmname | grep running
done
echo Assessment done at `date`
/usr/libexec/condor/condor_chirp set_job_attr VMState stopped
if [ $aborted = 0 ]
then 
rm -rf ./out
mkdir ./out
ls -lart
echo Extracting output at `date`
sudo /usr/sbin/vm_output $vmname ./out
sudo cat /var/log/messages | grep $vmname > out/vmmessages.log 2>&1
tar czvf out.tgz --exclude=lost+found ./out
else
    touch out.tgz
fi
echo Done extracting output at `date`
sudo /usr/sbin/vm_cleanup $vmname
echo Done cleaning up $vmname `date`
/usr/libexec/condor/condor_chirp set_job_attr VMState done
