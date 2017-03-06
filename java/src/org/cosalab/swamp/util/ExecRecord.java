// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.util;

import java.sql.ResultSet;
import java.sql.SQLException;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 9/17/13
 * Time: 11:45 AM
 */
public class ExecRecord implements TaggedData
{
    // note that these are actually the "column label" in the result set metadata

    /** Execution record uuid column label. */
    private static final String LABEL_EXEC_RECORD_ID = "execution_record_uuid";
    /** Platform version uuid column label. */
    private static final String LABEL_PLATFORM_ID = "platform_version_uuid";
    /** Tool version uuid column label. */
    private static final String LABEL_TOOL_ID = "tool_version_uuid";
    /** Package version uuid column label. */
    private static final String LABEL_PACKAGE_ID = "package_version_uuid";
    /** Status column label. */
    private static final String LABEL_STATUS = "status";
    /** Run date column label. */
    private static final String LABEL_RUN_DATE = "run_date";
    /** Completion date column label. */
    private static final String LABEL_COMPLETION_DATE = "completion_date";
    /** CPU utilization column label. */
    private static final String LABEL_CPU = "cpu_utilization";
    /** Lines of code column label. */
    private static final String LABEL_LOC = "lines_of_code";
    /** Exec node architecture ID column label. */
    private static final String LABEL_NODE = "execute_node_architecture_id";
    /** Project uuid column label. */
    private static final String LABEL_PROJECT_ID = "project_uuid";
    /** User uuid column label. */
    private static final String LABEL_USER_ID = "user_uuid";

    /** Exec record uuid, platform uuid, tool uuid, package uuid. */
    private final String uuidExecRecord, uuidPlatform, uuidTool, uuidPackage;
    /** Status, run date, completion date. */
    private String status, runDate, completionDate;
    /** CPU util, lines of code, exec node architecture. */
    private String cpuUtilization, linesOfCode, executeNodeArchitectureID;
    /** Project uuid. */
    private String uuidProject;
    /** User uuid. */
    private String uuidUser;
    /** Data tag. */
    private String tag;

    /**
     * Constructor.
     *
     * @param resultSet     Database result set used to set the fields.
     * @throws SQLException
     */
    public ExecRecord(ResultSet resultSet) throws SQLException
    {
        uuidExecRecord = resultSet.getString(LABEL_EXEC_RECORD_ID);
        uuidPlatform = resultSet.getString(LABEL_PLATFORM_ID);
        uuidTool = resultSet.getString(LABEL_TOOL_ID);
        uuidPackage = resultSet.getString(LABEL_PACKAGE_ID);
        setProjectUuid(resultSet.getString(LABEL_PROJECT_ID));
        setUserUuid(resultSet.getString(LABEL_USER_ID));
        setStatus(resultSet.getString(LABEL_STATUS));
        setRunDate(resultSet.getString(LABEL_RUN_DATE));
        setCompletionDate(resultSet.getString(LABEL_COMPLETION_DATE));

        setTag(uuidExecRecord);
        setCPUUtilization(resultSet.getString(LABEL_CPU));
        setExecuteNode(resultSet.getString(LABEL_NODE));
        setLinesOfCode(resultSet.getString(LABEL_LOC));
    }

    /**
     * Set the data tag.
     *
     * @param newTag    The new tag.
     */
    @Override
    public void setTag(final String newTag)
    {
        tag = newTag;
    }

    /**
     * Get the data tag.
     *
     * @return  The tag.
     */
    @Override
    public String getTag()
    {
        return tag;
    }

    /**
     * Get the execution record uuid.
     *
     * @return  The exec record uuid.
     */
    public String getExecRecordUuid()
    {
        return uuidExecRecord;
    }

    /**
     * Get the platform uuid.
     *
     * @return  The platform uuid
     */
    public String getPlatformUuid()
    {
        return uuidPlatform;
    }

    /**
     * Gert the tool uuid.
     *
     * @return  The tool uuid
     */
    public String getToolUuid()
    {
        return uuidTool;
    }

    /**
     * Get the package uuid.
     *
     * @return  The package uuid.
     */
    public String getPackageUuid()
    {
        return uuidPackage;
    }

    /**
     * Get the Swamp project uuid.
     *
     * @return  The project uuid.
     */
    public String getProjectUuid()
    {
        return uuidProject;
    }

    /**
     * Set the Swamp project uuid.
     *
     * @param id    The project uuid.
     */
    public void setProjectUuid(final String id)
    {
        uuidProject = StringUtil.validateStringArgument(id);
    }

    /**
     * Get the Swamp user uuid.
     *
     * @return  The user uuid.
     */
    public String getUserUuid()
    {
        return uuidUser;
    }

    /**
     * Set the Swamp project uuid.
     *
     * @param id    The user uuid.
     */
    public void setUserUuid(final String id)
    {
        uuidUser = StringUtil.validateStringArgument(id);
    }

    /**
     * Get the status.
     *
     * @return  The status string.
     */
    public String getStatus()
    {
        return status;
    }

    /**
     * Set the status.
     *
     * @param arg   The new status string.
     */
    public void setStatus(final String arg)
    {
        status = StringUtil.validateStringArgument(arg);
    }

    /**
     * Get the run date.
     *
     * @return  The run date.
     */
    public String getRunDate()
    {
        return runDate;
    }

    /**
     * Set the run date.
     *
     * @param arg   The new run date.
     */
    public void setRunDate(final String arg)
    {
        runDate = StringUtil.validateStringArgument(arg);
    }

    /**
     * Getter for the completion date.
     *
     * @return  The completion date.
     */
    public String getCompletionDate()
    {
        return completionDate;
    }

    /**
     * Setter for the completion date.
     *
     * @param arg   The new completion date.
     */
    public void setCompletionDate(final String arg)
    {
        completionDate = StringUtil.validateStringArgument(arg);
    }

    /**
     * Set the CPU utilization.
     *
     * @param arg   The new CPU utilization string.
     */
    public void setCPUUtilization(final String arg)
    {
        cpuUtilization = StringUtil.validateStringArgument(arg);
    }

    /**
     * Get the CPU utilization.
     *
     * @return  The CPU utilization string.
     */
    public String getCPUUtilization() {
        return cpuUtilization;
    }

    /**
     * Set the lines of code.
     *
     * @param arg   The new value of the lines of code.
     */
    public void setLinesOfCode(final String arg)
    {
        linesOfCode = StringUtil.validateStringArgument(arg);
    }

    /**
     * Get the lines of code value.
     *
     * @return  The lines of code.
     */
    public String getLinesOfCode() {
        return linesOfCode;
    }

    /**
     * Set the execute node.
     *
     * @param arg   The new executeNodeArchitectureID.
     */
    public void setExecuteNode(final String arg)
    {
        executeNodeArchitectureID = StringUtil.validateStringArgument(arg);
    }

    /**
     * Get the execute node.
     *
     * @return  The executeNodeArchitectureID.
     */
    public String getExecuteNode() {
         return executeNodeArchitectureID;
    }




}
