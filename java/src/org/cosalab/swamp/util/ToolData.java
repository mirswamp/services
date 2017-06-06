// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.util;

import java.io.File;
import java.sql.ResultSet;
import java.sql.SQLException;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 8/26/13
 * Time: 11:28 AM
 */
public class ToolData implements TaggedData
{
    // note that these are actually the "column label" in the result set metadata

    /** Tool uuid column label. */
    private static final String LABEL_TOOL_ID = "tool_uuid";
    /** Tool version uuid column label. */
    private static final String LABEL_VERSION_ID = "tool_version_uuid";
    /** Tool name column label. */
    private static final String LABEL_NAME = "tool_name";
    /** Tool version name column label. */
    private static final String LABEL_VERSION_STRING = "version_string";
    /** Tool path column label. */
    private static final String LABEL_PATH = "tool_path";
    /** Tool checksum column label. */
    private static final String LABEL_CHECKSUM = "checksum";
    /** Tool executable column label. */
    private static final String LABEL_TOOL_EXECUTABLE = "tool_executable";
    /** Tool arguments column label. */
    private static final String LABEL_ARGUMENTS = "tool_arguments";
    /** Build needed flag column label. */
    private static final String LABEL_BUILD_NEEDED = "IsBuildNeeded";
    /** Tool directory column label. */
    private static final String LABEL_TOOL_DIRECTORY = "tool_directory";

    /** The tool name. */
    private String toolName;
    /** The tool version name. */
    private String versionName;
    /** The tool path. */
    private String path;
    /** The tool checksum. */
    private String checkSum;
    /** The tool executable. */
    private String toolExecutable;
    /** The tool arguments. */
    private String toolArguments;
    /** The tool uuid. */
    private String toolID;
    /** The tool version uuid. */
    private String versionID;
    /** The tool directory. */
    private String toolDirectory;

    /** The build needed flag. */
    private boolean buildNeeded;

    /** The data tag for this object. */
    private String tag;

    /**
     * Constructor.
     *
     * @param resultSet         The result set returned from the database.
     * @throws SQLException
     * @throws InvalidDBObjectException
     */
    public ToolData(ResultSet resultSet) throws SQLException, InvalidDBObjectException
    {
        setToolName(resultSet.getString(LABEL_NAME));
        setVersionName(resultSet.getString(LABEL_VERSION_STRING));
        setPath(resultSet.getString(LABEL_PATH));
        setCheckSum(resultSet.getString(LABEL_CHECKSUM));
        setToolID(resultSet.getString(LABEL_TOOL_ID));
        setVersionID(resultSet.getString(LABEL_VERSION_ID));
        setToolArguments(resultSet.getString(LABEL_ARGUMENTS));
        setToolExecutable(resultSet.getString(LABEL_TOOL_EXECUTABLE));
        setToolDirectory(resultSet.getString(LABEL_TOOL_DIRECTORY));
        // this is a TINYINT field in the table, so we'll try to read it as a boolean
        setBuildNeeded(resultSet.getBoolean(LABEL_BUILD_NEEDED));

        File file = new File(path);
        setTag(file.getName());
    }

    /**
     * Get the tool name.
     *
     * @return  The name.
     */
    public String getToolName()
    {
        return toolName;
    }

    /**
     * Set the tool name.
     *
     * @param newName   The new name.
     */
    public void setToolName(String newName)
    {
        toolName = StringUtil.validateStringArgument(newName);
    }

    /**
     * Get the tool version name.
     *
     * @return  The version name.
     */
    public String getVersionName()
    {
        return versionName;
    }

    /**
     * Set the tool version name.
     *
     * @param newVersion    The new version name.
     */
    public void setVersionName(String newVersion)
    {
        versionName = StringUtil.validateStringArgument(newVersion);
    }

    /**
     * Get the tool path.
     *
     * @return  The path.
     */
    public String getPath()
    {
        return path;
    }

