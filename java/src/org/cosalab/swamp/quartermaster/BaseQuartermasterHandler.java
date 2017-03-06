// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.quartermaster;

import org.apache.log4j.Logger;
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

        if (dbURL == null || dbURL.isEmpty())
        {
            LOG.warn("quartermaster database URL string is null or empty");
        }

        if (dbUser == null || dbUser.isEmpty())
        {
            LOG.warn("quartermaster database user string is null or empty");
        }

        if(dbText == null || dbText.isEmpty())
        {
            LOG.warn("quartermaster database password string is null or empty");
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
