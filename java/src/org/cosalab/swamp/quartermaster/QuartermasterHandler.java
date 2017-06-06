// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.quartermaster;

import org.apache.log4j.Logger;
import org.cosalab.swamp.util.BogUtil;
import org.cosalab.swamp.util.CheckSumUtil;
import org.cosalab.swamp.util.InvalidDBObjectException;
import org.cosalab.swamp.util.PackageData;
import org.cosalab.swamp.util.PackageStoreDBUtil;
import org.cosalab.swamp.util.PlatformData;
import org.cosalab.swamp.util.PlatformStoreDBUtil;
import org.cosalab.swamp.util.StringUtil;
import org.cosalab.swamp.util.ToolData;
import org.cosalab.swamp.util.ToolShedDBUtil;

import java.io.IOException;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson@morgridgeinstitute.org
 * Date: 7/15/13
 * Time: 11:09 AM
 */

// you may want to run the QuartermasterServer with the JVM argument -Dtesting=true

public class QuartermasterHandler extends BaseQuartermasterHandler implements Quartermaster
{
    /** Set up logging for the quartermaster handler class. */
    private static final Logger LOG = Logger.getLogger(QuartermasterHandler.class.getName());

    /** Tool database connection manager. */
    private final ToolShedDBUtil toolShed;
    /** Package database connection manager. */
    private final PackageStoreDBUtil packageStore;
    /** Platform database connection manager. */
    private final PlatformStoreDBUtil platformStore;

    /** Tool uuid. */
    private String toolID;
    /** Package uuid. */
    private String packageID;
    /** Platform uuid. */
    private String platformID;

    /**
     *      The latest set of platform data - this is needed to retrieve the correct version of some tools.
     *      This is updated whenever the platform information is fetched from the database
     */
    private PlatformData currentPlatformData;

    /** Similar stored data for the package. */
    private PackageData currentPackageData;

    /** Are we running the quartermaster handler in test mode or not? */
    private Boolean inTestMode;


    /**
     * Get the bill of goods for this execution record.
     *
     * @param args      Arguments hash map containing the information we need
     *                  to create the bill of goods.
     * @return          true if we create a valid bill of goods; false otherwise.
     */
    @Override
    public HashMap<String, String> getBillOfGoods(HashMap<String, String> args)
    {
        LOG.info("request to getBillOfGoods");
        HashMap<String, String> bog = new HashMap<>();

        // write the version to the BOG
        BogUtil.writeVersionInBOG(bog);
        inTestMode = Boolean.parseBoolean(System.getProperty("testing"));
        String execRunID = args.get("execrunid");
        if (execRunID == null)
        {
            BogUtil.writeErrorMsgInBOG("no execution run ID found", bog);
            return bog;
        }

        // put this in the bog now, so we'll know which run went bad if there are errors and we return early.
        bog.put("execrunid", execRunID);

        // we have a valid exec run ID, so we can set the ID label.
        setIDLabel(StringUtil.createLogExecIDString(execRunID));

        // write the project id and the user id to the bog.
        // Validation should have been done by the Agent Dispatcher.
        bog.put("projectid", args.get("projectid"));
        bog.put("userid", args.get("userid"));

        // validate input parameters
        if(!checkQuartermasterInput(args, bog))
        {
            return bog;
        }

        // let's set up the data base connections
        if(!initConnections(runDBTest))
        {
            handleError(bog, "problem initializing database connections");
            return bog;
        }

        // we need to find the platform first, so that we can use the platform
        // information in the tool query.
        if (!retrievePlatform(bog))
        {
            return bog;
        }

        // ok, now let's do the package
        if (!retrievePackage(bog))
        {
            return bog;
        }

        // let's grab the tool information
        if (!retrieveTool(bog))
        {
            return bog;
        }

        LOG.debug("return BOG: " + idLabel);
        for (Map.Entry<String, String> entry : bog.entrySet())
        {
            LOG.debug("\tKey = " + entry.getKey() + ", Value = " + entry.getValue());
        }

        // clean up
        cleanup();
        return bog;
    }

    /**
     * Check the tool, platform and package uuids for problems before using them to
     * retrieve information from the database.
     *
     * @param args      Hash map with the uuids.
     * @param bog       Bill of goods hash map.
     * @return          true if all the uuids are present in the arguments hash map; false otherwise.
     */
    private boolean checkQuartermasterInput(HashMap<String, String> args, HashMap<String, String> bog)
    {
        boolean result = true;

        platformID = args.get("platformid");
        if (platformID == null)
        {
            bog.put(ERROR_KEY, "no platform ID found");
            result = false;
        }

        toolID = args.get("toolid");
        if (toolID == null)
        {
            bog.put(ERROR_KEY, "no tool ID found");
            result = false;
        }

        packageID = args.get("packageid");
        if (packageID == null)
        {
            bog.put(ERROR_KEY, "no package ID found");
            result = false;
        }

        return result;
    }

