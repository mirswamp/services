# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

use Module::Build;
  my $class = Module::Build->subclass(code => <<'EOF');
      sub process_xml_files {
            my $self = shift;
#            print "processing xml files\n";
#                  ... locate and process *.dat files,
#                        ... and create something in blib/lib/
    }
EOF
#  my $build = Module::Build->new
  my $build = $class->new
    (
     module_name => 'VMTools',
     license  => 'perl',
     requires => {
                  'perl'          => '5.6.1',
                  'XML::Simple'  => '2.18',
                 },
    configure_requires => { 'Module::Build' => 0.40 },
    test_requires => {
            'Test::BDD::Cucumber' => '0.15',
            'Test::More' => 0,
            'File::Basename' => 0,
            'Method::Signatures' => 0,
        },
        xml_files => { 'templ.xml' => 'lib/templ.xml' },
        script_files => { 'start_vm', => 'start_vm',
            'vm_output' => 'vm_output',
            'vm_cleanup' => 'vm_cleanup',
            'masterify_vm' => 'masterify_vm' },
    );
  $build->add_build_element('xml');
  $build->create_build_script;
