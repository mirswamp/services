// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2016 Software Assurance Marketplace

package org.cosalab.swamp.util;

import org.apache.log4j.Logger;

import java.sql.CallableStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 8/28/13
 * Time: 3:01 PM
 */
public class ToolShedDBUtil extends DBUtil
{
    /** Set up logging for this class. */
    private static final Logger LOG = Logger.getLogger(ToolShedDBUtil.class.getName());

    /**
     * Constructor.
     *
     * @param url       Database URL.
     * @param user      Database user name.
     * @param pass      Database password.
     */
    public ToolShedDBUtil(String url, String user, String pass)
    {
        super(url, user, pass);

        // if we need to see the results set metadata, uncomment the following line
//        logMetaDataFlag = true;
    }

    /**
     * Create a list of tool data objects from a database result set.
     *
     * @param resultSet         The result set.
     * @return                  The list of tool data objects.
     * @throws SQLException
     * @throws InvalidDBObjectException
     */
    private ArrayList<ToolData> processResults(ResultSet resultSet) throws SQLException, InvalidDBObjectException
    {
        if (logMetaDataFlag)
        {
            logResultSetMetaData(resultSet);
        }
        ArrayList<ToolData> results = new ArrayList<ToolData>();
        while (resultSet.next())
        {
            ToolData tool = new ToolData(resultSet);
            results.add(tool);
        }

        return results;
    }

    /**
     * Retrieve a single tool from the database. This may depend on the platform
     * version and package version.
     *
     * @param versionID             Tool version uuid.
     * @param platformVersionID     Platform version uuid.
     * @param packageVersionID      Package version uuid.
     * @return                      List of tool data objects. the list should contain only
     *                              one object, but may have multiple objects or be empty.
     * @throws SQLException
     * @throws InvalidDBObjectException
     */
    public ArrayList<ToolData> getSingleTool(String versionID, String platformVersionID, String packageVersionID)
            throws SQLException, InvalidDBObjectException
    {
        CallableStatement call = null;
        ResultSet resultSet = null;
        ArrayList<ToolData> results = new ArrayList<ToolData>();

        try
        {
            call = connection.prepareCall("{call tool_shed.select_tool_version(?,?,?)}");
            call.setString(1, versionID);
            call.setString(2, platformVersionID);
            call.setString(3, packageVersionID);
            LOG.debug("call tool_shed.select_tool_version(?,?,?) with args: " + versionID + " and " +
                              platformVersionID + " and " + packageVersionID + idLabel);

            boolean update = call.execute();
            if (update)
            {
                resultSet = call.getResultSet();
                results = processResults(resultSet);
            }
            else
            {
                LOG.error("problem executing the stored procedure: tool_shed.select_tool_version(?,?)" + idLabel);
            }
        }
        catch (InvalidDBObjectException e)
        {
            LOG.error("InvalidDBObjectException in getSingleTool(): " + e.getMessage() + idLabel);
            throw e;
        }
        catch (SQLException e)
        {
            LOG.error("SQLException in getSingleTool(): " + e.getMessage() + idLabel);
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
