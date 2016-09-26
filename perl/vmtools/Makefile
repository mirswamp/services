# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

SRC= lib/VMTools.pm lib/VMConstants.pm start_vm vm_cleanup vm_output masterify_vm
CRITIC=cruel
install: syntax lib/VMTools.pm.d start_vm.d vm_cleanup.d vm_output.d masterify_vm.d lib/VMConstants.pm.d
REMOTEDIR=src
REMOTEHOST=swa-exec-dt-01.mirsam.org
TEST_FORMATTER ?= tap_harness_args=formatter_class=TAP::Formatter::JUnit

%.d: %
#	./updateversion.pl $*
	scp $* dboulineau@$(REMOTEHOST):$(REMOTEDIR)
	touch $@

podcheck:
	podchecker $(SRC)

syntax:
	perl -c lib/VMTools.pm
	perl -c lib/VMConstants.pm
	perl -I lib -c start_vm
	perl -I lib -c vm_cleanup
	perl -I lib -c vm_output
	perl -I lib -c masterify_vm


blib: Build
	./Build 

Build:
	perl Build.PL

test: blib
	TEST_POD=1 TEST_CRITIC=2 ./Build test $(TEST_FORMATTER) --test_files "t/*.t ../common/t/*.t test.pl" $(TEST_OUTPUT)
	
distro: Build test
	./Build fakeinstall

critic:
	perlcritic --$(CRITIC) --theme '!pbp' --exclude=Documentation::RequirePodSections $(SRC)
