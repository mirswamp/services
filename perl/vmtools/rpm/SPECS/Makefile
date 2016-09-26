# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

TARBALL=../SOURCES/vmtools-1.tar.gz
FILES=start_vm masterify_vm vm_output vm_cleanup templ.xml
PKGS=VMTools.pm VMConstants.pm
export BUILD_NUMBER ?= dev

pkgfiles:= $(PKGS:%=../../lib/%)
files:= $(FILES:%=../../%) 
destfiles:=$(FILES:%=../SOURCES/%) $(PKGS:%=../SOURCES/%)

# Invoke as TOPDIR=$PWD/.. make
../RPMS/noarch/vmtools-0.9-1.noarch.rpm: ../RPMS ../BUILD ../SRPMS $(TARBALL) vmtools.spec
	rpmbuild --verbose --define '_topdir $(TOPDIR)' -ba vmtools.spec 

$(TARBALL): $(destfiles)
	make -C ../SOURCES

../SOURCES/%: ../../%
	cp -pf $< $@

../SOURCES/%: ../../lib/%
	cp -pf $< $@

../RPMS:
	mkdir -p ../RPMS

../BUILD:
	mkdir -p ../BUILD

../SRPMS:
	mkdir -p ../SRPMS
