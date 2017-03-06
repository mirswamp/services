// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.util;

import org.apache.log4j.Logger;

import java.sql.CallableStatement;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.util.HashMap;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 3/8/14
 * Time: 8:24 PM
 */
public class GatorDBUtil extends DBUtil
{
    /** Set up logging for this class. */
    private static final Logger LOG = Logger.getLogger(GatorDBUtil.class.getName());

    /** For convenience, copy the hashmap "error" key value locally. */
    private static final String ERROR_KEY = StringUtil.ERROR_KEY;

    /** Use this to separate fields in the Gator output. */
    private static final char GATOR_SEPARATOR = '|';

    /**
     * Constructor.
     *
     * @param url       Database URL.
     * @param user      Database user name.
     * @param pass      Database password.
     */
    public GatorDBUtil(String url, String user, String pass)
    {
        super(url, user, pass);
    }

    /**
     * Create a list of tools from the database.
     *
     * @param results   Hash map to hold the tool list.
     */
    public void makeToolList(HashMap<String, String> results)
    {
	    CallableStatement call = null;
        ResultSet resultSet = null;
        try
        {
            call = connection.prepareCall("{call tool_shed.select_all_pub_tools_and_vers}");
            LOG.debug("call tool_shed.select_all_pub_tools_and_vers" + idLabel);

            boolean update = call.execute();
            if (update)
            {
                resultSet = call.getResultSet();
                int rows = handleResultSet(resultSet, results);
                results.put("rows", Integer.toString(rows));
            }
            else
            {
                LOG.error("problem executing the tool shed stored procedure" + idLabel);
            }
        }

        catch (SQLException e)
        {
            String msg = "problem executing query: " + e.getMessage();
            LOG.error(msg + idLabel);
            results.put(ERROR_KEY, msg);
        }
        
        finally
        {
            closeResultSet(resultSet);
            closeStatement(call);
        }
    }

    /**
     * Create a list of packages from the database.
     *
     * @param results   Hash map to hold the package list.
     */
    public void makePackageList(HashMap<String, String> results)
    {
	    CallableStatement call = null;
        ResultSet resultSet = null;
        try
        {
            call = connection.prepareCall("{call package_store.select_all_pub_pkgs_and_vers}");
            LOG.debug("call package_store.select_all_pub_pkgs_and_vers" + idLabel);

            boolean update = call.execute();
            if (update)
            {
                resultSet = call.getResultSet();
                int rows = handleResultSet(resultSet, results);
                results.put("rows", Integer.toString(rows));
            }
            else
            {
                LOG.error("problem executing the package store stored procedure" + idLabel);
            }
        }
        
        catch (SQLException e)
        {
            String msg = "problem executing query: " + e.getMessage();
            LOG.error(msg + idLabel);
            results.put(ERROR_KEY, msg);
        }
        
        finally
        {
            closeResultSet(resultSet);
            closeStatement(call);
        }
    }

    /**
     * Create a list of platforms from the database.
     *
     * @param results   Hash map to hold the platform list.
     */
    public void makePlatformList(HashMap<String, String> results)
    {
	    CallableStatement call = null;
        ResultSet resultSet = null;
        try
        {
            call = connection.prepareCall("{call platform_store.select_all_pub_platforms_and_vers}");
            LOG.debug("call platform_store.select_all_pub_platforms_and_vers" + idLabel);

            boolean update = call.execute();
            if (update)
            {
                resultSet = call.getResultSet();
                int rows = handleResultSet(resultSet, results);
                results.put("rows", Integer.toString(rows));
            }
            else
            {
                LOG.error("problem executing the platform store stored procedure" + idLabel);
            }

        }
        catch (SQLException e)
        {
            String msg = "problem executing query: " + e.getMessage();
            LOG.error(msg + idLabel);
            results.put(ERROR_KEY, msg);
        }
        
        finally
        {
            closeResultSet(resultSet);
            closeStatement(call);
        }
    }

    private int handleResultSet(ResultSet resultSet, HashMap<String, String> results) throws SQLException
    {
        StringBuffer buffer;
        ResultSetMetaData meta = resultSet.getMetaData();
        int cols = meta.getColumnCount();
        int rows = 0;
        LOG.debug("Result Set has " + cols + " columns" + idLabel);
        buffer = new StringBuffer();
        for (int i = 1; i <= cols; i++)
        {
            buffer.append(meta.getColumnLabel(i));
            if (i < cols)
            {
                buffer.append(GATOR_SEPARATOR);
            }
            LOG.debug("column name: " + meta.getColumnName(i) +
                              " column label: " + meta.getColumnLabel(i) +
                              " column type: " + meta.getColumnTypeName(i) +
                              " table name: " + meta.getTableName(i));
        }

        results.put(Integer.toString(rows), buffer.toString());

        while (resultSet.next())
        {
            buffer = new StringBuffer();
            for (int i = 1; i < cols; i++)
            {

                buffer.append(fetchString(resultSet, i));
                buffer.append(GATOR_SEPARATOR);
            }
            buffer.append(fetchString(resultSet, cols));

            rows++;
            results.put(Integer.toString(rows), buffer.toString());
        }

        results.put("nitems", Integer.toString(rows+1));

        return rows;
    }

    /**
     * Return a non-empty and non-null value from a column of ResultSet
     * @param resultSet The ResultSet to query
     * @param column The column of result set to fetch
     * @return The value in column <code>column</code> of <code>resultSet</code> or the string 'null' if the value
     * is null or empty.
     * @throws SQLException
     */
    private String fetchString(final ResultSet resultSet, int column)
            throws SQLException
    {
        return StringUtil.validateStringArgument(resultSet.getString(column));
    }

}
