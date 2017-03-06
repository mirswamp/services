// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.util;

import org.apache.log4j.Logger;

import java.sql.CallableStatement;
import java.sql.SQLException;
import java.sql.Types;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 1/27/14
 * Time: 11:38 AM
 */
public class ViewerStoreDBUtil extends DBUtil
{
    /** Set up logging for this class. */
    private static final Logger LOG = Logger.getLogger(ViewerStoreDBUtil.class.getName());

    /**
     * Constructor.
     *
     * @param url       Database URL.
     * @param user      Database user name.
     * @param pass      Database password.
     */
    public ViewerStoreDBUtil(String url, String user, String pass)
    {
        super(url, user, pass);
    }

    /**
     * Store the viewer database.
     *
     * @param uuid          The uuid.
     * @param path          The path to the viewer database.
     * @param checksum      The checksum f the viewer database.
     * @return              true if the operation succeeds; false otherwise.
     * @throws SQLException
     */
    public boolean storeViewerDatabase(String uuid, String path, String checksum) throws SQLException
    {
        CallableStatement call = null;
        boolean results = false;
        LOG.debug("call to storeViewerDatabase" + idLabel);

        try
        {
            call = connection.prepareCall("{call viewer_store.store_viewer(?,?,?,?)}");

            call.setString(1, uuid);
            call.setString(2, path);
            call.setString(3, checksum);
            call.registerOutParameter(4, Types.VARCHAR);

            // no result set is being returned, so we can use the executeUpdate() method.
            call.executeUpdate();

            String flag = call.getString(4);
            results = checkDatabaseResult(flag, "viewer_store.store_viewer: ");
        }
        catch (SQLException e)
        {
            // rethrow the exception to handle it elsewhere. need to catch it so that
            // we can make sure that we close up the resources.
            LOG.error("SQLException in storeViewerDatabase(): " + e.getMessage() + idLabel);
            throw e;
        }
        finally
        {
            closeStatement(call);
        }

        return results;
    }

    /**
     * Update the viewer instance.
     *
     * @param uuid          The instance uuid.
     * @param status        The status.
     * @param statusCode    The status code.
     * @param address       The address.
     * @param url           The URL.
     * @return              true if the update succeeds; false otherwise.
     * @throws SQLException
     */
    public boolean updateViewerInstance(String uuid, String status, String statusCode, String address, String url)
            throws SQLException
    {
        CallableStatement call = null;
        boolean results = false;
        LOG.debug("call to updateViewerInstance" + idLabel);

        try
        {
            call = connection.prepareCall("{call viewer_store.update_viewer_instance(?,?,?,?,?,?)}");
            int code = 0;
            if (statusCode != null)
            {
                try
                {
                    code = Integer.parseInt(statusCode);
                }
                catch (NumberFormatException nfe)
                {
                    code = 0;
                }
            }
            call.setString(1, uuid);
            call.setString(2, status);
            call.setInt(3, code);
            call.setString(4, address);
            call.setString(5, url);
            call.registerOutParameter(6, Types.VARCHAR);

            // no result set is being returned, so we can use the executeUpdate() method.
            call.executeUpdate();

            String flag = call.getString(6);
            results = checkDatabaseResult(flag, "viewer_store.update_viewer_instance: ");
        }
        catch (SQLException e)
        {
            // rethrow the exception to handle it elsewhere. need to catch it so that
            // we can make sure that we close up the resources.
            LOG.error("SQLException in updateViewerInstance(): " + e.getMessage() + idLabel);
            throw e;
        }
        finally
        {
            closeStatement(call);
        }

        return results;
    }

    /**
     * Check the string value returned by a database query to see if the query succeeded or failed.
     *
     * @param value     Value returned from the database.
     * @param message   String used for logging purposes.
     * @return          true if the query succeeded, false otherwise.
     */
    private boolean checkDatabaseResult(String value, String message)
    {
        boolean results;
        if (value.equalsIgnoreCase(DB_SUCCESS))
        {
            results = true;
        }
        else
        {
            LOG.error("DB error: " + message + value + idLabel);
            results = false;
        }
        return results;
    }

}
