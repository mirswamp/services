# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#
# spec file for vmtools scripts 
#
%define is_darwin %(test -e /Applications && echo 1 || echo 0)
%if %is_darwin
%define _topdir	 	/Users/dboulineau/Projects/cosa/trunk/swamp/src/main/perl/vmtools/rpm
%define nil #
%define _rpmfc_magic_path   /usr/share/file/magic
%define __os Linux
%endif
%define _arch noarch

#%define __spec_prep_post	%{___build_post}
#%define ___build_post	exit 0
#%define __spec_prep_cmd /bin/sh
#%define __build_cmd /bin/sh
#%define __spec_build_cmd %{__build_cmd}
#%define __spec_build_template	#!%{__spec_build_shell}

Summary: A collection of tools for manipulating virtual machines
Name: vmtools
Version: 0.9
Release: 1.%(perl -e 'print $ENV{BUILD_NUMBER}')
License: GPL
Group: Development/Tools
Source: vmtools-1.tar.gz
URL: http://www.cosalab.org
Vendor: cosalab.org
Packager: D. Boulineau <dboulineau@morgridgeinstitute.org>
BuildRoot: /tmp/%{name}-buildroot
BuildArch: noarch

%description
A collection of scripts to create VMs with the ability
to run specific scripts from the hypervisor.

%prep
%setup -c

%build
echo "Here's where I am at build $PWD"
cd ../BUILD/%{name}-%{version}
make install
%install
echo rm -rf $RPM_BUILD_ROOT
echo "At install i am $PWD"
%if %is_darwin
cd %{name}-%{version}
%endif
mkdir -p $RPM_BUILD_ROOT/usr/sbin/
mkdir -p $RPM_BUILD_ROOT/usr/local/share/man/man1
mkdir -p $RPM_BUILD_ROOT/usr/local/etc/swamp
mkdir -p $RPM_BUILD_ROOT/usr/local/share/perl5
mkdir -p $RPM_BUILD_ROOT/usr/project
mkdir -p $RPM_BUILD_ROOT/usr/local/empty

install -m 444 templ.xml $RPM_BUILD_ROOT/usr/local/etc/swamp
install -m 644 masterify_vm.1 $RPM_BUILD_ROOT/usr/local/share/man/man1/masterify_vm.1
install -m 644 start_vm.1 $RPM_BUILD_ROOT/usr/local/share/man/man1/start_vm.1
install -m 644 vm_cleanup.1 $RPM_BUILD_ROOT/usr/local/share/man/man1/vm_cleanup.1
install -m 644 vm_output.1 $RPM_BUILD_ROOT/usr/local/share/man/man1/vm_output.1
install -m 755 VMConstants.pm $RPM_BUILD_ROOT/usr/local/share/perl5
install -m 755 VMTools.pm $RPM_BUILD_ROOT/usr/local/share/perl5
install -m 755 start_vm $RPM_BUILD_ROOT/usr/sbin/
install -m 755 vm_cleanup $RPM_BUILD_ROOT/usr/sbin/
install -m 755 vm_output $RPM_BUILD_ROOT/usr/sbin/
install -m 755 masterify_vm $RPM_BUILD_ROOT/usr/sbin/

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
#%doc README TODO COPYING ChangeLog

/usr/sbin/start_vm
/usr/sbin/vm_cleanup
/usr/sbin/vm_output
/usr/sbin/masterify_vm
/usr/local/share/perl5/VMTools.pm
/usr/local/share/perl5/VMConstants.pm
/usr/local/share/man/man1/start_vm.1
/usr/local/share/man/man1/vm_cleanup.1
/usr/local/share/man/man1/vm_output.1
/usr/local/share/man/man1/masterify_vm.1
/usr/local/etc/swamp/templ.xml

