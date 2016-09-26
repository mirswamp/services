# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

# Simple script to launch the slave client which listens for commands over a virtual serial port

# Wait for networking
sleep 20

# Write something to /mnt/out/run.out
ifconfig >> /mnt/out/run.out 2>&1

perl slave.pl >> /mnt/out/run.out 2>&1

shutdown -h now
