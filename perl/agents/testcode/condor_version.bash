BINDIR=$(cd -- "$(dirname -- "$0")" && pwd)
echo "BINDIR: <"$BINDIR">"
. ~tbricker/swamp/deployment/swampinabox/runtime/bin/swamp_utility.functions

os_tag=""
os_distribution=$(get_os_distribution)
os_version=$(get_os_version)

echo "Checking OS support ... $os_distribution $os_version"

case "$os_distribution $os_version" in
    "CentOS Linux 6")  os_tag=RedHat6 ;;
    "CentOS Linux 7")  os_tag=RedHat7 ;;
    "Red Hat Linux 6") os_tag=RedHat6 ;;
    "Red Hat Linux 7") os_tag=RedHat7 ;;
    *)  
        #   
        # This script needs to know what OS this host is running only to
        # install the system service, which is something that the user can
        # do themselves, if need be.
        #   
        echo "Warning: Not a recognized OS: $os_distribution $os_version" 1>&2
        ;;  
esac
echo "os_tag: <"$os_tag">"

htcondor_version=$(grep '^htcondor:' /opt/swamp/etc/dependencies.txt \
	| head -n 1 \
	| sed -e 's/^htcondor://')
echo "htcondor_version: <"$htcondor_version">"

htcondor_tar_file=$BINDIR/../dependencies/htcondor/condor-${htcondor_version}-x86_64_${os_tag}-stripped.tar.gz
echo "htcondor_tar_file: <"$htcondor_tar_file">"
