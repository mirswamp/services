host=localhost
port=22
sleep_time=1
loop_count=2
for ((i=1; i <= $loop_count; i++))
do
        if [ $(curl -s ${host}:${port} > /dev/null; echo $?) != 7 ]
        then
                connected=$?
                break
        else
                connected=$?
                sleep ${sleep_time}
        fi
done
echo "connected: ${connected}"
if [ $connected == 0 ]
then
        echo "Flow rule exists"
else
        echo "Flow rule does not exist - aborting ..."
        exit
fi
