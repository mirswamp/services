// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.quartermaster;

import org.apache.log4j.Logger;
import org.cosalab.swamp.dispatcher.AgentDispatcher;
import org.cosalab.swamp.util.StringUtil;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 5/5/15
 * Time: 4:03 PM
 */
public class BaseQuartermasterHandler
{
    /** Set up logging for the base quartermaster handler class. */
    private static final Logger LOG = Logger.getLogger(BaseQuartermasterHandler.class.getName());
    /** Hash map key for an error. */
    protected static final String ERROR_KEY = StringUtil.ERROR_KEY;

    /** database URL. */
    protected final String dbURL;
    /** database user name. */
    protected final String dbUser;
    /** database password. */
    protected final String dbText;

    /** Do we need to run the database test after connecting or not? */
    protected boolean runDBTest;

    /** String with the run ID for logging. */
    protected String idLabel;

    /**
     * Constructor.
     */
    public BaseQuartermasterHandler()
    {
        dbURL = QuartermasterServer.getDbQuartermasterURL();
        dbUser = QuartermasterServer.getDbQuatermasterUser();
        dbText = QuartermasterServer.getDbQuartermasterPasswd();

        finishSetup();
    }

    /**
     * Constructor.
     */
    public BaseQuartermasterHandler(boolean isDispatcher)
    {
        if (isDispatcher)
        {
            dbURL = AgentDispatcher.getDbURL();
            dbUser = AgentDispatcher.getDbUser();
            dbText = AgentDispatcher.getDbPasswd();

        }
        else
        {
            dbURL = QuartermasterServer.getDbQuartermasterURL();
            dbUser = QuartermasterServer.getDbQuatermasterUser();
            dbText = QuartermasterServer.getDbQuartermasterPasswd();
        }

        finishSetup();
    }

    /**
     * Constructor for use in the situation when we must pass in the database
     * parameters instead of finding them from the server.
     *
     * @param url       The database URL.
     * @param user      The database user name.
     * @param text      The database user password.
     */
    public BaseQuartermasterHandler(String url, String user, String text)
    {
        dbURL = url;
        dbUser = user;
        dbText = text;

        finishSetup();
    }

    /**
     * Helper method for all of the constructors. Validates the database
     * member variables and assigns values to the remaining variables.
     */
    private void finishSetup()
    {
        if (dbURL == null || dbURL.isEmpty())
        {
            LOG.warn("base quartermaster database URL string is null or empty");
        }

        if (dbUser == null || dbUser.isEmpty())
        {
            LOG.warn("base quartermaster database user string is null or empty");
        }

        if(dbText == null || dbText.isEmpty())
        {
            LOG.warn("base quartermaster database password string is null or empty");
        }

        // don't need to run the test unless we are debugging
        runDBTest = false;

        // initially the label state is blank.
        idLabel = " ";
    }

    /**
     * Set the ID label string
     *
     * @param value     The new ID label.
     */
    protected void setIDLabel(String value)
    {
        idLabel = value;
    }
}
