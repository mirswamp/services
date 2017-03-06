// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.quartermaster;

import org.apache.log4j.Logger;
import org.cosalab.swamp.util.AssessmentDBUtil;
import org.cosalab.swamp.util.StringUtil;

import java.sql.SQLException;
import java.util.HashMap;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 5/2/14
 * Time: 1:43 PM
 */
public class AdminHandler extends BaseQuartermasterHandler implements Admin
{
    /** Set up logging for this class. */
    private static final Logger LOG = Logger.getLogger(AdminHandler.class.getName());

    /** Assessment database connection manager. */
    private final AssessmentDBUtil assessmentStore;

    /**
     * Constructor.
     */
    public AdminHandler()
    {
        super();
        LOG.debug("*** Admin Handler is on the job ***");

        assessmentStore = new AssessmentDBUtil(dbURL, dbUser, dbText);
        runDBTest = false;
    }

    /**
     * Send an execution event to the database.
     *
     * @param args      Hash map with the information to be sent to the data base.
     * @return          Hash map with the results of the database request.
     */
    @Override
    public HashMap<String, String> insertExecutionEvent(HashMap<String, String> args)
    {
        LOG.info("request to insertExecutionEvent");

        HashMap<String, String> results = new HashMap<String, String>();

        String recordID = args.get("execrecorduuid");
        if (recordID == null)
        {
            results.put(ERROR_KEY, "no execution record UUID found");
            return results;
        }

        // we have a valid exec run ID, so we can set the ID label.
        setIDLabel(StringUtil.createLogExecIDString(recordID));

        // write the uuid in the results
        results.put("execrecorduuid", recordID);

        String eventTime = args.get("eventtime");
        if (eventTime == null)
        {
            results.put(ERROR_KEY, "no event time found");
            return results;
        }

        String eventName = args.get("eventname");
        if (eventName == null)
        {
            results.put(ERROR_KEY, "no event name found");
            return results;
        }

        String eventPayload = args.get("eventpayload");
        if (eventPayload == null)
        {
            results.put(ERROR_KEY, "no event payload found");
            return results;
        }

        // let's set up the data base connection
        if(!initConnection(runDBTest))
        {
            results.put(ERROR_KEY, "problem initializing database connection");
            cleanup();
            return results;
        }

        try
        {
            boolean success = assessmentStore.insertExecutionEvent(recordID, eventTime, eventName, eventPayload);
            if (!success)
            {
                // something failed - the error message is in the log file.
                String msg = "error when attempting to insert execution event.";
                handleError(results, msg);
                return results;
            }
        }
        catch (SQLException e)
        {
            String msg = "SQL exception when inserting execution event: " + e.getMessage();
            handleError(results, msg);
            return results;
        }

        cleanup();
        return results;
    }

    /**
     * Send the system status to the database.
     *
     * @param args  Hash map with the information to be sent to the data base.
     * @return      Hash map with the results for the database request.
     */
    @Override
    public HashMap<String, String> insertSystemStatus(HashMap<String, String> args)
    {
        LOG.info("request to insertSystemStatus");

        HashMap<String, String> results = new HashMap<String, String>();

        String statusKey = args.get("statuskey");
        if (statusKey == null)
        {
            results.put(ERROR_KEY, "no status key found");
            return results;
        }

        // Set the logging id label to the status key
        setIDLabel(StringUtil.createLogStatusKeyString(statusKey));

        // write the uuid in the results
        results.put("statuskey", statusKey);

        String statusValue = args.get("statusvalue");
        if (statusValue == null)
        {
            results.put(ERROR_KEY, "no status value found");
            LOG.error("no status value found" + idLabel);
            return results;
        }

        LOG.debug("status value = " + statusValue + idLabel);

        // let's set up the data base connection
        if(!initConnection(runDBTest))
        {
            results.put(ERROR_KEY, "problem initializing database connection");
            cleanup();
            return results;
        }

        try
        {
            boolean success = assessmentStore.insertSystemStatus(statusKey, statusValue);
            if (!success)
            {
                // something failed - the error message is in the log file.
                String msg = "error when attempting to insert system status.";
                handleError(results, msg);
                return results;
            }
        }
        catch (SQLException e)
        {
            String msg = "SQL exception when inserting system status: " + e.getMessage();
            handleError(results, msg);
            return results;
        }

        cleanup();
        return results;
    }

    /**
     * Close the database connection so we can exit cleanly.
     */
    private void cleanup()
    {
        assessmentStore.cleanup();
    }

    /**
     * In the event of a fatal error, log the message, add it to the returned results
     * and clean up the database connection.
     *
     * @param bog       Hash map with the results to be returned.
     * @param msg       Error message.
     */
    private void handleError(HashMap<String, String> bog, String msg)
    {
        LOG.error(msg + idLabel);
        bog.put(ERROR_KEY, msg);
        cleanup();
    }

    /**
     * Initialize the connection to the assessment store.
     *
     * @param doTest        Should we run a simple connection test or not?
     * @return              true if the connection is established; false otherwise.
     */
    private boolean initConnection(boolean doTest)
    {
        // register the JDBC
        if (!assessmentStore.registerJDBC())
        {
            return false;
        }

        // make the database connection
        if (!assessmentStore.makeDBConnection())
        {
            return false;
        }

        if (doTest)
        {
            // test the connection
            LOG.info(assessmentStore.doVersionTest() + idLabel);
        }

        return true;
    }

    /**
     * Set the ID label string
     *
     * @param value     The new ID label.
     */
    @Override
    protected void setIDLabel(String value)
    {
        super.setIDLabel(value);
        assessmentStore.setIDLabel(idLabel);
    }
}
