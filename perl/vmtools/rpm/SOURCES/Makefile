# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

SRCDIR=../..
SRC=VMTools.pm start_vm vm_output vm_cleanup templ.xml Makefile VMConstants.pm masterify_vm
CP=/bin/cp -pf

vmtools-1.tar.gz: $(SRC)
	tar czvf $@ $(SRC)

%.1: %
	pod2man $? > $@

install: start_vm.1 vm_cleanup.1 vm_output.1 masterify_vm.1

