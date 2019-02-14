# add swampresults group if not extant
groupadd -f swampresults

# add mysql and swa-daemon users to swampresults group
usermod -a -G swampresults mysql
usermod -a -G swampresults swa-daemon

# adjust shared subdirectories in /swamp/working/results
chgrp -fR swampresults /swamp/working/results
chmod g+rwxs /swamp/working/results
chmod -R g+rw /swamp/working/results/*

# adjust shared subdirectories in /swamp/SCAProjects
chgrp -fR swampresults /swamp/SCAProjects
chmod g+rwxs /swamp/SCAProjects
chmod -R g+rw /swamp/SCAProjects/*


