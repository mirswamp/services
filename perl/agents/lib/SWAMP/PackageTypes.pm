# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2018 Software Assurance Marketplace

package SWAMP::PackageTypes;

use 5.010;
use utf8;
use strict;
use warnings;

use parent qw(Exporter);
our (@EXPORT_OK);
BEGIN {
    require Exporter;
    @EXPORT_OK = qw(
      $GENERIC_PKG
      $C_CPP_PKG
      $JAVASRC_PKG
      $JAVABYTECODE_PKG
      $PYTHON2_PKG
      $PYTHON3_PKG
	  $ANDROID_JAVASRC_PKG
	  $RUBY_PKG
	  $RUBY_SINATRA_PKG
	  $RUBY_ON_RAILS_PKG
	  $RUBY_PADRINO_PKG
	  $ANDROID_APK_PKG
	  $JAVA8SRC_PKG
	  $JAVA8BYTECODE_PKG
	  $WEB_SCRIPTING_PKG

      $C_CPP_PKG_STRING
      $JAVA7SRC_PKG_STRING
      $JAVA7BYTECODE_PKG_STRING
      $JAVA8SRC_PKG_STRING
      $JAVA8BYTECODE_PKG_STRING
      $PYTHON2_PKG_STRING
      $PYTHON3_PKG_STRING
      $ANDROID_JAVASRC_PKG_STRING
	  $RUBY_PKG_STRING
	  $RUBY_SINATRA_PKG_STRING
	  $RUBY_ON_RAILS_PKG_STRING
	  $RUBY_PADRINO_PKG_STRING
      $ANDROID_APK_PKG_STRING
	  $WEB_SCRIPTING_PKG_STRING

      $CPP_TYPE
      $JAVA_TYPE
      $PYTHON_TYPE
	  $RUBY_TYPE
	  $SCRIPT_TYPE
    );
}

our $GENERIC_PKG			= '0';
our $C_CPP_PKG				= '1';
our $JAVASRC_PKG			= '2';
our $JAVABYTECODE_PKG		= '3';
our $PYTHON2_PKG			= '4';
our $PYTHON3_PKG			= '5';
our $ANDROID_JAVASRC_PKG	= '6';
our $RUBY_PKG				= '7';
our $RUBY_SINATRA_PKG		= '8';
our $RUBY_ON_RAILS_PKG		= '9';
our $RUBY_PADRINO_PKG		= '10';
our $ANDROID_APK_PKG		= '11';
our $JAVA8SRC_PKG			= '12';
our $JAVA8BYTECODE_PKG		= '13';
our $WEB_SCRIPTING_PKG		= '14';

our $PYTHON_TYPE	= 'python';
our $JAVA_TYPE		= 'java';
our $CPP_TYPE		= 'cpp';
our $RUBY_TYPE		= 'ruby';
our $SCRIPT_TYPE	= 'script';

our $GENERIC_PKG_STRING			= 'generic';
our $C_CPP_PKG_STRING			= 'C/C++';
our $JAVA7SRC_PKG_STRING		= 'Java 7 Source Code';
our $JAVA7BYTECODE_PKG_STRING	= 'Java 7 Bytecode';
our $JAVA8SRC_PKG_STRING		= 'Java 8 Source Code';
our $JAVA8BYTECODE_PKG_STRING	= 'Java 8 Bytecode';
our $PYTHON2_PKG_STRING			= 'Python2';
our $PYTHON3_PKG_STRING			= 'Python3';
our $ANDROID_JAVASRC_PKG_STRING	= 'Android Java Source Code';
our $RUBY_PKG_STRING			= 'Ruby';
our $RUBY_SINATRA_PKG_STRING	= 'Ruby Sinatra';
our $RUBY_ON_RAILS_PKG_STRING	= 'Ruby on Rails';
our $RUBY_PADRINO_PKG_STRING	= 'Ruby Padrino';
our $ANDROID_APK_PKG_STRING		= 'Android .apk';
our $WEB_SCRIPTING_PKG_STRING	= 'Web Scripting';

1;
