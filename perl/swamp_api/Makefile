# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

VER=v$(shell date +%s)
demo: thispkg.tar.gz
	perl swamp_pkg --file thispkg.tar.gz  --comment_public "Demo upload of $(VER)"  --version_string $(VER) --build_system make --build_target Makefile 
	
thispkg.tar.gz:
	gtar czf thispkg.tar.gz swamp_pkg swamp_auth

test: upload.tar.gz
	. ./upload.sh

upload.tar.gz: upload.sh
	gtar czf upload.tar.gz Makefile upload.sh