    /**
     * Retrieve the platform information and write it to the bill of goods.
     *
     * @param bog   Bill of goods hash map.
     * @return      true if we succeed; false otherwise.
     */
    private boolean retrievePlatform(HashMap<String, String> bog)
    {
        // clear the current platform data, just to be sure that we're in a consistent state
        currentPlatformData = null;

        try
        {
            ArrayList<PlatformData> platformSet = platformStore.getSinglePlatform(platformID);
            if (platformSet.size() > 1)
            {
                // this should never happen, but if it does, we will assume that the
                // platform we want is the first one in the set and keep going.
                LOG.warn("platform store has retrieved more than one platform" + idLabel);
            }
            else if (platformSet.isEmpty())
            {
                String msg = "platform store has not retrieved the requested platform";
                handleError(bog, msg);
                return false;
            }

            // this is the platform - write it to the bog
            currentPlatformData = platformSet.get(0);
            BogUtil.writePlatformInBOG(currentPlatformData, bog);
        }
        catch (SQLException e)
        {
            String msg = "problem retrieving platform from platform store: " + e.getMessage();
            handleError(bog, msg);
            return false;
        }

        return true;
    }

    /**
     * Retrieve the package information from the database and write it in the bill of goods.
     *
     * @param bog   Bill of goods hash map.
     * @return      true if we succeed; false otherwise.
     */
    private boolean retrievePackage(HashMap<String, String> bog)
    {
        currentPackageData = null;

        boolean success = false;

        try
        {
            ArrayList<PackageData> packageSet = packageStore.getSinglePackage(packageID);
            if (packageSet.size() > 1)
            {
                LOG.warn("package store has retrieved more than one package" + idLabel);
            }
            else if (packageSet.isEmpty())
            {
                String msg = "package store has not retrieved the requested package";
                handleError(bog, msg);
                return false;
            }

            // this is the package
            PackageData pack = packageSet.get(0);
            if (!inTestMode)
            {
                String checksum = CheckSumUtil.getFileCheckSumSHA512(pack.getPath());
                if (!checksum.equalsIgnoreCase(pack.getCheckSum()))
                {
                    // check sums don't match
                    String msg = StringUtil.formatChecksumErrorMsg("check sum error on package", pack.getPath(),
                                                                   pack.getCheckSum(), checksum);
                    handleError(bog, msg);
                    return false;
                }
            }
            // write out the package info to the bog
            BogUtil.writePackageInBOG(pack, bog);
            currentPackageData = pack;

            // now check for the package dependency list, this writes the list to the bog too.
            if (retrievePackageDependencyList(pack, bog))
            {
                success = true;
            }
        }
        catch (InvalidDBObjectException e)
        {
            String msg = "invalid package in database: " + e.getMessage();
            handleError(bog, msg);
        }
        catch (SQLException e)
        {
            String msg = "problem retrieving package from package store: " + e.getMessage();
            handleError(bog, msg);
        }
        catch (IOException e)
        {
            String msg = "problem computing checksum of package: " + e.getMessage();
            handleError(bog, msg);
        }

        return success;
    }

    /**
     * Retrieve the package dependency list and write it in the bill of goods.
     *
     * @param pack          Package data object.
     * @param bog           Bill of goods hash map.
     * @return              true if we succeed; false otherwise.
     * @throws SQLException
     */
    private boolean retrievePackageDependencyList(PackageData pack, HashMap<String, String> bog)
            throws SQLException
    {
        boolean success = false;

        // check to make sure that we have valid platform data; we'll need the platform version uuid
        // in order to retrieve the dependency list from the data base.
        if (currentPlatformData == null)
        {
            String msg = "package store can not retrieve dependency list: missing platform information";
            handleError(bog, msg);
            return success;
        }

        try
        {
            String depends = packageStore.getDependencyList(pack.getVersionID(),
                                                            currentPlatformData.getVersionID());
            BogUtil.writeDependencyListInBOG(StringUtil.validateStringArgument(depends), bog);
            success = true;
        }
        catch (SQLException e)
        {
            String msg = "problem retrieving package dependency list: " + e.getMessage();
            LOG.error(msg + idLabel);
            throw e;
        }

        return success;
    }

