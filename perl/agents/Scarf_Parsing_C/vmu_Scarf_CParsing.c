#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ScarfCommon.h"
#include "AttributeJsonReader.h"
#include "ScarfXml.h"
#include "ScarfJson.h"

#define MAX_ATTRIBUTE 30
// set debug level to 0, 1, 2
int debug = 0;

// A list of sorted array containing a set of attribute entries, sorted by the name of the entry.
entry **attributeDict;
// The counter keeps track of the actual number of the entries in the attributeDict
int count = 0;
// The counter of bugs detected in the SCARF result
int bugCount = 0;
// These global variables will be set with values from arguments passed into the main method, and output to JSON in the initialHandler().
char *packageName;
char *packageVersion;
char *toolName;
char *toolVersion;
char *platformName;
char *platformVersion;
char *assessmentStartTime;
char *assessmentEndTime;
char *reportGenerationTime;

// The writer for outputing SCARF results to the JSON file
ScarfJSONWriter *writer;

// The compare function for the qsort function.
int entryCompare(const void* a, const void* b)
{
	char *namea = (*(entry **)a)->name;
	char *nameb = (*(entry **)b)->name;
	//printf("%s, %s\n", namea, nameb);
	return strcmp(namea, nameb);
}

// The search function performs a binary search on the attributeDict, given the name string of the attribute.
entry * binarySearch(char *attribute, int l, int r)
{
	int mid = (l + r)/2;
	// if the search hits the middle element, return the result
	if (strcmp(attributeDict[mid]->name, attribute) == 0) {
		return attributeDict[mid];
	} else if (l == r){
		return NULL;
	}
	// if the current position is smaller than the attribute, search the right half
	if (strcmp(attributeDict[mid]->name, attribute) < 0) {
		return binarySearch(attribute, mid+1, r);
	}
	return binarySearch(attribute, l, mid-1);
}

// Set the valid bit for the attribute to 1 
void setAttributeValid(char *attribute)
{
	if (attribute == NULL) {
		fprintf(stderr, "[ERROR]: The attribute cannot be NULL\n");
		return;
	}
	entry *target = binarySearch(attribute, 0, count-1);
	if (target == NULL) {
		fprintf(stderr, "[ERROR]: Cannot find %s in the attribute list\n", attribute);
		return;
	} else {
		target->valid = 1;
	}
	return; 
}

// Return the valid bit of the attribute
// Otherwise, return -1 if the attribute is not found.
int getAttributeValid(char *attribute)
{
	if (attribute == NULL) {
		fprintf(stderr, "[ERROR]: The attribute cannot be NULL\n");
		return;
	}
	entry *target = binarySearch(attribute, 0, count-1);
	if (target == NULL) {
		fprintf(stderr, "[ERROR]: Cannot find %s in the attribute list\n", attribute);
		return -1;
	} else {
		return target->valid;
	}
	return -1;
}

// Increase the count by one for each attribute found in the SCARF xml file.
void incrementXMLCount(char *attribute)
{	
	if (attribute == NULL) {
		fprintf(stderr, "[ERROR]: The attribute cannot be NULL\n");
		return;
	}
	entry *target = binarySearch(attribute, 0, count-1);
	if (target == NULL) {
		fprintf(stderr, "[ERROR]: Cannot find %s in the attribute list\n", attribute);
		return;
	} else {
		target->xmlCount += 1;
	}
	return;
}

// Increment the bugCount.
void incrementBugCount()
{
	bugCount++;
}

// Add an attribute to the sorted attribute list. The list is sorted by the attribute name string.
void addAttribute(char *attribute)
{
	entry *currEntry;
	if((currEntry = malloc(sizeof(entry))) == NULL) {
		fprintf(stderr, "[ERROR]: Malloc Failed !");
	}
	currEntry->name = strdup(attribute);
	currEntry->valid = 0;
	currEntry->xmlCount = 0;
	attributeDict[count] = currEntry;
	count ++;
}

//for debug use
void printSortedArr()
{
	int i;
	for (i=0; i<count; i++) {
		printf("[DEBUG] %s %d %d\n", attributeDict[i]->name, attributeDict[i]->valid, attributeDict[i]->xmlCount);
	}
}

