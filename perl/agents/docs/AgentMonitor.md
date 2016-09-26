#### Agent Monitor Overview {#AgentMonitorOverview}

The Agent Monitor is the process responsible for launching SWAMP assessment runs, monitoring assessment runs and for reporting status, execution information and log events.

When the AgentMonitor starts, it first daemonizes itself, then restores any application state from a persistence store. The persistence store is used to preserve internal data structures in the event the process is stopped or the server on which it is running is rebooted.

Agent Monitor maintains lists of 
- assessment runs it has started 
- processes associated with the assessment runs see [csa_agent](../../dox_csa_agent/html/index.html)
- HTCondor jobs associated with the assessment runs see [assessmentTask](../../dox_csa_agent/html/index.html)
- VM domains associated with assessment runs. see [DomainMonitor][]

Each list is indexed by a execute run id or *execrunid*, this is the primary key binding all of the information about assessment runs. 

The main application of AgentMonitor is an XML::RPC server, defined in `AgentMonitor.pl`. All methods implemented by the server are contained within the `AgentMonitor.pl` source file. Other methods associated with AgentMonitor are in the package `SWAMP::AgentMonitorCommon`.

