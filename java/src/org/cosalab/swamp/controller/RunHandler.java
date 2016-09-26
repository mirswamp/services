// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2016 Software Assurance Marketplace

package org.cosalab.swamp.controller;

import org.apache.log4j.Logger;
import org.apache.xmlrpc.XmlRpcException;
import org.apache.xmlrpc.client.XmlRpcClient;
import org.cosalab.swamp.collector.BaseCollectorHandler;
import org.cosalab.swamp.dispatcher.AgentDispatcher;
import org.cosalab.swamp.util.ExecRecord;
import org.cosalab.swamp.util.StringUtil;

import java.sql.SQLException;
import java.util.ArrayList;
import java.util.HashMap;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson@morgridgeinstitute.org
 * Date: 7/25/13
 * Time: 10:54 AM
 */
public class RunHandler extends BaseCollectorHandler implements RunController
{
    /** Set up logging for the run handler class. */
    private static final Logger LOG = Logger.getLogger(RunHandler.class.getName());

    /** Exec run UUID key for use in hash map. */
    private static final String EXEC_RUN_KEY = "execrunid";

    /** Command strings. */
    private final String cmdStart, cmdBOG;

    /**
     * Constructor.
     */
    public RunHandler()
    {
        super();
        LOG.debug("*** The Run Handler is on the job ***");
        cmdStart = AgentDispatcher.getStringStart();
        cmdBOG = AgentDispatcher.getStringBOG();
    }

    /**
     * Prepare input information for an assessment run and send it to the launch pad.
     *
     * @param args  a HashMap that contains the required input information.
     * @return      a HashMap with the results of executing this method.
     */
    @Override
    public HashMap<String, String> doRun(HashMap<String, String> args)
    {
        LOG.info("doRun called");
        HashMap<String, String> results = new HashMap<String, String>();

        if (args == null)
        {
            results.put(ERROR_KEY, "null argument");
            return results;
        }

        String execrunID = args.get(EXEC_RUN_KEY);
        if (execrunID == null || execrunID.isEmpty())
        {
            results.put(ERROR_KEY, "bad assessment run ID");
            return results;
        }

        // set the ID label.
        setIDLabel(StringUtil.createLogExecIDString(execrunID));

        // store the run ID in the results map for debugging purposes
        results.put(EXEC_RUN_KEY, execrunID);

        // we need to talk to the database to find the id's for the tool, package and platform
        // for this assessment run.

        // first, let's set up the data base connections
        if(!initConnections(runDBTest))
        {
            results.put(ERROR_KEY, "problem initializing database connections");
            cleanup();
            return results;
        }

        HashMap<String, String> arguments = new HashMap<String, String>();

        // the arguments hash map contains the input for the quartermaster
        arguments.put(EXEC_RUN_KEY, execrunID);

        // let's grab the run information
        if (!getQuartermasterArgs(results, execrunID, arguments))
        {
            cleanup();
            return results;
        }

        // at this point we no longer need the assessment DB connection
        cleanup();

        try
        {
            // behave as a client for the Quartermaster.
            QuartermasterClient quarterClient = QuartermasterClient.getInstance();
            XmlRpcClient clientQ = quarterClient.getClient();
            if (clientQ == null)
            {
                String msg = "problem initializing the quartermaster client";
                handleError(results, msg, LOG);
                return results;
            }

            HashMap<String, String> bog = getBOG(arguments, clientQ);
            if (bog == null)
            {
                String msg = "quartermaster returned a null bog";
                handleError(results, msg, LOG);
                return results;
            }
            else if (bog.get(ERROR_KEY) != null)
            {
                results.put(ERROR_KEY, bog.get(ERROR_KEY));
                return results;
            }

            LOG.info("\treceived BOG from quartermaster" + idLabel);

            // now add the results folder information
            bog.put("resultsfolder", AgentDispatcher.getResultsFolderRoot());

            // set ourselves up as a client for the launch pad
            LaunchPadClient launchPadClient = LaunchPadClient.getInstance();
            XmlRpcClient clientL = launchPadClient.getClient();
            if (clientL == null)
            {
                String msg = "problem initializing the launch pad client";
                handleError(results, msg, LOG);
                return results;
            }

            // call the launch pad to start the job
            if (!launchJob(results, bog, clientL))
            {
                return results;
            }

            LOG.info("\tjob sent to launch pad" + idLabel);
        }
        catch (XmlRpcException e)
        {
            String msg = "problem talking to XML-RPC server: " + e.getMessage();
            handleError(results, msg, LOG);
        }

        return results;
    }

