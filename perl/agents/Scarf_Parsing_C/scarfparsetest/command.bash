tool=$1
../vmu_Scarf_CParsing -input_file ./${tool}_parsed_results.xml -output_file ./${tool}_nativereport.json -tool_name $tool -tool_list ~/SWAMP/deployment/swamp/config/Scarf_ToolList.json -metadata_path ./${tool}_SCARFmetaData
echo $command
$command
