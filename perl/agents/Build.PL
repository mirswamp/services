# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

use Module::Build;
my $class = Module::Build->subclass( code => <<'EOF');
      sub process_xml_files {
            my $self = shift;
#            print "processing xml files\n";
#                  ... locate and process *.dat files,
#                        ... and create something in blib/lib/
    }
EOF

#  my $build = Module::Build->new
my $build = $class->new(
    module_name => 'SWAMP::Client::AgentClient',
    license     => 'perl',
    requires    => {
        'perl'             => '5.6.1',
        'Data::UUID'       => '1.219',
        'Log::Log4perl' => '',
        'ConfigReader::Simple' => '',
        'Digest::SHA' => '',
        'Sys::Virt'       => '== 1.0.5',
        'Storable'         => '2.45',
        'RPC::XML'         => '1.56',
        'RPC::XML::Server' => '1.7',
        'RPC::XML::Client' => '1.4',
    },
    configure_requires => { 'Module::Build' => 0.40 },
    test_requires      => {

        #            'Test::BDD::Cucumber' => '0.15',
        'Test::More'         => 0,
        'File::Basename'     => 0,
        'Method::Signatures' => 0,
    },
    test_files =>
      { 
        't/perl/agents/t/agentmonitor.t' => 'agentmonitor.t' ,
        't/logcollector.t' => 'logcollector.t' ,
        't/resultcollector.t' => 'resultcollector.t' ,
        't/launchpad.t' => 'launchpad.t' ,
        't/viewer.t' => 'viewer.t',
        't/locking.t' => 'locking.t' ,
      },
    script_files => {
        'TestDispatchServer.pl' => 'TestDispatchServer.pl',
        'csa_agent.pl' => 'csa_agent.pl', 
        'csa_HTCondorAgent.pl' => 'csa_HTCondorAgent.pl',
#        'assessmentTask.pl', needs libvirt for Sys::Virt.. ugh
        'LaunchPad.pl' => 'LaunchPad.pl', 
        'AgentMonitor.pl' => 'AgentMonitor.pl',
        'launchviewer.pl' => 'launchviewer.pl',
        'killrun.pl' => 'killrun.pl',
        'calldorun.pl' => 'calldorun.pl',
        'swamp_config' => 'swamp_config',
        'notifyuser.pl' => 'notifyuser.pl',
        'ViewerMonitor.pl' => 'ViewerMonitor.pl',
        'swamp_monitor' => 'swamp_monitor',
    },
);
$build->create_build_script;
