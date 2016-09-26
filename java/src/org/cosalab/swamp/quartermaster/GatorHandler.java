// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2016 Software Assurance Marketplace

package org.cosalab.swamp.quartermaster;

import org.apache.log4j.Logger;
import org.cosalab.swamp.util.GatorDBUtil;
import org.cosalab.swamp.util.StringUtil;

import java.util.HashMap;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 8/27/13
 * Time: 2:43 PM
 */
public class GatorHandler extends BaseQuartermasterHandler implements Gator
{
    /** Set up logging for this class. */
    private static final Logger LOG = Logger.getLogger(GatorHandler.class.getName());

    /** The gator database connection manager. */
    private final GatorDBUtil gatorDatabase;

    /**
     * Constructor.
     */
    public GatorHandler()
    {
        super();
        LOG.debug("*** Gator Handler is on the job ***");

        gatorDatabase = new GatorDBUtil(dbURL, dbUser, dbText);
    }

    /**
     * Initialize the gator database connection.
     *
     * @param doTest    Flag controls whether we run a simple connection test or not.
     * @return          true if the connection is opened to the database; false otherwise.
     */
    private boolean initDatabaseConnection(boolean doTest)
    {
        // register the JDBC
        if (!gatorDatabase.registerJDBC())
        {
            return false;
        }

        // make the database connection
        if (!gatorDatabase.makeDBConnection())
        {
            return false;
        }

        if (doTest)
        {
            // test the connection
            LOG.info(gatorDatabase.doVersionTest() + idLabel);
        }

        return true;
    }

    /**
     * Make a list of all the tools in the database.
     *
     * @return  Hash map with the list of tools.
     */
    @Override
    public HashMap<String, String> listTools()
    {
        LOG.info("request to listTools");
        HashMap<String, String> results = new HashMap<String, String>();

        // set a dummy id string
        setIDLabel(StringUtil.createLogExecIDString("gator-list-tools"));

        if (initDatabaseConnection(runDBTest))
        {
            gatorDatabase.makeToolList(results);
        }
        else
        {
            results.put(ERROR_KEY, "problem initializing database connection" + idLabel);
        }

        cleanup();
        return results;
    }

    /**
     * Make a list of all of the packages in the database.
     *
     * @return  Hash map with the list of the package data.
     */
    @Override
    public HashMap<String, String> listPackages()
    {
        LOG.info("request to listPackages");
        HashMap<String, String> results = new HashMap<String, String>();

        // set a dummy id string
        setIDLabel(StringUtil.createLogExecIDString("gator-list-packages"));

        if (initDatabaseConnection(runDBTest))
        {
            gatorDatabase.makePackageList(results);
        }
        else
        {
            results.put(ERROR_KEY, "problem initializing database connection" + idLabel);
        }

        cleanup();
        return results;
    }

    /**
     * Make a list of all the platforms in the database.
     *
     * @return  Hash map with the platform data.
     */
    @Override
    public HashMap<String, String> listPlatforms()
    {
        LOG.info("request to listPlatforms");
        HashMap<String, String> results = new HashMap<String, String>();

        // set a dummy id string
        setIDLabel(StringUtil.createLogExecIDString("gator-list-platforms"));

        if (initDatabaseConnection(runDBTest))
        {
            gatorDatabase.makePlatformList(results);
        }
        else
        {
            results.put(ERROR_KEY, "problem initializing database connection" + idLabel);
        }

        cleanup();
        return results;
    }

    /**
     * Close the database connection so we can exit cleanly.
     */
    private void cleanup()
    {
        gatorDatabase.cleanup();
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
        gatorDatabase.setIDLabel(idLabel);
    }

}
