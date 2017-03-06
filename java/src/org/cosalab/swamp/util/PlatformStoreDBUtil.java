// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.util;

import org.apache.log4j.Logger;

import java.sql.CallableStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 9/3/13
 * Time: 9:41 AM
 */
public class PlatformStoreDBUtil extends DBUtil
{
    /** Set up logging for this class. */
    private static final Logger LOG = Logger.getLogger(PlatformStoreDBUtil.class.getName());

    /**
     * Constructor.
     *
     * @param url       Database URL.
     * @param user      Database user name.
     * @param pass      Database password.
     */
    public PlatformStoreDBUtil(String url, String user, String pass)
    {
        super(url, user, pass);

        // if we need to see the results set metadata, uncomment the following line
//        logMetaDataFlag = true;
    }

    /**
     * Make a list of all platforms.
     *
     * @return      The platform list.
     * @throws SQLException
     */
    public ArrayList<PlatformData> makePlatformList() throws SQLException
    {
        CallableStatement call = null;
        ResultSet resultSet = null;
        ArrayList<PlatformData> results = new ArrayList<PlatformData>();

        try
        {
            call = connection.prepareCall("{call platform_store.select_all_pub_platforms_and_vers}");

            boolean update = call.execute();
            if (update)
            {
                resultSet = call.getResultSet();
                results = processResults(resultSet);
            }
            else
            {
                LOG.error("problem executing the stored procedure: platform_store.select_all_public_platforms"
                                  + idLabel);
            }
        }
        catch (SQLException e)
        {
            // we need to catch the SQLException so we can close the call and result set, but we
            // can't handle the error condition here - rethrow the exception
            LOG.error("SQLException in makePlatformList(): " + e.getMessage() + idLabel);
            throw e;
        }
        finally
        {
            closeResultSet(resultSet);
            closeStatement(call);
        }

        return results;
    }

    /**
     * Convert the result set returned from the database into a list of platform data objects.
     *
     * @param resultSet     The result set form the database.
     * @return              The list of platform data objects.
     * @throws SQLException
     */
    private ArrayList<PlatformData> processResults(ResultSet resultSet) throws SQLException
    {
        if (logMetaDataFlag)
        {
            logResultSetMetaData(resultSet);
        }
        ArrayList<PlatformData> results = new ArrayList<PlatformData>();
        while (resultSet.next())
        {
            PlatformData data = new PlatformData(resultSet);
            results.add(data);
        }

        return results;
    }

    /**
     * Return a single platform data object based on the platform version uuid.
     *
     * @param versionID         The platform version uuid.
     * @return                  List of all the platform versions that match the uuid.
     *                          The list may be empty, have one object or multiple objects.
     * @throws SQLException
     */
    public ArrayList<PlatformData> getSinglePlatform(String versionID) throws SQLException
    {
        CallableStatement call = null;
        ResultSet resultSet = null;
        ArrayList<PlatformData> results = new ArrayList<PlatformData>();

        try
        {
            call = connection.prepareCall("{call platform_store.select_platform_version(?)}");
            call.setString(1, versionID);
            LOG.debug("call platform_store.select_platform_version(?) with arg: " + versionID + idLabel);

            boolean update = call.execute();
            if (update)
            {
                resultSet = call.getResultSet();
                results = processResults(resultSet);
            }
            else
            {
                LOG.error("problem executing the stored procedure: call package_store.select_pkg_version(?)"
                                  + idLabel);
            }
        }
        catch (SQLException e)
        {
            // we need to catch the SQLException so we can close the call and result set, but we
            // can't handle the error condition here - rethrow the exception
            LOG.error("SQLException in getSinglePlatform(): " + e.getMessage() + idLabel);
            throw e;
        }
        finally
        {
            closeResultSet(resultSet);
            closeStatement(call);
        }

        return results;
    }

}
