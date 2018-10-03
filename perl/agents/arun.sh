#!/bin/bash

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2018 Software Assurance Marketplace

RUNOUT="$VMOUTPUTDIR/swamp_run.out"
EVENTOUT="/dev/ttyS1"
VMIPOUT="/dev/ttyS2"
shutdown_on_error=0

if [ -f "$RUNOUT" ]; then
    echo "`date`: Exiting immediately because $RUNOUT already exists" >> $RUNOUT
	echo "run.sh pid: $$" >> $RUNOUT
	echo "run.sh ppid: ${PPID}" >> $RUNOUT
	echo "run.sh parent command: $(ps ${PPID} | tail -n 1)" >> $RUNOUT
	echo "========================== env" >> $RUNOUT
	env >> $RUNOUT 2>&1
	echo "==========================" >> $RUNOUT
    exit
fi

echo "`date`: run.sh pid: $$" >> $RUNOUT
echo "run.sh ppid: ${PPID}" >> $RUNOUT
echo "run.sh parent command: $(ps ${PPID} | tail -n 1)" >> $RUNOUT

echo "RUNSHSTART" > $EVENTOUT

# check for ip connectivity
for i in {1..10}
do
    VMIP=$(ip route get 1 | awk '{print $7; exit}')
    # this will implicitly wait for 1 second between each of 3 pings
    ping -c 3 $VMIP
    if [ $? == 0 ] 
    then
        break
    fi  
done
echo "$VMIP `hostname`" >> /etc/hosts
ping -c 3 `hostname`
if [ $? != 0 ] 
then
	echo "ERROR: NO IP ADDRESS" >> $RUNOUT
	if [ $shutdown_on_error -eq 1 ] 
	then
		echo "Shutting down $VIEWER viewer via run.sh" >> $RUNOUT
		shutdown -h now 
		exit
	fi
fi
echo $VMIP > $VMIPOUT

echo "========================== id" >> $RUNOUT
id >> $RUNOUT 2>&1
echo "========================== env" >> $RUNOUT
env >> $RUNOUT 2>&1
echo "========================== pwd" >> $RUNOUT
pwd >> $RUNOUT 2>&1
echo "==========================" >> $RUNOUT

echo "BEGINASSESSMENT" > $EVENTOUT
chmod +x $VMINPUTDIR/_run.sh
export NOSHUTDOWN=1
echo ::Assessing_package,`date +%s` >> $RUNOUT
$VMINPUTDIR/_run.sh
echo ::done Assessing_package,$?, `date +%s` >> $RUNOUT


if [ -f '/var/log/boot.log' -a -r '/var/log/boot.log' ]
then
	echo "Copying boot.log at: `date`" >> $RUNOUT
	cp /var/log/boot.log /mnt/out
fi
if [ -f '/var/log/messages' -a -r '/var/log/messages' ]
then
	echo "Copying messages at: `date`" >> $RUNOUT
	cp /var/log/messages /mnt/out
fi

echo "Shutting down assessment vm at: `date`" >> $RUNOUT
echo "ENDASSESSMENT" > $EVENTOUT

$VMSHUTDOWN >> $RUNOUT
