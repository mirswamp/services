// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.quartermaster;

import org.apache.log4j.Logger;
import org.cosalab.swamp.util.BogUtil;
import org.cosalab.swamp.util.CheckSumUtil;
import org.cosalab.swamp.util.StringUtil;
import org.cosalab.swamp.util.ViewerStoreDBUtil;

import java.io.IOException;
import java.sql.SQLException;
import java.util.HashMap;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 2/16/17
 * Time: 2:21 PM
 */
public class ViewerHandler extends BaseQuartermasterHandler implements ViewerOps
{
    /** Set up logging for the quartermaster handler class. */
    private static final Logger LOG = Logger.getLogger(ViewerHandler.class.getName());
    /** Hash map key for the viewer uuid. */
    private static final String VIEWER_UUID_KEY = "vieweruuid";

    /** Viewer database connection manager. */
    private final ViewerStoreDBUtil viewerStore;

    /**
     * Store the viewer's database.
     *
     * @param args      Arguments hash map containing the information needed to store
     *                  the viewer database.
     * @return          true if we succeed; false otherwise.
     */
    @Override
    public HashMap<String, String> storeViewerDatabase(HashMap<String, String> args)
    {
        LOG.info("request to storeViewerDatabase");

        HashMap<String, String> results = new HashMap<String, String>();

        String viewerID = args.get(VIEWER_UUID_KEY);
        if (viewerID == null)
        {
            BogUtil.writeErrorMsgInBOG("no viewer UUID found", results);
            return results;
        }

        // we have a valid exec run ID, so we can set the ID label.
        setIDLabel(StringUtil.createLogViewerIDString(viewerID));

        // write the uuid in the results
        results.put(VIEWER_UUID_KEY, viewerID);

        String viewerPath = args.get("viewerdbpath");
        if (viewerPath == null)
        {
            BogUtil.writeErrorMsgInBOG("no viewer db path found", results);
            return results;
        }

        // now the checksum - compute it if necessary
        String viewerChecksum = args.get("viewerdbchecksum");
        if (viewerChecksum == null)
        {
            LOG.debug("checksum not passed as argument; quartermaster doing the calculation." + idLabel);
            try
            {
                viewerChecksum = CheckSumUtil.getFileCheckSumSHA512(viewerPath);
            }
            catch (IOException e)
            {
                // unable to compute the checksum
                String msg = "problem computing checksum: " + e.getMessage();
                handleError(results, msg);
                return results;
            }
        }

        // let's set up the data base connection
        if(!initViewerStoreConnection(runDBTest))
        {
            BogUtil.writeErrorMsgInBOG("problem initializing database connection", results);
            cleanup();
            return results;
        }

        LOG.debug("preparing to store the viewer database" + idLabel);

        try
        {
            boolean success = viewerStore.storeViewerDatabase(viewerID, viewerPath, viewerChecksum);
            if (!success)
            {
                // something failed - the error message is in the log file.
                String msg = "error when attempting to store database.";
                handleError(results, msg);
                return results;
            }
        }
        catch (SQLException e)
        {
            String msg = "SQL exception when storing viewer database: " + e.getMessage();
            handleError(results, msg);
            return results;
        }

        cleanup();
        LOG.info("viewer database stored successfully" + idLabel);
        return results;
    }

    /**
     * Update the viewer instance status.
     *
     * @param args      Arguments hash map containing the information we need to update
     *                  the viewer status in the database.
     * @return          true if we succeed; false otherwise.
     */
    @Override
    public HashMap<String, String> updateViewerInstance(HashMap<String, String> args)
    {
        LOG.info("request to updateViewerInstance");

        HashMap<String, String> results = new HashMap<String, String>();

        String viewerID = args.get(VIEWER_UUID_KEY);
        if (viewerID == null)
        {
            BogUtil.writeErrorMsgInBOG("no viewer UUID found", results);
            return results;
        }

        // write the uuid in the results
        results.put(VIEWER_UUID_KEY, viewerID);

        // we have a valid exec run ID, so we can set the ID label.
        setIDLabel(StringUtil.createLogViewerIDString(viewerID));

        String viewerStatus = args.get("viewerstatus");
        if (viewerStatus == null)
        {
            BogUtil.writeErrorMsgInBOG("no viewer status found", results);
            return results;
        }
        String viewerStatusCode = args.get("viewerstatuscode");
        if (viewerStatusCode != null && viewerStatusCode.equalsIgnoreCase("null"))
        {
            viewerStatusCode = null;
        }

        // the address and proxy might be null and this is ok. check for possible "null" strings too.
        String viewerAddress = args.get("vieweraddress");
        if (viewerAddress != null && viewerAddress.equalsIgnoreCase("null"))
        {
            viewerAddress = null;
        }

        String viewerProxy = args.get("viewerproxyurl");
        if (viewerProxy != null && viewerProxy.equalsIgnoreCase("null"))
        {
            viewerProxy = null;
        }

        // let's set up the data base connection
        if(!initViewerStoreConnection(runDBTest))
        {
            BogUtil.writeErrorMsgInBOG("problem initializing database connection", results);
            cleanup();
            return results;
        }

        LOG.debug("preparing to update the view instance" + idLabel);

        try
        {
            boolean success = viewerStore.updateViewerInstance(viewerID, viewerStatus, viewerStatusCode,
                                                               viewerAddress, viewerProxy);
            if (!success)
            {
                // something failed - the error message is in the log file.
                String msg = "error when attempting to update viewer instance.";
                handleError(results, msg);
                return results;
            }
        }
        catch (SQLException e)
        {
            String msg = "SQL exception when updating viewer instance: " + e.getMessage();
            handleError(results, msg);
            return results;
        }

        cleanup();
        LOG.info("viewer instance updated successfully" + idLabel);
        return results;
    }

    /**
     * Handle an error by logging it, writing it to the hash map and then closing the
     * database connections.
     *
     * @param bog       The hash map.
     * @param msg       Error message string.
     */
    private void handleError(HashMap<String, String> bog, String msg)
    {
        LOG.error(msg + idLabel);
        BogUtil.writeErrorMsgInBOG(msg, bog);
        cleanup();
    }

    /**
     * Close all of the database connections so we can exit cleanly.
     */
    private void cleanup()
    {
        viewerStore.cleanup();
    }

    /**
     * Initialize the viewer store database connection.
     *
     * @param doTest    Should we run a connection test or not?
     * @return          true the database connection is established; false otherwise.
     */
    private boolean initViewerStoreConnection(boolean doTest)
    {
        // register the JDBC
        if (!viewerStore.registerJDBC())
        {
            return false;
        }

        // make the database connection
        if (!viewerStore.makeDBConnection())
        {
            return false;
        }

        if (doTest)
        {
            // test the connection
            LOG.info(viewerStore.doVersionTest() + idLabel);
        }

        return true;
    }

    /**
     * Constructor.
     */
    public ViewerHandler()
    {
        super();
        LOG.debug("*** The Viewer Handler is on the job ***");

        viewerStore = new ViewerStoreDBUtil(dbURL + "viewer_store", dbUser, dbText);
    }

}
