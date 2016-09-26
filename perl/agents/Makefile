# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

SRC= AgentMonitor.pl TestDispatchServer.pl csa_agent.pl csa_HTCondorAgent.pl calldorun.pl killrun.pl launchviewer.pl LaunchPad.pl swamp_monitor swamp_config ViewerMonitor.pl notifyuser.pl
SCRIPTS= csa_HTCondorAgent_launcher csa_agent_launcher assessmentlauncher
DOXYGEN_SRC=\
	dox_agentmonitor \
	dox_assessmentTask \
	dox_csa_HTCondoragent \
	dox_csa_agent
PACKAGES=\
	SWAMP/RPCUtils.pm \
	SWAMP/HTCondorDefines.pm \
	SWAMP/Client/AgentClient.pm \
	SWAMP/Client/ExecuteRecordCollectorClient.pm \
	SWAMP/Client/LaunchPadClient.pm \
	SWAMP/Client/LogCollectorClient.pm \
	SWAMP/Client/ResultCollectorClient.pm \
	SWAMP/Client/RunControllerClient.pm \
	SWAMP/Client/GatorClient.pm \
	SWAMP/AssessmentTools.pm \
	SWAMP/ToolLicense.pm \
	SWAMP/TestVirtUtils.pm \
	SWAMP/FrameworkUtils.pm \
	SWAMP/CodeDX.pm \
	SWAMP/Floodlight.pm \
	SWAMP/Notification.pm \
	SWAMP/AgentMonitorCommon.pm \
	SWAMP/SWAMPUtils.pm \
	SWAMP/SysUtils.pm \
	SWAMP/VMPrimitives.pm 
#
# Test all sources on Dev box
ifeq ($(shell uname), Darwin) 
SRC += assessmentTask.pl DomainMonitor.pl vrunTask.pl
PACKAGES += SWAMP/SysVirtEvents.pm
endif

DOCROOT ?= doxygen
HOST ?= submit1
LIBS=lib ../vmprimitives/lib
TEST_FORMATTER ?= tap_harness_args=formatter_class=TAP::Formatter::JUnit
.PHONY: syntax clean deploy doc Build

syntax: $(SRC) $(PACKAGES:%=lib/%)
	@echo $? | xargs -n 1 perl -c $(LIBS:%=-I%) 

srclist: $(SRC) $(PACKAGES:%=lib/%)
	@echo $? | xargs -n 1 echo

clean:
	./Build clean

Build: Build.PL
	perl Build.PL

blib: Build
	./Build 

testrpc:
	./Build test --verbose --test_files "t/*.t" 

test: blib syntax
	TEST_POD=1 TEST_CRITIC=2 ./Build test $(TEST_FORMATTER)  --test_files "t/*.t ../common/t/*.t" $(TEST_OUTPUT)
	/bin/rm -f t/.hypervisors t/.agentevents t/.agentstate t/.viewerinfo t/temp.props .viewerinfo AgentMonitor.log TestDispatchServer.log LaunchPad.log t/*.log csa_agent.log

bats:
	testswamp_mon --tap > swamp_monitor.tap
	
distro: Build test 
	./Build fakeinstall

critic: blib syntax
	PERL5LIB=lib TEST_CRITIC=2 ./Build test --verbose --test_files "../common/t/critic.t"
	-PERL5LIB=lib perlcritic --cruel assessmentTask.pl
	-PERL5LIB=lib perlcritic --cruel DomainMonitor.pl
	-PERL5LIB=lib perlcritic --cruel vrunTask.pl

#echo $(DOXYGEN_SRC) | xargs -n1 echo $<
doc: $(SRC) $(PACKAGES:%=lib/%)  
	cd ../../deployment/doc && make clean doc


tags: $(SRC) $(PACKAGES:%=lib/%)
	ctags -L srcfiles  --language-force=Perl


tarball:
	gtar czvf dist.tar.gz $(SRC) $(SCRIPTS) $(PACKAGES:%=lib/%) arun vrun.pl

deploy: tarball
	scp dist.tar.gz exec5:deploy 
	ssh exec5 tar -C deploy -xvf deploy/dist.tar.gz

localdeploy:
	cp $(SRC) /opt/swamp/bin
	cp -r lib/* /opt/swamp/perl5
