// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2016 Software Assurance Marketplace

package org.cosalab.swamp.collector;

import org.apache.log4j.Logger;
import org.cosalab.swamp.util.ExecRecord;
import org.cosalab.swamp.util.StringUtil;

import java.sql.SQLException;
import java.text.ParseException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson@morgridgeinstitute.org
 * Date: 7/25/13
 * Time: 10:18 AM
 */
public class ExecCollectorHandler extends BaseCollectorHandler implements ExecCollector
{
    /** Set up logging for this class. */
    private static final Logger LOG = Logger.getLogger(ExecCollectorHandler.class.getName());

    /**
     * Constructor.
     */
    public ExecCollectorHandler()
    {
        super();
        LOG.debug("*** The Exec Collector is on the job ***");
    }

    /**
     * Handle the request to update the execution results.
     *
     * @param args      Hash map with the execution results to be sent to the database.
     * @return          Hash map with the results of the request.
     */
    @Override
    public HashMap<String, String> updateExecutionResults(HashMap<String, String> args)
    {
        LOG.info("request to updateExecutionResults");
        HashMap<String, String> results = new HashMap<String, String>();

        if (args == null)
        {
            results.put(ERROR_KEY, "null argument");
            return results;
        }

        for (Map.Entry<String, String> entry : args.entrySet())
        {
            LOG.info("\tKey = " + entry.getKey() + ", Value = " + entry.getValue());
        }

        String execrunID = args.get("execrunid");
        if (execrunID == null || execrunID.isEmpty())
        {
            results.put(ERROR_KEY, "bad assessment run ID");
            return results;
        }

        // we have a valid exec run ID, so we can set the ID label.
        setIDLabel(StringUtil.createLogExecIDString(execrunID));

        // first, let's set up the data base connections
        if(!initConnections(runDBTest))
        {
            results.put(ERROR_KEY, "problem initializing database connections");
            cleanup();
            return results;
        }

        String status = StringUtil.validateStringArgument(args.get("status"));

        String timeStart = args.get("run_date");
        try
        {
            timeStart = StringUtil.convertDateString(timeStart);
        }
        catch (ParseException e)
        {
            LOG.warn("problem converting date: " + timeStart + idLabel);
            timeStart = "null";
        }

        String timeEnd = args.get("completion_date");
        try
        {
            timeEnd = StringUtil.convertDateString(timeEnd);
        }
        catch (ParseException e)
        {
            LOG.warn("problem converting date: " + timeEnd + idLabel);
            timeEnd = "null";
        }

        String execNode = StringUtil.validateStringArgument(args.get("execute_node_architecture_id"));

        String sloc = args.get("lines_of_code");
        int loc = StringUtil.decodeIntegerFromString(sloc);

        String cpuUtil = args.get("cpu_utilization");
        if (cpuUtil == null || cpuUtil.isEmpty())
        {
            cpuUtil = "0";
        }
        else if (cpuUtil.charAt(0) == 'i' || cpuUtil.charAt(0) == '_')
        {
            int cpu = StringUtil.decodeIntegerFromString(cpuUtil);
            cpuUtil = Integer.toString(cpu);
        }
        else if(cpuUtil.charAt(0) == 'd')
        {
            double cpu = StringUtil.decodeDoubleFromString(cpuUtil);
            cpuUtil = Double.toString(cpu);
        }

        String vmHostname = args.get("vm_hostname");
        if (vmHostname == null)
        {
            vmHostname = "";
        }

        String vmUsername = args.get("vm_username");
        if (vmUsername == null)
        {
            vmUsername = "";
        }

        String vmPassword = args.get("vm_password");
        if (vmPassword == null)
        {
            vmPassword = "";
        }

        String vmIP = args.get("vmip");
        if (vmIP == null)
        {
            vmIP = "";
        }

        try
        {
            boolean success = assessmentDB.updateExecutionRunStatus(execrunID, status, timeStart, timeEnd,
                                                                    execNode, loc, cpuUtil,
                                                                    vmHostname, vmUsername, vmPassword, vmIP);
            if (!success)
            {
                results.put(ERROR_KEY, "update failed");
            }
        }
        catch (SQLException e)
        {
            String msg = "error updating exec run status: " + e.getMessage();
            handleError(results, msg, LOG);
        }

        // ok, let's clean up and return
        cleanup();
        return results;
    }

    /**
     * Handle the request to get a single execution record.
     *
     * @param args      Hash map with the arguments that need to be sent to the database.
     * @return          Hash map with the results of the request.
     */
    @Override
    public HashMap<String, String> getSingleExecutionRecord(HashMap<String, String> args)
    {
        LOG.info("request to getSingleExecutionRecord");
        HashMap<String, String> results = new HashMap<String, String>();

        String execRunID = args.get("execrunid");
        if (execRunID == null)
        {
            results.put(ERROR_KEY, "no execution run ID found");
            return results;
        }
        else
        {
            results.put("execrunid", execRunID);
        }

        // we have a valid exec run ID, so we can set the ID label.
        setIDLabel(StringUtil.createLogExecIDString(execRunID));

        if(!initConnections(runDBTest))
        {
            results.put(ERROR_KEY, "problem initializing database connections");
            cleanup();
            return results;
        }

        try
        {
            ArrayList<ExecRecord> recordSet = assessmentDB.getSingleExecutionRecord(execRunID);
            if (recordSet.size() > 1)
            {
                LOG.warn("assessment DB has retrieved more than one record" + idLabel);
            }
            else if (recordSet.size() < 1)
            {
                String msg = "assessment DB could not find the requested record";
                handleError(results, msg, LOG);
                return results;
            }

            // this is the assessment run record
            ExecRecord record = recordSet.get(0);

            // write out the requested information
            results.put("status", record.getStatus());
            results.put("run_date", record.getRunDate());
            results.put("completion_date", record.getCompletionDate());
            results.put("cpu_utilization", record.getCPUUtilization());
            results.put("lines_of_code", record.getLinesOfCode());
            results.put("execute_node_architecture_id", record.getExecuteNode());

        }
        catch (SQLException e)
        {
            String msg = "problem retrieving record from assessment DB: " + e.getMessage();
            handleError(results, msg, LOG);
            return results;
        }
        finally
        {
            // always clean up - we're done with the database
            cleanup();
        }

        // all done, let's return
        return results;
    }

}