    /**
     * Set the value of the tool path after validating the argument.
     *
     * @param newPath       The new path.
     * @throws InvalidDBObjectException
     */
    public void setPath(String newPath) throws InvalidDBObjectException
    {
        if (newPath == null || newPath.isEmpty())
        {
            // we have a bad tool returned from the database
            throw new InvalidDBObjectException("tool path is empty or null");
        }

        path = newPath;
    }

    /**
     * Get the tool checksum.
     *
     * @return  The checksum.
     */
    public String getCheckSum()
    {
        return checkSum;
    }

    /**
     * Set the checksum of the tool after validating the argument.
     *
     * @param newCheckSum       The new checksum value.
     * @throws InvalidDBObjectException
     */
    public void setCheckSum(String newCheckSum) throws InvalidDBObjectException
    {
        if (newCheckSum == null || newCheckSum.isEmpty())
        {
            // we have a bad tool returned from the database
            throw new InvalidDBObjectException("tool checksum is empty or null");
        }
        checkSum = newCheckSum;
    }

    /**
     * Get the tool uuid.
     *
     * @return  The uuid.
     */
    public String getToolID()
    {
        return toolID;
    }

    /**
     * Set the tool uuid.
     *
     * @param newID The uuid.
     */
    public void setToolID(String newID)
    {
        toolID = StringUtil.validateStringArgument(newID);
    }

    /**
     * Get the tool version uuid.
     *
     * @return  The uuid.
     */
    public String getVersionID()
    {
        return versionID;
    }

    /**
     * Set the tool version uuid.
     *
     * @param newID     The new uuid.
     */
    public void setVersionID(String newID)
    {
        versionID = StringUtil.validateStringArgument(newID);
    }

    /**
     * Create a string representation of the tool object.
     *
     * @return  The string representation.
     */
    public String toString()
    {
        String msg = "idTool: " + getToolID() + " idVersion: " + getVersionID() + " name: " + getToolName() +
                " version: " + getVersionName() + " buildNeeded: " + isBuildNeeded() +
                "\npath: " + getPath() + "\nchecksum: " + getCheckSum();

        return msg;
    }

    /**
     * Set the tag field.
     *
     * @param newTag    The new tag.
     */
    @Override
    public void setTag(String newTag)
    {
        tag = StringUtil.validateStringArgument(newTag);
    }

    /**
     * Return the data tag field.
     *
     * @return  The tag.
     */
    @Override
    public String getTag()
    {
        return tag;
    }

    /**
     * Get the tool executable field.
     *
     * @return  The tool executable field.
     */
    public String getToolExecutable()
    {
        return toolExecutable;
    }

    /**
     * Set the tool executable field.
     *
     * @param exec  The new value of the tool executable field.
     */
    public void setToolExecutable(String exec)
    {
        toolExecutable = StringUtil.validateStringArgument(exec);
    }

    /**
     * Get the tool arguments field.
     *
     * @return  The tool arguments.
     */
    public String getToolArguments()
    {
        return toolArguments;
    }

    /**
     * Set the tool arguments field.
     *
     * @param toolArgs  The new value of the tool arguments.
     */
    public void setToolArguments(String toolArgs)
    {
        toolArguments = StringUtil.validateStringArgument(toolArgs);
    }

    /**
     * Get the build needed flag.
     *
     * @return  The build needed flag.
     */
    public boolean isBuildNeeded()
    {
        return buildNeeded;
    }

    /**
     * Set the build needed flag.
     *
     * @param buildNeeded   The new flag value.
     */
    public void setBuildNeeded(boolean buildNeeded)
    {
        this.buildNeeded = buildNeeded;
    }

    /**
     * Get the tool directory.
     *
     * @return  The tool directory.
     */
    public String getToolDirectory()
    {
        return toolDirectory;
    }

    /**
     * Set the tool directory.
     *
     * @param toolDirectory     The new tool directory.
     */
    public void setToolDirectory(String toolDirectory)
    {
        this.toolDirectory = StringUtil.validateStringArgument(toolDirectory);
    }

}