    /**
     * Retrieve the arguments that need to be passed on to the quartermaster.
     *
     * @param results       Hash map containing the results.
     * @param execrunID     Execution run uuid.
     * @param arguments     Hash map with the input data for the quartermaster.
     * @return              true if we retrieve the quartermaster info; false otherwise.
     */
    private boolean getQuartermasterArgs(HashMap<String, String> results,
                                         String execrunID,
                                         HashMap<String, String> arguments)
    {
        try
        {
            ArrayList<ExecRecord> recordSet = assessmentDB.getSingleExecutionRecord(execrunID);
            if (recordSet.size() > 1)
            {
                LOG.warn("assessment DB has retrieved more than one record" + idLabel);
            }
            else if (recordSet.size() < 1)
            {
                String msg = "assessment DB has not retrieved the requested record";
                handleError(results, msg, LOG);
                return false;
            }

            // this is the assessment run record
            ExecRecord record = recordSet.get(0);
            // one final check of the exec run ID
            if (!execrunID.equalsIgnoreCase(record.getExecRecordUuid()))
            {
                // somwhow the exec run ID retrieved from the database is not what we wanted
                String msg = "assessment DB has retrieved record with mismatched exec run ID";
                handleError(results, msg, LOG);
                return false;
            }
            // we are good to go.
            prepareInputForQuartermaster(record, arguments);
        }
        catch (SQLException e)
        {
            String msg = "problem retrieving record from assessment DB: " + e.getMessage();
            handleError(results, msg, LOG);
            return false;
        }

        return true;
    }

    /**
     * Retrieve the bill of goods from the quartermaster.
     *
     * @param arguments     Hash map with the input arguments for the quartermaster.
     * @param qClient       The quartermaster XML-RPC client.
     * @return              Hash map - the bill of goods.
     * @throws XmlRpcException
     */
    private HashMap<String, String> getBOG(HashMap<String, String> arguments, XmlRpcClient qClient)
            throws XmlRpcException
    {
        ArrayList params = new ArrayList();
        params.add(arguments);

        HashMap<String, String> bog = (HashMap<String, String>)qClient.execute(cmdBOG, params);

        return bog;
    }

    /**
     * Launch the assessment run.
     *
     * @param results       Results hash map.
     * @param bog           The bill of goods hash map.
     * @param client        The launch pad XML-RPC client.
     * @return              true if the job is successfully launched; false otherwise.
     */
    private boolean launchJob(HashMap<String, String> results, HashMap<String, String> bog, XmlRpcClient client)
    {
        ArrayList params = new ArrayList();
        params.add(bog);
        boolean success = false;

        try
        {
            HashMap<String, String> resultHash = (HashMap<String, String>)client.execute(cmdStart, params);
            if (resultHash == null)
            {
                // it's an error for the launch pad to return a null
                String msg = "launchpad returned a null result";
                LOG.error(msg + idLabel);
                results.put(ERROR_KEY, msg);
            }
            else if (resultHash.get(ERROR_KEY) == null)
            {
                LOG.info("job started" + idLabel);
                success = true;
            }
            else
            {
                // the launch pad encountered an error and quit.
                results.put(ERROR_KEY, resultHash.get(ERROR_KEY));
                LOG.error("starting job: error: " + resultHash.get(ERROR_KEY) + idLabel);
            }
        }
        catch (XmlRpcException e)
        {
            String msg = "launchpad execution failed: " + e.getMessage();
            handleError(results, msg, LOG);
        }
        return success;
    }


    /**
     * Simple test method for retrieving an execution record.
     *
     * @param args      Hash map with arguments for the test.
     * @return          Results hash map: input info for the quartermaster.
     */
    public HashMap<String, String> doDatabaseTest(HashMap<String, String> args)
    {
        LOG.info("request to doDatabaseTest");
        HashMap<String, String> bog = new HashMap<String, String>();

        String execRunID = args.get(EXEC_RUN_KEY);
        if (execRunID == null)
        {
            bog.put(ERROR_KEY, "no execution run ID found");
            return bog;
        }

        // first, let's set up the data base connections
        if(!initConnections(runDBTest))
        {
            bog.put(ERROR_KEY, "problem initializing database connections");
            cleanup();
            return bog;
        }

        // put this in the bog now, so we'll know which run went bad if there are errors and we return early.
        bog.put(EXEC_RUN_KEY, execRunID);

        // let's grab the information
        try
        {
            ArrayList<ExecRecord> recordSet = assessmentDB.getSingleExecutionRecord(execRunID);
            if (recordSet.size() > 1)
            {
                LOG.warn("assessment DB has retrieved more than one record");
            }
            else if (recordSet.size() < 1)
            {
                String msg = "assessment DB has not retrieved the requested record";
                handleError(bog, msg, LOG);
                cleanup();
                return bog;
            }

            // this is the assessment run record
            ExecRecord record = recordSet.get(0);
            prepareInputForQuartermaster(record, bog);

        }
        catch (SQLException e)
        {
            String msg = "problem retrieving record from assessment DB: " + e.getMessage();
            handleError(bog, msg, LOG);
            return bog;
        }

        // all done - we can return;
        cleanup();
        return bog;
    }

    /**
     * Prepare the input for a quartermaster get bill of goods query.
     *
     * @param record    The execution record data.
     * @param input     The has hmap that will be sent to the quartermaster.
     */
    private void prepareInputForQuartermaster(ExecRecord record, HashMap<String, String> input)
    {
//        input.put("execrunid", record.getExecRecordUuid());
        input.put("platformid", record.getPlatformUuid());
        input.put("toolid", record.getToolUuid());
        input.put("packageid", record.getPackageUuid());
        input.put("projectid", record.getProjectUuid());
    }
}
