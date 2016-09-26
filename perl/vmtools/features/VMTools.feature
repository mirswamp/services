Feature: Testing of VMTools.pm
 As a developer I want to use VMTools.pm
 I want to test the interface to VMTools.pm
 In order to have confidence in it.

 Background:
  Given a usable VMTools package

# Scenario: Test getVMDir method
#  When I've called getVMDir with myvm
#  Then the return is /usr/project/myvm

# Scenario: Test getVMDir method empty
#  When I've called getVMDir with nothing
#  Then the return is /usr/project

 Scenario: Test vmExists 
 When I've called vmExists with myvm
 Then the return is 0

 Scenario: Test system method1
  When I call system with "echo 'hello world'"
  Then the output is "echo hello world"

    Scenario: Test isMasterImage 
        When I've called isMasterImage with somefile-master-20130603.qcow2
        Then the return is 0

    Scenario: Test isMasterImage 
        When I've called isMasterImage with condor-fedora2-master-20130603.qcow2
        Then the return is 1

    Scenario: Check listVMs
        When I've called listVMs
        Then the return is 

##sub logMsg($) {
##sub consoleMsg ($) {
##sub errorMsg ($) {
##sub system {
##sub init ($$$) {
##sub initProjectLog($) {
##sub shutdown {
##sub isMasterImage($) {
##sub displaynameToMastername($) {
##sub masternameToDisplayname($) {
##sub listMasters {
##sub vmVNCDisplay($) {
##sub vmExists($) {
##sub vmState($) {
##sub startVM($) {
##sub getVMDir($) {
##sub extractOutput($$) {
##sub createImages($$$$$) {
##sub createXML($$$$$) {
##sub destroyVM($) {
##sub removeVM($) {
##sub defineVM($) {
##sub listVMs {
##sub checkEffectiveUser {
