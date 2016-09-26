// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2016 Software Assurance Marketplace

package org.cosalab.swamp.collector;

import org.apache.log4j.Logger;
import org.cosalab.swamp.dispatcher.AgentDispatcher;
import org.cosalab.swamp.util.AssessmentDBUtil;
import org.cosalab.swamp.util.StringUtil;

import java.util.HashMap;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 9/20/13
 * Time: 2:44 PM
 */
public class BaseCollectorHandler
{
    /** Set up logging for this base class. */
    private static final Logger LOG = Logger.getLogger(BaseCollectorHandler.class.getName());
    /** Hash map error key. */
    protected static final String ERROR_KEY = StringUtil.ERROR_KEY;

    /** The database connection management object. */
    protected AssessmentDBUtil assessmentDB;
    /** Do we need to run the database test after connecting or not? */
    protected boolean runDBTest;

    /** String with the run ID for logging. */
    protected String idLabel;

    /**
     * Create the base collector handler object: set the URL, user name and password. The create
     * assessment database utility object.
     */
    public BaseCollectorHandler()
    {
        String dbURL = AgentDispatcher.getDbURL();
        String dbUser = AgentDispatcher.getDbUser();
        String dbText = AgentDispatcher.getDbPasswd();

        if (dbURL == null || dbURL.isEmpty())
        {
            LOG.warn("assessment database URL string is null or empty");
        }

        if (dbUser == null || dbUser.isEmpty())
        {
            LOG.warn("assessment database user string is null or empty");
        }

        if(dbText == null || dbText.isEmpty())
        {
            LOG.warn("assessment database password string is null or empty");
        }

        assessmentDB = new AssessmentDBUtil(dbURL + "assessment", dbUser, dbText);

        // don't need to run the test unless we are debugging
        runDBTest = false;

        // initially the label state is blank.
        idLabel = " ";
    }

    /**
     * If we encounter an error, log it and put the message in the hash map.
     *
     * @param bog       The hash map.
     * @param msg       The error message.
     * @param log       The logger object to use.
     */
    protected void handleError(HashMap<String, String> bog, String msg, Logger log)
    {
        log.error(msg + idLabel);
        bog.put(ERROR_KEY, msg);
    }

    /**
     * Clean up any loose ends when we are finished.
     */
    protected void cleanup()
    {
        assessmentDB.cleanup();
    }

    /**
     * Initialize the database connection.
     *
     * @param doTest    Flag controlling whether we should run the database test after connecting.
     * @return          true if the connection is created successfully; false otherwise.
     */
    protected boolean initConnections(boolean doTest)
    {
        // register the JDBC
        if (!assessmentDB.registerJDBC())
        {
            return false;
        }

        // make the database connection
        if (!assessmentDB.makeDBConnection())
        {
            return false;
        }

        if (doTest)
        {
            // test the connections
            LOG.info(assessmentDB.doVersionTest() + idLabel);
        }

        return true;
    }

    /**
     * Set the ID label string
     *
     * @param value     The new ID label.
     */
    protected void setIDLabel(String value)
    {
        idLabel = value;
        assessmentDB.setIDLabel(idLabel);
    }

}