// Log the count of the attribute in SCARF result.
void logAttributeCount()
{
	int i;
	for (i=0; i<count; i++) {
		if (attributeDict[i]->valid == 1) {
			printf("[INFO] The number of %s found in SCARF XML result is %d/%d.\n", attributeDict[i]->name, attributeDict[i]->xmlCount, bugCount);
		}
	}
}

// Handler function on the initial callback
void *initialHandler(Initial *initial, void *reference)
{
	// These variables are must-have variables in the front-end display, so that we need
	// double-check they are not set to NULL for JSON output, otherwise, we set these variables
	// to values from the command line input.
	if (initial->package_name == NULL)	initial->package_name = packageName;
	if (initial->package_version == NULL)	initial->package_version = packageVersion;
	if (initial->tool_name == NULL)	initial->tool_name = toolName;
	if (initial->tool_version == NULL)	initial->tool_version = toolVersion;
	if (initial->platform_name == NULL)	initial->platform_name = platformName;
	if (initial->platform_version == NULL)	initial->platform_version = platformVersion; 		
	initial->assessment_start_ts = assessmentStartTime;	
	initial->assessment_end_ts = assessmentEndTime;
	initial->report_generation_ts = reportGenerationTime;	
	
	char *initialErrors = CheckStart(initial);
	if(strcmp(initialErrors,"")){
		fprintf(stderr, "[ERROR]: Checkstart failed\n");
	}
	ScarfJSONWriterAddStartTag(writer, initial);
	return NULL;
}

// Handler function on the bug instance callback
void *bugHandler(BugInstance *bug, void *reference)
{
	entry *attributeList = (entry *)reference;
	char *bugErrors = CheckBug(bug);
	if(strcmp(bugErrors,"")){
		fprintf(stderr, "[ERROR]: Checkbug failed\n");
	}
	ScarfJSONWriterAddBug(writer, bug, attributeList);
	return NULL;
}

// Handler function on the metric callback
void *metricHandler(Metric *metr, void *reference)
{
	char *metricErrors = CheckMetric(metr);
	if(strcmp(metricErrors,"")){
		fprintf(stderr, "[ERROR]: Checkmetric failed\n");
	}
	ScarfJSONWriterAddMetric(writer, metr);
	return NULL;
}

// Handler function on the metric summary callback
void *metricSummaryHandler(MetricSummary *metrSum, void *reference)
{
	return NULL;
}

// Handler function on the bug summary callback
void *bugSummaryHandler(BugSummary *bugSum, void *reference)
{
	return NULL;
}

// Handler function on the final callback
void *finalHandler(void *killValue, void *reference)
{
	return NULL;
}

// Read an metadata entry from the File pointed by fp on line-to-line basis, get rid of the '\n' 
// at the end of the line.
void readMetaData(char **var, size_t *len, FILE *fp)
{
	size_t varLen;
	if((varLen=getline(var, len, fp)) == -1){
		fprintf(stderr, "[ERROR]: Error reading the SCARF metadata\n");
		return;
	}
	if((*var)[varLen-1] == '\n'){
		(*var)[varLen-1] = '\0';
	}
}

