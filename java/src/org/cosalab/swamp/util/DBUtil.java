// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2016 Software Assurance Marketplace

package org.cosalab.swamp.util;

import org.apache.log4j.Logger;

import java.sql.*;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 9/3/13
 * Time: 8:57 AM
 */

/**
 * This is the base class for the database utility classes. This provides the basic logic
 * for making the db connection, managing the connection and closing the connection.
 * There is also a simple connection test that returns the version of the database.
 */

public class DBUtil
{
    /** Set up logging for this class. */
    private static final Logger LOG = Logger.getLogger(DBUtil.class.getName());

    /** Flag used for a successful data base operation. */
    protected static final String DB_SUCCESS = "SUCCESS";

    /** The database connection. */
    protected Connection connection;

    /** The database URL. */
    protected String dbURL;
    /** The database user. */
    protected String dbUser;
    /** The database password. */
    protected String dbPasswd;

    /** Is the connection active? */
    protected boolean connectionActive;
    /** Should we log the meta data for any results we obtain? */
    protected boolean logMetaDataFlag;

    /** ID String for logging purposes. */
    protected String idLabel;

    /**
     * Create a new DBUtil object.
     *
     * @param url       The URL of the database.
     * @param user      The database username.
     * @param pass      The database password.
     */
    public DBUtil(final String url, final String user, final String pass)
    {
        // set the url, user and password needed to access the database
        dbURL = url;
        dbUser = user;
        dbPasswd = pass;

        // this flag keeps track of the connection status
        connectionActive = false;

        // flag used by the subclasses when deciding to LOG the result set metadata
        logMetaDataFlag = false;

        // set the ID label to a blank string initially
        idLabel = " ";
    }

    /**
     * Register the JDBC driver. We use the Maria DB driver.
     *
     * @return  true if we succeed, false if we fail
     */
    public boolean registerJDBC()
    {
        // register the JDBC driver
        try
        {
            Class.forName("org.mariadb.jdbc.Driver");
            LOG.debug("MariaDB JDBC driver registered" + idLabel);
        }
        catch (ClassNotFoundException e)
        {
            final String msg = "JDBC driver not found: " + e.getMessage();
            LOG.error(msg + idLabel);
            return false;
        }
        return true;
    }

    /**
     * Make the connection to the database. Use the url, user and password set
     * in the constructor.
     *
     * @return true if we succeed, false if we fail.
     */
    public boolean makeDBConnection()
    {
        try
        {
            connection = DriverManager.getConnection(dbURL, dbUser, dbPasswd);
        }
        catch (SQLException exception)
        {
            String msg = "Connection failed: " + exception.getMessage();
            LOG.error(msg + idLabel);
            return false;
        }

        connectionActive = true;
        return true;
    }

    /**
     * Clean up anything that is open.
     * If the connection is active we try to close it.
     */
    public void cleanup()
    {
        if (connectionActive)
        {
            try
            {
                connection.close();
            }
            catch (SQLException e)
            {
                final String msg = "problems closing connection: " + e.getMessage();
                LOG.error(msg + idLabel);
            }
        }
    }

    /**
     * Perform the simple version test. The connection needs to be active for this to work.
     *
     * @return a string with the version result or an error message
     */
    public String doVersionTest()
    {
        if (!connectionActive)
        {
            return "error: no active database connection";
        }

        Statement statement = null;
        ResultSet resultSet = null;
        String value = "error running version test";
        try
        {
            statement = connection.createStatement();
            resultSet = statement.executeQuery("SELECT VERSION()");
            if (resultSet.next())
            {
                String dbVersion = resultSet.getString(1);
                String msg = "test query: DB version = " + dbVersion;
                LOG.info(msg + idLabel);
                value = msg;
            }
        }
        catch (SQLException e)
        {
            String msg = "problem executing version test query: " + e.getMessage();
            LOG.error(msg + idLabel);
        }
        finally
        {
            closeResultSet(resultSet);
            closeStatement(statement);
        }

        return value;
    }

    /**
     * Utility method to close a ResultSet.
     *
     * @param resultSet	The ResultSet to be closed.
     */
    protected void closeResultSet(ResultSet resultSet)
    {
        if (resultSet != null)
        {
            try
            {
                resultSet.close();
            }
            catch (SQLException e)
            {
                String msg = "problem closing result set";
                LOG.error(msg + idLabel);
            }
        }
    }

    /**
     * Utility method to LOG the metadata (or at least some of it) for the result set.
     *
     * @param resultSet                the result set
     * @throws SQLException     if we have trouble accessing the metadata
     */
    protected void logResultSetMetaData(final ResultSet resultSet) throws SQLException
    {
        final ResultSetMetaData meta = resultSet.getMetaData();
        final int cols = meta.getColumnCount();
        LOG.info("Result Set has " + cols + " columns" + idLabel);
        for (int i = 1; i <= cols; i++)
        {
            LOG.info("\t" + i + ", column name: " + meta.getColumnName(i) +
                             ", column label: " + meta.getColumnLabel(i) +
                             ", column type: " + meta.getColumnTypeName(i) +
                             " table name: " + meta.getTableName(i));
        }
    }
       
    /**
     * Close a Statement object so that it will not cause a resource leak. This method will
     * also work for PreparedStatement and CallableStatement objects
     * 
     * @param call	The Statement object
     */
    protected void closeStatement(Statement call)
    {
        try
        {
            if (call != null)
            {
                call.close();
            }
        }
        catch (SQLException e)
        {
            String msg = "problem closing statement: " + e.getMessage();
            LOG.error(msg + idLabel);
        }
    }

    /**
     * Set the ID label used for logging.
     *
     * @param label The new label.
     */
    public void setIDLabel(String label)
    {
        idLabel = label;
    }
}
