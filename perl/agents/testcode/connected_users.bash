echo "`date +"%Y/%m/%d %H:%M:%S"`: [$$] Checking for connected users" >> $RUNOUT 2>&1
connected_users="$(who)"
while [ "$connected_users" != "" ]
do
	echo "`date +"%Y/%m/%d %H:%M:%S"`: [$$]"
    sleep 3
    connected_users="$(who)"
done
