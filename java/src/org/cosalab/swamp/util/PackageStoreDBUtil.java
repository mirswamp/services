// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2016 Software Assurance Marketplace

package org.cosalab.swamp.util;

import org.apache.log4j.Logger;

import java.sql.CallableStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Types;
import java.util.ArrayList;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 8/29/13
 * Time: 10:16 AM
 */
public class PackageStoreDBUtil extends DBUtil
{
    /** Set up logging for this class. */
    private static final Logger LOG = Logger.getLogger(PackageStoreDBUtil.class.getName());

    /**
     * Constructor.
     *
     * @param url   Database URL.
     * @param user  Database user name.
     * @param pass  Database password.
     */
    public PackageStoreDBUtil(String url, String user, String pass)
    {
        super(url, user, pass);

        // if we need to see the results set metadata, uncomment the following line
//        logMetaDataFlag = true;
    }

    /**
     * Process the results set into a list of package data objects. Each object correpsonds to
     * one row in the results set.
     *
     * @param resultSet         The results set returned from the database.
     * @return                  A List of PackageData objects.
     * @throws SQLException
     * @throws InvalidDBObjectException
     */
    private ArrayList<PackageData> processResults(ResultSet resultSet) throws SQLException, InvalidDBObjectException
    {
        if (logMetaDataFlag)
        {
            logResultSetMetaData(resultSet);
        }
        ArrayList<PackageData> results = new ArrayList<PackageData>();
        while (resultSet.next())
        {
            PackageData data = new PackageData(resultSet);
            results.add(data);
        }

        return results;
    }

    /**
     * Retrieve the data for a single package form the database and return it as a list of package data objects.If
     * the package could not be found, the list will be empty. Otherwise the list should have a single object, unless
     * there is a database issue which causes multiple objects to be returned.
     *
     * @param versionID         The package version ID (uuid).
     * @return                  A List of PackageData objects.
     * @throws SQLException
     * @throws InvalidDBObjectException
     */
    public ArrayList<PackageData> getSinglePackage(String versionID) throws SQLException, InvalidDBObjectException
    {
        CallableStatement call = null;
        ResultSet resultSet = null;
        ArrayList<PackageData> results = new ArrayList<PackageData>();

        try
        {
            call = connection.prepareCall("{call package_store.select_pkg_version(?)}");
            call.setString(1, versionID);
            LOG.debug("call package_store.select_pkg_version(?) with arg: " + versionID + idLabel);

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
        catch (InvalidDBObjectException e)
        {
            LOG.error("InvalidDBObjectException with package_store.select_pkg_version(): " + e.getMessage()
                              + idLabel);
            throw e;
        }
        catch (SQLException e)
        {
            LOG.error("SQLException with package_store.select_pkg_version(): " + e.getMessage() + idLabel);
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
     * Find the dependency information for a package on a particular platform.
     *
     * @param packageVersionID      The package version uuid.
     * @param platformVersionID     The platform version uuid.
     * @return                      A string with the dependency information.
     * @throws SQLException
     */
    public String getDependencyList(String packageVersionID, String platformVersionID) throws SQLException
    {
        CallableStatement call = null;
        String result = "";

        try
        {
            call = connection.prepareCall("{call package_store.fetch_pkg_dependency(?,?,?,?)}");
            call.setString(1, packageVersionID);
            call.setString(2, platformVersionID);
            call.registerOutParameter(3, Types.CHAR);
            call.registerOutParameter(4, Types.VARCHAR);
            LOG.debug("call package_store.fetch_pkg_dependency(?,?,?,?) with args: " + packageVersionID
                              + " " + platformVersionID + idLabel);

            int flag = call.executeUpdate();

            String found = call.getString(3);
            LOG.debug("found = " + found + " flag = " + flag + idLabel);

            if (found.equalsIgnoreCase("Y"))
            {
                result = call.getString(4);
            }
        }
        catch (SQLException e)
        {
            LOG.error("SQLException with package_store.fetch_pkg_dependency(): " + e.getMessage() + idLabel);
            throw e;
        }
        finally
        {
            closeStatement(call);
        }

        return result;
    }

}
