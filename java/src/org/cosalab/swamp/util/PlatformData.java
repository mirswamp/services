// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2016 Software Assurance Marketplace

package org.cosalab.swamp.util;

import java.sql.ResultSet;
import java.sql.SQLException;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 9/3/13
 * Time: 9:46 AM
 */
public class PlatformData implements TaggedData
{
    // note that these are actually the "column label" in the result set metadata

    /** Platform uuid column label. */
    private static final String COL_PLATFORM_ID = "platform_uuid";
    /** Platform version uuid column label. */
    private static final String COL_VERSION_ID = "platform_version_uuid";
    /** Platform name column label. */
    private static final String COL_NAME = "platform_name";
    /** Platform version string column label. */
    private static final String COL_VERSION_STR = "version_string";
    /** Platform path column label. */
    private static final String COL_PATH = "platform_path";

    /** The platform name. */
    private final String platformName;
    /** The platform version name. */
    private final String versionName;
    /** The platform path. */
    private final String path;
    /** The platform uuid. */
    private final String platformID;
    /** The platform version uuid. */
    private final String versionID;

    /** The data tag for this object. */
    private String tag;

    /**
     * Constructor.
     *
     * @param resultSet     The result set from the database.
     * @throws SQLException
     */
    public PlatformData(ResultSet resultSet) throws SQLException
    {
        platformName = resultSet.getString(COL_NAME);
        versionName = resultSet.getString(COL_VERSION_STR);
        platformID = resultSet.getString(COL_PLATFORM_ID);
        versionID = resultSet.getString(COL_VERSION_ID);
        path = resultSet.getString(COL_PATH);
        setTag(path);
    }

    /**
     * Set the data tag.
     *
     * @param tag   The data tag.
     */
    @Override
    public void setTag(String tag)
    {
        this.tag = tag;
    }

    /**
     * Get the data tag.
     *
     * @return      The data tag.
     */
    @Override
    public String getTag()
    {
        return tag;
    }

    /**
     * Get the platform ID.
     *
     * @return  The platform uuid.
     */
    public String getPlatformID()
    {
        return platformID;
    }

    /**
     * Get the platform version ID.
     *
     * @return  The platform version uuid.
     */
    public String getVersionID()
    {
        return versionID;
    }

    /**
     * Get the platform name.
     *
     * @return  The name.
     */
    public String getPlatformName()
    {
        return platformName;
    }

    /**
     * Get the platform version name.
     *
     * @return  The version name.
     */
    public String getPlatformVersionName()
    {
        return versionName;
    }

    /**
     * Get the platform path.
     *
     * @return      The path.
     */
    public String getPlatformPath()
    {
        return path;
    }

    /**
     * Create a string representation of the platform data object.
     *
     * @return  The string representation.
     */
    public String toString()
    {
        return "id: " + getPlatformID() + " name: " + getPlatformName() + " versionID: " +
                getVersionID() + " version: " +
                getPlatformVersionName() + " path: " + getPlatformPath();
    }
}
