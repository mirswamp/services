Title: VRun design notes
Author: Dave Boulineau
Affiliation: MIR

# VRun design notes
A VRun will be launched as the HTCondor job for SWAMP viewers in the same manner that  `assessmentTask.pl` is launched for Assessment Runs. The VRun task will be responsible only for populating the database on the VM and ensuring that mysql and tomcat are running.  

When a user clicks View on the UI, the call from the web service will invoke a stored procedure, that will call a Perl script (`launchviewer.pl`) to launch a VRUN. `launchviewer.pl` will check to see if the required VM is present and if it is present it will send the provided results via `curl` to the VM's CodeDX interface and return a URL to the stored procedure.  If the VM is not present, an error is returned to the stored procedure.

If `launchviewer.pl` determines the VM is not running, via an XML-RPC call to AgentMonitor, `launchviewer.pl` will create a BOG and send it to the launcher. This BOG will describe:

* which SWAMP project the VM needs to be associated with
* which database needs to be restored to the VM. 

The `run.sh`that is created for the VM will need to check for authorized user, non-authorized user, and project to exist in the database once the VM has been created. 

Postprocessing of the job will be simpler for VRun VMs than for ARun VMs in that there will not be results so the output doesn't get processed, all that needs to happen in `csa_HTCondorAgent` is that the job folder is removed.

Once agentMonitor is informed of the IP address of the web server of CodeDX, then AgentMonitor will need to call ViewerMonitor on csaweb to create the .htaccess files.

## Synchronization
A mechanism for ensuring only ONE viewer is launched no matter how many viewer requests are sent is required. This has to happen at the launchviewer point within AgentMonitor, create a lock on 'project.viewer' , only one client at a time can call launchViewer with a set of project/viewer pair. This locking will need to happen within the AgentMonitor because it is the long running process that will know about all viewers in a SWAMP instance. We will need a mechanism to handle restarts of the AgentMonitor so that locks persist across process boundaries. N.B. We cannot use advisory locking from within a single long running process, because that lock will **always** be accessible to the original process.

## Process responsibilities 
* The VM will be built, started, torn down by a script [`vruntask`][vruntask] running on a hypervisor.
* `vruntask` will inform AgentMonitor of the state of the VM via XML-RPC.
* `vruntask` will be initiated via HTCondor job with a VRun type of `BOG` from the submit node.
*  in the event `vruntask` dies and the VM is still running, DomainMonitor will trash the VM as soon as it can and let AgentMonitor know the VM is shutdown. 
* The HTCondor job that invokes `vruntask` will be started **immediately** by `LaunchPad`, csa_agent queue. csa_agent has a new option to allow multiple copies of itself to exist  and to launch an HTCondor job immediately.

## `launchviewer.pl` :

* Runs on the dataserver, is invoked from the stored procedure
* Check to see if a viewer VM is running (via XML-RPC procedures in AgentMonitor)
* Send results via `curl` to the VM.  AgentMonitor will know the IP address of the VM when the VM is started.  
* If desired, sends results have been sent via `curl`,
* returns the URL to the CodeDX project to the stored procedure that invoked the script *or* an ERROR

A viewer will be identified by it's type (e.g. CodeDX, Native, etc) and it's project since there is a 1:1 mapping of project to viewer.  viewer{type, project}
## vruntask tasks [vruntask]
* Copy database to input disk
* Copy mysql scripts to input disk
* create `run.sh` that will 
    * manipulate database as necessary
    * modify `.htaccess` file as necessary. 
    * Place codedx instance in proper place.  with proper uuid.
    * Place the IP address of the VM in /etc/hosts as 'ipaddress vmname'
    * Emit the IP address of the VM
    * Fail quickly if there is not an IP address.
    
* call start_vm with input disk and platform of RHEL6-CodeDX 

The CodeDX project will get created via a curl call from launchviewer.

![title](file:///Users/dboulineau/Documents/SWAMP/vrun.svg)

##  Misc
* Creating the VM still needs the completion of createrunscripts, which will need to create the .sql scripts and run.sh script **DONE**
* Run.sh on the VM will need to emit the IP address of the VM so that the agentMonitor.viewerStatus can be invoked. **DONE**
* Finish describing the BOG for vrunTask's ingestion. Should be much simpler than arun BOG. **DONE**
* The SQL script should only check to see if we need an api-key (if there's one in users AND in SUPER_ADMINS) then we don't need one. The user table gets populated by whatever token is in .htacess automatically. **DONE**
* Finish implementing the CodeDX package interface with actual `curl` invocations.  **DONE**
* Finish csaweb installer to deploy ViewerMonitor in SPEC file. Makefile is done, configs are done. Test on VM. **Done**.
* AgentMonitor sets api-key when BOG is created. This will need to be used by EVERY CLIENT wanting to talk to the running VM. So it will live in the agentmonitor process and be available by viewerstatus. **DONE**


 

