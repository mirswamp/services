CC=gcc
# CC=gcc -g3
CXXFLAGS=-I. -I$(PWD)/yajl/install/include -I/usr/include/libxml2 
LDFLAGS=-L$(PWD)/yajl/install/lib -lxml2 -lm -Wl,-rpath,/opt/swamp/lib -lyajl
# LDFLAGS=-L$(PWD)/yajl/install/lib -lxml2 -lm -Wl,-rpath,$(PWD)/yajl/install/lib -lyajl

all: yajl_lib vmu_Scarf_CParsing

%.o : %.c
	$(CC) -c -o $@ $< $(CXXFLAGS)

yajl_lib:
	(cd ./yajl; ./configure -p $(PWD)/yajl/install; make -s distro; make -s install;) 
	# (cd ./yajl; CFLAGS=-g3 ./configure -p $(PWD)/yajl/install; make distro; make install;) 
	
vmu_Scarf_CParsing: vmu_Scarf_CParsing.c ScarfXmlReader.o ScarfJsonWriter.o AttributeJsonReader.o ScarfCommon.h ScarfXml.h ScarfJson.h AttributeJsonReader.h
	$(CC) $(CXXFLAGS) $(LDFLAGS) -o $@ vmu_Scarf_CParsing.c ScarfXmlReader.o ScarfJsonWriter.o AttributeJsonReader.o 
	readelf -d vmu_Scarf_CParsing | grep RPATH

clean:
	rm -f *.o vmu_Scarf_CParsing output.json 
	(cd ./yajl; make distclean)