// This is the main method for the Scarf_Parsing program.
int main(int argc, char **argv) {
	//check the input arguments
	if (argc != 11 || strcmp(argv[1], "-input_file") || strcmp(argv[3], "-output_file") || strcmp(argv[5], "-tool_name") || strcmp(argv[7], "-tool_list") || strcmp(argv[9], "-metadata_path")) {
		fprintf(stderr, "[ERROR]: The input arguments should be: ./vmu_Scarf_CParsing.c -input_dir ... -output_dir ... -tool_name ... -tool_list ... -metadata_path ...\n");
		exit(1);
	}
	//check the input arguments
	char *inputFile;
	char *outputFile;
	char *assessToolName;
	char *toolListPath;

	// load metadata variables	
	inputFile = strdup(argv[2]);
	outputFile = strdup(argv[4]);
	assessToolName = strdup(argv[6]);
	toolListPath = strdup(argv[8]);
	char *metadataPath = strdup(argv[10]);

	// The maximum length of each metadata
	size_t metadataLen = 150;

	// metadata file IO
	FILE *fp;
	if((fp = fopen(metadataPath, "r")) != NULL){
		readMetaData(&packageName, &metadataLen, fp);
		readMetaData(&toolName, &metadataLen, fp);	
		readMetaData(&platformName, &metadataLen, fp);	
		readMetaData(&assessmentStartTime, &metadataLen, fp);	
		readMetaData(&packageVersion, &metadataLen, fp);	
		readMetaData(&toolVersion, &metadataLen, fp);	
		readMetaData(&platformVersion, &metadataLen, fp);	
		readMetaData(&assessmentEndTime, &metadataLen, fp);	
		readMetaData(&reportGenerationTime, &metadataLen, fp);	
		fclose(fp);
	}
	else {
		fprintf(stderr,"[ERROR]: Warning - %s open failed.\n", metadataPath);
	}
	
	// Create the ScarfXmlReader from the scarf file
	ScarfXmlReader *reader = NewScarfXmlReaderFromFilename(inputFile, "UTF-8");
    if(reader == NULL){
        fprintf(stderr, "[ERROR]: Creating XML reader from: %s failed.\n", inputFile);
        exit(1);
    }
	
	// Create the ScarfJsoWriter for output Json
	writer = NewScarfJSONWriterFromFilename(outputFile);
	if (writer == NULL) {
        fprintf(stderr, "[ERROR]: Creating JSON writer to: %s failed.\n", outputFile);
        exit(1);
    }
	ScarfJSONWriterSetErrorLevel(writer, 1);
    ScarfJSONWriterSetPretty(writer, 1);

	//allocate the memory for attribute dictionary
	if ((attributeDict = malloc(sizeof(entry *)*MAX_ATTRIBUTE)) == NULL) {
		fprintf(stderr, "[ERROR] Malloc Failed !");
	}	

	//initialize the default Reader
	AttributeJSONReader *defaultReader = NewAttributeJSONReaderFromFilename(toolListPath);
	if (defaultReader == NULL) {
		fprintf(stderr, "[ERROR]: Creating attribute JSON reader from: %s failed.\n", toolListPath);
		exit(1);
	} 

	//read the default values
	setAttributeDefault(defaultReader);
	AttributeJSONReaderParse(defaultReader);	
	// delete the default attribute JSON reader
	if (defaultReader != NULL) {
		DeleteAttributeJSONReader(defaultReader);
	}	

	//sort the entry array by the string name
	qsort(attributeDict, count, sizeof(entry *), entryCompare);

	// Create the AttributeJSONReader from the Scarf_ToolList.json
	AttributeJSONReader *attriReader = NewAttributeJSONReaderFromFilename(toolListPath);

	if (attriReader == NULL) {
		fprintf(stderr, "[ERROR]: Creating attribute JSON reader from: %s failed.\n", toolListPath);
		exit(1);
	} 

	// Set the entry list and toolname	
	AttributeJSONReaderSetToolname(attriReader, assessToolName);
	AttributeJSONReaderParse(attriReader);
	
	if (debug) {
		printSortedArr();
	}
	// Set the callback functions associated with the XML reader
	InitialCallback initialFunction = &initialHandler;
	BugCallback bugFunction = &bugHandler;
	BugSummaryCallback bugSummaryFunction = &bugSummaryHandler;
	MetricCallback metricFunction = &metricHandler;
	MetricSummaryCallback metricSummaryFunction = &metricSummaryHandler;
	FinalCallback finishFunction = &finalHandler;

    SetInitialCallback(reader, initialFunction);
    SetBugCallback(reader, bugFunction);
    SetMetricCallback(reader, metricFunction);
    SetBugSummaryCallback(reader, bugSummaryFunction);
    SetMetricSummaryCallback(reader, metricSummaryFunction);
    SetFinalCallback(reader, finishFunction);

	// Start parsing the scarf
	void* status = Parse(reader);
	if (status != (void*)-1) {
		// End parsing and free the memory
		ScarfJSONWriterAddSummary(writer);
		ScarfJSONWriterAddEndTag(writer);
		DeleteScarfXmlReader(reader);
		DeleteAttributeJSONReader(attriReader);	
   		DeleteScarfJSONWriter(writer); 
	}
	
	//log attribute count in the SCARF xml file
	logAttributeCount();

	return 0;
}