    /**
     * Retrieve the tool information from the database and write it in the bill of goods.
     *
     * @param bog       Bill of goods hash map.
     * @return          true if we succeed; false otherwise.
     */
    private boolean retrieveTool(HashMap<String, String> bog)
    {
        boolean success = false;

        // check to make sure that we have valid platform data; we'll need the platform version uuid
        // in order to retrieve the tool from the tool shed.
        if (currentPlatformData == null)
        {
            String msg = "tool shed can not retrieve tool: missing platform information";
            handleError(bog, msg);
            return false;
        }

        if (currentPackageData == null)
        {
            String msg = "tool shed can not retrieve tool: missing package information";
            handleError(bog, msg);
            return false;
        }

        try
        {
            ArrayList<ToolData> toolSet = toolShed.getSingleTool(toolID,
                                                                 currentPlatformData.getVersionID(),
                                                                 currentPackageData.getVersionID());
            if (toolSet.size() > 1)
            {
                LOG.warn("tool shed has retrieved more than one tool" + idLabel);
            }
            else if (toolSet.isEmpty())
            {
                String msg = "tool shed has not retrieved the requested tool";
                handleError(bog, msg);
                return false;
            }

            // this is the tool
            ToolData tool = toolSet.get(0);
            if (!inTestMode)
            {
                String checksum = CheckSumUtil.getFileCheckSumSHA512(tool.getPath());
                if (!checksum.equalsIgnoreCase(tool.getCheckSum()))
                {
                    // check sums don't match
                    String msg = StringUtil.formatChecksumErrorMsg("check sum error on tool!", tool.getPath(),
                                                                   tool.getCheckSum(), checksum);
                    handleError(bog, msg);
                    return false;
                }
            }
            // write the tool info to the bog
            BogUtil.writeToolInBOG(tool, bog);
            success = true;
        }
        catch (InvalidDBObjectException e)
        {
            String msg = "invalid tool in database: " + e.getMessage();
            handleError(bog, msg);
        }
        catch (SQLException e)
        {
            String msg = "problem retrieving tool from tool shed: " + e.getMessage();
            handleError(bog, msg);
        }
        catch (IOException e)
        {
            String msg = "problem computing checksum of tool: " + e.getMessage();
            handleError(bog, msg);
        }

        return success;
    }

    /**
     * Handle an error by logging it, writing it to the bill of goods and then closing the
     * database connections.
     *
     * @param bog       Bill of goods hash map.
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
        toolShed.cleanup();
        packageStore.cleanup();
        platformStore.cleanup();
    }

    /**
     * Initialize database connections for the tool, package and platform stores in the database.
     *
     * @param doTest    Should we run a connection test or not?
     * @return          true if all of the connections are established; false otherwise.
     */
    private boolean initConnections(boolean doTest)
    {
        // first let's deal with the tool shed

        // register the JDBC
        if (!toolShed.registerJDBC())
        {
            return false;
        }

        // make the database connection
        if (!toolShed.makeDBConnection())
        {
            return false;
        }

        // now the package store
        // register the JDBC
        if (!packageStore.registerJDBC())
        {
            return false;
        }

        // make the database connection
        if (!packageStore.makeDBConnection())
        {
            return false;
        }

        // finally the platform store
        // register the JDBC
        if (!platformStore.registerJDBC())
        {
            return false;
        }

        // make the database connection
        if (!platformStore.makeDBConnection())
        {
            return false;
        }

        if (doTest)
        {
            // test the connections
            LOG.info(toolShed.doVersionTest() + idLabel);
            LOG.info(packageStore.doVersionTest() + idLabel);
            LOG.info(platformStore.doVersionTest() + idLabel);
        }

        return true;
    }

    /**
     * Constructor.
     */
    public QuartermasterHandler()
    {
        super();
        LOG.debug("*** The Quartermaster is on the job ***");

        toolShed = new ToolShedDBUtil(dbURL + "tool_shed", dbUser, dbText);
        packageStore = new PackageStoreDBUtil(dbURL + "package_store", dbUser, dbText);
        platformStore = new PlatformStoreDBUtil(dbURL + "platform_store", dbUser, dbText);

        // initialize this stuff to something harmless
        currentPlatformData = null;
        currentPackageData = null;
    }

    /**
     * Constructor for use in situations where we must pass the database parameters
     * to the Quartermaster handler instead of obtaining them from the server.
     *
     * @param url       The database URL.
     * @param user      The database username.
     * @param word      The database uer password.
     */
    public QuartermasterHandler(String url, String user, String word)
    {
        super(url, user, word);
        LOG.debug("*** The Quartermaster is on the job ***");

        toolShed = new ToolShedDBUtil(dbURL + "tool_shed", dbUser, dbText);
        packageStore = new PackageStoreDBUtil(dbURL + "package_store", dbUser, dbText);
        platformStore = new PlatformStoreDBUtil(dbURL + "platform_store", dbUser, dbText);

        // initialize this stuff to something harmless
        currentPlatformData = null;
        currentPackageData = null;
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
        toolShed.setIDLabel(idLabel);
        packageStore.setIDLabel(idLabel);
        platformStore.setIDLabel(idLabel);
    }
}
