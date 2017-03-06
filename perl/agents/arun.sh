#!/bin/bash

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2017 Software Assurance Marketplace

RUNOUT="$VMOUTPUTDIR/swamp_run.out"
CLOCOUT="$VMOUTPUTDIR/cloc.out"
EVENTOUT="/dev/ttyS1"

if [ -f "$RUNOUT" ]; then
    echo "`date`: Exiting immediately because $RUNOUT already exists" >> "$RUNOUT.2"
    exit
fi

echo "RUNSHSTART" > $EVENTOUT

echo "begin run.sh" >> $RUNOUT
echo "========================== date" >> $RUNOUT
date >> $RUNOUT 2>&1
echo "========================== id" >> $RUNOUT
id >> $RUNOUT 2>&1
echo "========================== env" >> $RUNOUT
env >> $RUNOUT 2>&1
echo "========================== pwd" >> $RUNOUT
pwd >> $RUNOUT 2>&1
echo "========================== find" >> $RUNOUT
find . >> $RUNOUT 2>&1
echo "==========================" >> $RUNOUT
echo "==STARTIF" >> $RUNOUT
/sbin/ifconfig >> $RUNOUT
echo "==ENDIF" >> $RUNOUT

line=$(grep package-archive package.conf)
parts=(${line//=/ })
PACKAGE=${parts[1]}

echo "RUNCLOC" > $EVENTOUT

echo "cloc $PACKAGE >> $CLOCOUT" >> $RUNOUT
perl $VMINPUTDIR/cloc-1.68.pl --csv --quiet $PACKAGE >> $CLOCOUT 2>&1

echo "BEGINASSESSMENT" > $EVENTOUT
echo ::Assessing_package,`date +%s` >> $RUNOUT
chmod +x $VMINPUTDIR/_run.sh
export NOSHUTDOWN=1
$VMINPUTDIR/_run.sh
echo ::done Assessing_package,$?, `date +%s` >> $RUNOUT
echo "Copying log files at: `date`" >> $RUNOUT
cp /var/log/boot.log /mnt/out
cp /var/log/messages /mnt/out
echo "Shutting down assessment vm at: `date`" >> $RUNOUT
echo "ENDASSESSMENT" > $EVENTOUT

$VMSHUTDOWN >> $RUNOUT
