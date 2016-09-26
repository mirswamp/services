Feature: Testing of VM Scripts
    As a developer I want to use VM scripts
    I want to test the behaviour of the scripts.
    In order to ensure they meet the user requirments.

Background:
    Given a valid install

Scenario: vm_cleanup no args
    Given a script named vm_cleanup
    When I've run vm_cleanup with no args
    Then the output looks like "vm-name option is req"

Scenario: start_vm no args
    Given a script named start_vm
    When I've run start_vm with no args
    Then the output looks like "dir-path option is req"

Scenario: vm_output with help
    Given a script named vm_output
    When I've run vm_output --help
    Then the output looks like "Usage:"

Scenario: vm_cleanup with help
    Given a script named vm_cleanup
    When I've run vm_cleanup --help
    Then the output looks like "Usage:"

Scenario: start_vm with help
    Given a script named start_vm
    When I've run start_vm --help
    Then the output looks like "Usage:"

Scenario:
    Given a script named vm_output
    When I've run vm_cleanup -V
    Then the result is "vm_output:"

Scenario: vm_output no args
    Given a script named vm_output
    When I've run vm_output with no args
    Then the output is the following
    """
    vm-name option is required.
    Usage:
        vm_output [--version] vm-name dir-path

    """
