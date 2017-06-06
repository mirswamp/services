// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.util;

import org.apache.log4j.Logger;

import java.sql.CallableStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Types;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 9/17/13
 * Time: 11:34 AM
 */
public class AssessmentDBUtil extends DBUtil
{
    /** Set up the logging for this class. */
    private static final Logger LOG = Logger.getLogger(AssessmentDBUtil.class.getName());

    /**
     * Create an AssessmentDBUtil object.
     *
     * @param url       The db URL.
     * @param user      The db user name.
     * @param pass      The db password.
     */
    public AssessmentDBUtil(String url, String user, String pass)
    {
        super(url, user, pass);

        // if we need to see the results set metadata, uncomment the following line
//        logMetaDataFlag = true;
    }

    /**
     * Retrieve a single execution record from the database.
     *
     * @param runID             The execution run uuid.
     * @return                  A list of ExecRecord objects associated with the exec run uuid.
     * @throws SQLException
     */
    public ArrayList<ExecRecord> getSingleExecutionRecord(String runID) throws SQLException
    {
        CallableStatement call = null;
        ResultSet resultSet = null;
        ArrayList<ExecRecord> results = new ArrayList<ExecRecord>();

        try
        {
            call = connection.prepareCall("{call assessment.select_execution_record(?)}");
            call.setString(1, runID);
            LOG.debug("call assessment.select_execution_record(?) with arg: " + runID + idLabel);

            boolean update = call.execute();
            if (update)
            {
                resultSet = call.getResultSet();
                results = processResults(resultSet);
            }
            else
            {
                LOG.error("problem executing the stored procedure: assessment.select_execution_record(?)" +
                idLabel);
            }
        }
        catch (SQLException e)
        {
            LOG.error("SQLException in getSingleExecutionRecord(): " + e.getMessage() + idLabel);
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
     * Process the results of a database query.
     *
     * @param resultSet         The result set returned by the query.
     * @return                  A list of ExecRecord objects.
     * @throws SQLException
     */
    private ArrayList<ExecRecord> processResults(ResultSet resultSet) throws SQLException
    {
        if (logMetaDataFlag)
        {
            logResultSetMetaData(resultSet);
        }
        ArrayList<ExecRecord> results = new ArrayList<ExecRecord>();
        while (resultSet.next())
        {
            ExecRecord record = new ExecRecord(resultSet);
            results.add(record);
        }

        return results;
    }

    /**
     * Sends an updated status of an assessment run to the database.
     *
     * @param versionID     The version ID.
     * @param status        The new status.
     * @param timeStart     Starting time.
     * @param timeEnd       End time.
     * @param execNode      The exec node used for the run.
     * @param lines         Lines of code.
     * @param cpuUtil       Utilization of the CPU.
     * @param vmHost        VM host.
     * @param vmUser        VM user name.
     * @param vmPass        VM password.
     * @param vmIP          VM IP address.
     * @param vmImage       VM image file name.
     * @param toolFilename  file name of the tool used in this run.
     * @return              true if the db operation is successful; false otherwise.
     * @throws SQLException
     */
    public boolean updateExecutionRunStatus(String versionID, String status, String timeStart, String timeEnd,
                                            String execNode, int lines, String cpuUtil,
                                            String vmHost, String vmUser, String vmPass, String vmIP,
                                            String vmImage, String toolFilename)
            throws SQLException
    {
        CallableStatement call = null;
        String result = "";

        try
        {
            call = connection.prepareCall("{call assessment.update_execution_run_status(?,?,?,?,?,?,?,?,?,?,?,?,?,?)}");
            call.setString(1, versionID);
            call.setString(2, status);
            call.setString(3, timeStart);
            call.setString(4, timeEnd);
            call.setString(5, execNode);
            call.setInt(6, lines);
            call.setString(7, cpuUtil);
            call.setString(8, vmHost);
            call.setString(9, vmUser);
            call.setString(10, vmPass);
            call.setString(11, vmIP);
            call.setString(12, vmImage);
            call.setString(13, toolFilename);
            call.registerOutParameter(14, Types.VARCHAR);

            int flag = call.executeUpdate();

            result = call.getString(14);
            LOG.info("result = " + result + " flag = " + flag + idLabel);
        }
        catch (SQLException e)
        {
            LOG.error("SQLException in updateExecutionRunStatus(): " + e.getMessage() + idLabel);
            throw e;
        }
        finally
        {
            closeStatement(call);
        }

        return checkDatabaseResult(result, "assessment.update_execution_run_status: ");
    }

    /**
     * Sends an updated field of an assessment run to the database.
     *
     * @param execRunID     The exec run ID.
     * @param field         The field to be modified.
     * @param value         The new value of the field
     * @return              true if the db operation is successful; false otherwise.
     * @throws SQLException
     */
    public boolean updateExecutionRunStatusTestSingleField(String execRunID, String field, String value)
            throws SQLException
    {
        CallableStatement call = null;
        String result = "";
        int flag;

        LOG.info("--> field = " + field + " value = " + value);

        try
        {
            LOG.info("connection valid? " + connection.isValid(1));
            call = connection.prepareCall("{call assessment.update_execution_run_status_test(?,?,?,?)}");
            if (call == null)
            {
                LOG.error("**** null callable statement ****");
            }
            call.setString(1, execRunID);
            call.setString(2, field);
            call.setString(3, value);
            call.registerOutParameter(4, Types.VARCHAR);

            flag = call.executeUpdate();

            result = call.getString(4);
            LOG.info("result = " + result + " flag = " + flag + idLabel);
        }
        catch (SQLException e)
        {
            LOG.error("SQLException in updateExecutionRunStatusTestSingleField(): " + e.getMessage() + idLabel);
            throw e;
        }
        finally
        {
            LOG.info("updateExecutionRunStatusTestSingleField: closing statement");
            closeStatement(call);
        }

        return checkDatabaseResult(result, "assessment.update_execution_run_status_test: ");
    }

    /**
     * Sends an updated field of an assessment run to the database.
     *
     * @param execRunID     The exec run ID.
     * @param list          The validated list of field, value pairs to be inserted in the record.
     * @return              true if all of the db operations are successful; false otherwise.
     * @throws SQLException
     */
    public boolean updateExecutionRunStatusMultiField(String execRunID, HashMap<String, String> list)
            throws SQLException
    {
        CallableStatement call;
        String result;
        int flag;
        boolean success = true;

//        LOG.info(" database connection valid? " + connection.isValid(1));
        call = connection.prepareCall("{call assessment.update_execution_run_status_test(?,?,?,?)}");
        if (call == null)
        {
            LOG.error("**** null callable statement ****");
            return false;
        }

        for (Map.Entry<String, String> entry : list.entrySet())
        {
            String field = entry.getKey();
            String value = entry.getValue();

            try
            {
                call.setString(1, execRunID);
                call.setString(2, field);
                call.setString(3, value);
                call.registerOutParameter(4, Types.VARCHAR);

                flag = call.executeUpdate();
                result = call.getString(4);
                
                // success or failure of this run
                boolean temp = checkDatabaseResult(result,"assessment.update_execution_run_status_test (field = " + field + "): ");
                if (!temp)
                {
                    success = false;
                }

                LOG.info("(field = " + field + " value = " + value + ") result = " + result + " flag = " + flag + idLabel);
            }
            catch (SQLException e)
            {
                LOG.error("SQLException in updateExecutionRunStatusMultiField(): " + e.getMessage() + idLabel);
                LOG.error("\t\t **** update failed for field: " + field + ", value: " + value + " ****");
                success = false;
            }
        }

        LOG.info("updateExecutionRunStatusMultiField: closing the statement");
        closeStatement(call);

        return success;
    }


    /**
     * Send the assessment run results to the database.
     *
     * @param execRunID         The execution run uuid.
     * @param resultPath        The path of the results.
     * @param resultChecksum    The check sum of the results.
     * @param sourcePath        The path of the source.
     * @param sourceChecksum    The check sum of the source.
     * @param logPath           The path of the log file(s).
     * @param logChecksum       The log file checksum.
     * @param weaknessCount     The number of weaknesses found in the assessment
     * @return                  true if the db operation is successful; false otherwise.
     * @throws SQLException
     */
    public boolean insertResults(String execRunID, String resultPath, String resultChecksum, String sourcePath,
                                 String sourceChecksum, String logPath, String logChecksum, int weaknessCount)
            throws SQLException
    {
        CallableStatement call = null;
        String result = "";

        try
        {
            call = connection.prepareCall("{call assessment.insert_results(?,?,?,?,?,?,?,?,?)}");
            call.setString(1, execRunID);
            call.setString(2, resultPath);
            call.setString(3, resultChecksum);
            call.setString(4, sourcePath);
            call.setString(5, sourceChecksum);
            call.setString(6, logPath);
            call.setString(7, logChecksum);
            call.setInt(8, weaknessCount);
            call.registerOutParameter(9, Types.VARCHAR);

            int flag = call.executeUpdate();

            result = call.getString(9);
            LOG.info("result = " + result + " flag = " + flag + idLabel);
        }
        catch (SQLException e)
        {
            LOG.error("SQLException in insertResults(): " + e.getMessage() + idLabel);
            throw e;
        }
        finally
        {
            closeStatement(call);
        }

        return checkDatabaseResult(result, "assessment.insert_results: ");
    }

    /**
     * Send an execution event to the database.
     *
     * @param execRecordID      The execution uuid.
     * @param eventTime         Time of the event
     * @param event             The nature of the event.
     * @param payload           The data to be sent to the database
     * @return                  true if the db operation is successful; false otherwise.
     * @throws SQLException
     */
    public boolean insertExecutionEvent(String execRecordID, String eventTime, String event, String payload)
            throws SQLException
    {
        CallableStatement call = null;
        boolean results = false;

        try
        {
            call = connection.prepareCall("{call assessment.insert_execution_event(?,?,?,?,?)}");
            call.setString(1, execRecordID);
            call.setString(2, eventTime);
            call.setString(3, event);
            call.setString(4, payload);
            call.registerOutParameter(5, Types.VARCHAR);

            call.executeUpdate();

            String flag = call.getString(5);
            results = checkDatabaseResult(flag, "assessment.insert_execution_event: ");
        }
        catch (SQLException e)
        {
            LOG.error("SQLException in insertExecutionEvent(): " + e.getMessage() + idLabel);
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
            LOG.error("DB error: " + message + " " + value + idLabel);
            results = false;
        }
        return results;
    }

    /**
     * Send the assessment status to the database.
     *
     * @param key       The exec run uuid.
     * @param value     The status of the assessment run.
     * @return          true is the db operation succeeds; false otherwise.
     * @throws SQLException
     */
    public boolean insertSystemStatus(String key, String value)
            throws SQLException
    {
        CallableStatement call = null;
        boolean results = false;

        try
        {
            call = connection.prepareCall("{call assessment.set_system_status(?,?,?)}");
            call.setString(1, key);
            call.setString(2, value);
            call.registerOutParameter(3, Types.VARCHAR);

            call.executeUpdate();

            String flag = call.getString(3);
            results = checkDatabaseResult(flag, "assessment.set_system_status: ");
        }
        catch (SQLException e)
        {
            LOG.error("SQLException in insertSystemStatus(): " + e.getMessage() + idLabel);
            throw e;
        }
        finally
        {
            closeStatement(call);
        }

        return results;
    }
}
