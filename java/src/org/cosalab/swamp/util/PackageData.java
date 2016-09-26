// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2016 Software Assurance Marketplace

package org.cosalab.swamp.util;

import java.io.File;
import java.sql.ResultSet;
import java.sql.SQLException;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 8/29/13
 * Time: 10:23 AM
 */
public class PackageData implements TaggedData
{
    // note that all these are actually the "column label" in the result set metadata

    /** Package uuid column label. */
    private static final String LABEL_PACKAGE_ID = "package_uuid";
    /** Package version uuid column label. */
    private static final String LABEL_VERSION_ID = "package_version_uuid";
    /** Package name column label. */
    private static final String LABEL_NAME = "package_name";
    /** Package version string column label. */
    private static final String LABEL_VERSION_STRING = "version_string";
    /** Package path column label. */
    private static final String LABEL_PATH = "package_path";
    /** Package checksum column label. */
    private static final String LABEL_CHECKSUM = "checksum";
    /** Build system column label. */
    private static final String LABEL_BUILD_SYSTEM = "build_system";
    /** Build target column label. */
    private static final String LABEL_BUILD_TARGET = "build_target";
    /** Source path column label. */
    private static final String LABEL_SOURCE_PATH = "source_path";
    /** Build file column label. */
    private static final String LABEL_BUILD_FILE = "build_file";
    /** Configuration command column label. */
    private static final String LABEL_CONFIG_CMD = "config_cmd";
    /** Configuration options column label. */
    private static final String LABEL_CONFIG_OPT = "config_opt";
    /** Configuration directory column label. */
    private static final String LABEL_CONFIG_DIR = "config_dir";
    /** Build options column label. */
    private static final String LABEL_BUILD_OPT = "build_opt";
    /** Build directory column label. */
    private static final String LABEL_BUILD_DIR = "build_dir";
    /** Build command column label. */
    private static final String LABEL_BUILD_CMD = "build_cmd";
    /** Byte code class path column label. */
    private static final String LABEL_CLASS_PATH = "bytecode_class_path";
    /** Byte code auxiliary class path column label. */
    private static final String LABEL_AUX_CLASS_PATH = "bytecode_aux_class_path";
    /** Byte code source path column label. */
    private static final String LABEL_BYTE_CODE_SOURCE_PATH = "bytecode_source_path";
    /** Package type column label. */
    private static final String LABEL_PACKAGE_TYPE = "package_type";
    /** Android package SDK target label. */
    private static final String LABEL_ANDROID_SDK_TARGET = "android_sdk_target";
    /** Android package redo build label. */
    private static final String LABEL_ANDROID_REDO_BUILD = "android_redo_build";
    /** Gradle build wraper flag label. */
    private static final String LABEL_USE_GRADLE_WRAPPER = "use_gradle_wrapper";
    /** Target field for Android lint label. */
    private static final String LABEL_ANDROID_LINT_TARGET = "android_lint_target";
    /** Language version label. */
    private static final String LABEL_LANGUAGE_VERSION = "language_version";
    /** Maven version label. */
    private static final String LABEL_MAVEN_VERSION = "maven_version";
    /** Android maven plugin. */
    private static final String LABEL_ANDROID_MAVEN_PLUGIN = "android_maven_plugin";

    /** The name of the package. */
    private String packageName;
    /** The name of the package version. */
    private String versionName;
    /** The package path. */
    private String path;
    /** The package checksum. */
    private String checkSum;
    /** The build target. */
    private String buildTarget;
    /** The build tool. */
    private String buildTool;
    /** The package uuid. */
    private String packageID;
    /** The version uuid. */
    private String versionID;
    /** The source path. */
    private String sourcePath;
    /** The build file. */
    private String buildFile;
    /** The build options. */
    private String buildOpt;
    /** The build command. */
    private String buildCmd;
    /** The build directory. */
    private String buildDir;
    /** The configuration command. */
    private String configCmd;
    /** The configuration directory. */
    private String configDir;
    /** The configuration options. */
    private String configOpt;
    /** The class path. */
    private String classPath;
    /** The auxiliary class path. */
    private String auxClassPath;
    /** The byte code source path. */
    private String byteCodeSourcePath;
    /** Package type. */
    private String packageType;
    /** Android package SDK target. */
    private String androidSDKTarget;
    /** Android package redo build flag. */
    private boolean androidRedoBuild;
    /** Gradle wrapper flag. */
    private boolean useGradleWrapper;
    /** Android lint target. */
    private String androidLintTarget;
    /** The language version. */
    private String languageVersion;
    /** The maven version. */
    private String mavenVersion;
    /** The android maven plugin. */
    private String androidMavenPlugin;

    /** The data tag for this object. */
    private String tag;

    /**
     * Create a new package data object from a result set.
     *
     * @param resultSet                     The result set.
     * @throws SQLException
     * @throws InvalidDBObjectException
     */
    public PackageData(final ResultSet resultSet) throws SQLException, InvalidDBObjectException
    {
        setPackageName(resultSet.getString(LABEL_NAME));
        setVersionName(resultSet.getString(LABEL_VERSION_STRING));
        setPath(resultSet.getString(LABEL_PATH));
        setCheckSum(resultSet.getString(LABEL_CHECKSUM));
        setPackageID(resultSet.getString(LABEL_PACKAGE_ID));
        setVersionID(resultSet.getString(LABEL_VERSION_ID));
        setBuildTarget(resultSet.getString(LABEL_BUILD_TARGET));
        setBuildSystem(resultSet.getString(LABEL_BUILD_SYSTEM));
        setSourcePath(resultSet.getString(LABEL_SOURCE_PATH));
        setBuildFile(resultSet.getString(LABEL_BUILD_FILE));
        setConfigCmd(resultSet.getString(LABEL_CONFIG_CMD));
        setConfigOpt(resultSet.getString(LABEL_CONFIG_OPT));
        setConfigDir(resultSet.getString(LABEL_CONFIG_DIR));
        setBuildDir(resultSet.getString(LABEL_BUILD_DIR));
        setBuildOpt(resultSet.getString(LABEL_BUILD_OPT));
        setBuildCmd(resultSet.getString(LABEL_BUILD_CMD));

        // new byte code fields
        setClassPath(resultSet.getString(LABEL_CLASS_PATH));
        setAuxClassPath(resultSet.getString(LABEL_AUX_CLASS_PATH));
        setByteCodeSourcePath(resultSet.getString(LABEL_BYTE_CODE_SOURCE_PATH));

        // new package type (C/C++, Java source, Java bytecode)
        setPackageType(resultSet.getString(LABEL_PACKAGE_TYPE));

        // Android package flags
        setAndroidSDKTarget(resultSet.getString(LABEL_ANDROID_SDK_TARGET));
        // this is a TINYINT field in the table, so we'll try to read it as a boolean
        setAndroidRedoBuild(resultSet.getBoolean(LABEL_ANDROID_REDO_BUILD));

        // Gradle wrapper flag
        setUseGradleWrapper(resultSet.getBoolean(LABEL_USE_GRADLE_WRAPPER));

        // Android lint target
        setAndroidLintTarget(resultSet.getString(LABEL_ANDROID_LINT_TARGET));

        // The language version for this package
        setLanguageVersion(resultSet.getString(LABEL_LANGUAGE_VERSION));

        // The maven version and other android stuff
        setMavenVersion(resultSet.getString(LABEL_MAVEN_VERSION));
        setAndroidMavenPlugin(resultSet.getString(LABEL_ANDROID_MAVEN_PLUGIN));

        final File file = new File(path);
        setTag(file.getName());

    }

    /**
     * Get the package name.
     *
     * @return  The package name.
     */
    public String getPackageName()
    {
        return packageName;
    }

    /**
     * Set the package name.
     *
     * @param newPackageName    The new name.
     */
    public void setPackageName(final String newPackageName)
    {
        packageName = StringUtil.validateStringArgument(newPackageName);
    }

    /**
     * Get the package version name.
     *
     * @return  The name.
     */
    public String getVersionName()
    {
        return versionName;
    }

    /**
     * Set the package version name.
     *
     * @param newVersionName    The new name.
     */
    public void setVersionName(final String newVersionName)
    {
        versionName = StringUtil.validateStringArgument(newVersionName);
    }

    /**
     * get the path.
     *
     * @return  The package path.
     */
    public String getPath()
    {
        return path;
    }

    /**
     * Set the package path, checking for problems with the data returned from the database.
     *
     * @param newPath                       The new path.
     * @throws InvalidDBObjectException
     */
    public void setPath(final String newPath) throws InvalidDBObjectException
    {
        if (newPath == null || newPath.isEmpty())
        {
            // we have a bad package returned from the database
            throw new InvalidDBObjectException("package path is empty or null");
        }

        path = newPath;
    }

    /**
     * Get the package checksum.
     *
     * @return  The checksum.
     */
    public String getCheckSum()
    {
        return checkSum;
    }

    /**
     * Set the package checksum, checking for database problems.
     *
     * @param newCheckSum               The new checksum.
     * @throws InvalidDBObjectException
     */
    public void setCheckSum(final String newCheckSum) throws InvalidDBObjectException
    {
        if (newCheckSum == null || newCheckSum.isEmpty())
        {
            // we have a bad package returned from the database
            throw new InvalidDBObjectException("package checksum is empty or null");
        }
        checkSum = newCheckSum;
    }

    /**
     * Get the package ID.
     *
     * @return  The package uuid.
     */
    public String getPackageID()
    {
        return packageID;
    }

    /**
     * Set the package ID.
     *
     * @param newID The new package uuid.
     */
    public void setPackageID(final String newID)
    {
        packageID = StringUtil.validateStringArgument(newID);
    }

    /**
     * Get the package version ID.
     *
     * @return  The package version uuid.
     */
    public String getVersionID()
    {
        return versionID;
    }

    /**
     * Set the package version ID.
     *
     * @param newID The new package version uuid.
     */
    public void setVersionID(final String newID)
    {
        versionID = StringUtil.validateStringArgument(newID);
    }

    /**
     * Create a string representation of the package data object.
     *
     * @return  The string.
     */
    public String toString()
    {

        return "idPackage: " + getPackageID() + " idVersion: " + getVersionID() + " name: " +
                getPackageName() + " version: " + getVersionName() + "\npath: " + getPath() +
                "\nchecksum: " + getCheckSum();
    }

    /**
     * Set the data tag.
     *
     * @param newTag    The tag.
     */
    @Override
    public void setTag(final String newTag)
    {
        tag = StringUtil.validateStringArgument(newTag);
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
     * Get the build target.
     *
     * @return  The build target.
     */
    public String getBuildTarget()
    {
        return buildTarget;
    }

    /**
     * Set the build target.
     *
     * @param build The new build target.
     */
    public void setBuildTarget(final String build)
    {
        buildTarget = StringUtil.validateStringArgument(build);
    }

    /**
     * Get the build system.
     *
     * @return  The build system.
     */
    public String getBuildSystem()
    {
        return buildTool;
    }

    /**
     * Set the build system.
     *
     * @param tool  The build system.
     */
    public void setBuildSystem(final String tool)
    {
        buildTool = StringUtil.validateStringArgument(tool);
    }

    /**
     * Get the source path.
     *
     * @return  The package source path.
     */
    public String getSourcePath()
    {
        return sourcePath;
    }

    /**
     * Set the source path.
     *
     * @param sPath     The enw package source path.
     */
    public void setSourcePath(final String sPath)
    {
        sourcePath = StringUtil.validateStringArgument(sPath);
    }

    /**
     * Get the build file.
     *
     * @return  The build file.
     */
    public String getBuildFile()
    {
        return buildFile;
    }

    /**
     * Set the build file.
     *
     * @param bFile The build file.
     */
    public void setBuildFile(String bFile)
    {
        buildFile = StringUtil.validateStringArgument(bFile);
    }

    /**
     * Get the build directory.
     *
     * @return  The build directory.
     */
    public String getBuildDir()
    {
        return buildDir;
    }

    /**
     * Set the build directory.
     *
     * @param dir   The build directory.
     */
    public void setBuildDir(final String dir)
    {
        buildDir = StringUtil.validateStringArgument(dir);
    }

    /**
     * Set the build options.
     *
     * @return  The build options.
     */
    public String getBuildOpt()
    {
        return buildOpt;
    }

    /**
     * Get the build command.
     *
     * @return  The bui;d command.
     */
    public String getBuildCmd()
    {
         return buildCmd;
    }

    /**
     * Set the build command.
     *
     * @param cmd   The build command.
     */
    public void setBuildCmd(final String cmd)
    {
       buildCmd = StringUtil.validateStringArgument(cmd);
    }

    /**
     * Set the build options.
     *
     * @param opt   The build options.
     */
    public void setBuildOpt(final String opt)
    {
        buildOpt = StringUtil.validateStringArgument(opt);
    }

    /**
     * Get the configuration options.
     *
     * @return  The configuration options.
     */
    public String getConfigOpt()
    {
        return configOpt;
    }

    /**
     * Set the configuration options.
     *
     * @param opt   The configuration options.
     */
    public void setConfigOpt(final String opt)
    {
        configOpt = StringUtil.validateStringArgument(opt);
    }

    /**
     * Get the configuration directory.
     *
     * @return  The configuration directory.
     */
    public String getConfigDir()
    {
        return configDir;
    }

    /**
     * Set the configuration directory.
     *
     * @param dir   The configuration directory.
     */
    public void setConfigDir(final String dir)
    {
        configDir = StringUtil.validateStringArgument(dir);
    }

    /**
     * Get the configuration command.
     *
     * @return  The configuration command.
     */
    public String getConfigCmd()
    {
        return configCmd;
    }

    /**
     * Set the configuration command.
     *
     * @param cmd   The configuration command.
     */
    public void setConfigCmd(final String cmd)
    {
        configCmd = StringUtil.validateStringArgument(cmd);
    }

    /**
     * Get the class path.
     *
     * @return  The class path.
     */
    public String getClassPath()
    {
        return classPath;
    }

    /**
     * Set the class path.
     *
     * @param path  The class path.
     */
    public void setClassPath(final String path)
    {
        classPath = StringUtil.validateStringArgument(path);
    }

    /**
     * Get the auxiliary class path.
     *
     * @return  The auxiliary class path.
     */
    public String getAuxClassPath()
    {
        return auxClassPath;
    }

    /**
     * Set the auxiliary class path.
     *
     * @param path  The auxiliary class path.
     */
    public void setAuxClassPath(final String path)
    {
        auxClassPath = StringUtil.validateStringArgument(path);
    }

    /**
     * Get the byte code source path.
     *
     * @return  The byte code source path.
     */
    public String getByteCodeSourcePath()
    {
        return byteCodeSourcePath;
    }

    /**
     * Set the byte code source path.
     *
     * @param path  The byte code source path.
     */
    public void setByteCodeSourcePath(String path)
    {
        byteCodeSourcePath = StringUtil.validateStringArgument(path);
    }

    /**
     * Set the package type.
     *
     * @param type  The package type.
     */
    public void setPackageType(final String type)
    {
        packageType = StringUtil.validateStringArgument(type);
    }

    /**
     * Get the package type.
     *
     * @return  The package type.
     */
    public String getPackageType()
    {
        return packageType;
    }

    /**
     * Get the Android package SDK target.
     *
     * @return  The SDK target.
     */
    public String getAndroidSDKTarget()
    {
        return androidSDKTarget;
    }

    /**
     * Set the Android package SDK target.
     *
     * @param androidSDKTarget  The Android SDK target.
     */
    public void setAndroidSDKTarget(String androidSDKTarget)
    {
        this.androidSDKTarget = StringUtil.validateStringArgument(androidSDKTarget);
    }

    /**
     * Get the Redo Build flag for an Android package.
     *
     * @return  The Redo Build flag
     */
    public boolean getAndroidRedoBuild()
    {
        return androidRedoBuild;
    }

    /**
     * Set the Android Redo Build flag.
     *
     * @param androidRedoBuild  The Redo Build flag.
     */
    public void setAndroidRedoBuild(boolean androidRedoBuild)
    {
        this.androidRedoBuild = androidRedoBuild;
    }

    /**
     * Get the use Gradle wrapper flag.
     *
     * @return The Gradle wrapper flag
     */
    public boolean getUseGradleWrapper()
    {
        return useGradleWrapper;
    }

    /**
     * Set the use Gradle WRapper flag.
     *
     * @param useGradleWrapper  the new value of the flag
     */
    public void setUseGradleWrapper(boolean useGradleWrapper)
    {
        this.useGradleWrapper = useGradleWrapper;
    }

    /**
     * Get the Android lint target
     *
     * @return  The Android lint target
     */
    public String getAndroidLintTarget()
    {
        return androidLintTarget;
    }

    /**
     * Set the Android lint target
     *
     * @param androidLintTarget The new value of the target
     */
    public void setAndroidLintTarget(String androidLintTarget)
    {
        this.androidLintTarget = StringUtil.validateStringArgument(androidLintTarget);
    }

    /**
     * Get the language version for the package.
     *
     * @return  The package's language version.
     */
    public String getLanguageVersion()
    {
        return languageVersion;
    }

    /**
     * Set the language version for the package
     *
     * @param languageVersion   The new value of the package language version
     */
    public void setLanguageVersion(String languageVersion)
    {
        this.languageVersion = StringUtil.validateStringArgument(languageVersion);
    }

    /**
     * Get the maven version.
     *
     * @return  The maven version as a string
     */
    public String getMavenVersion()
    {
        return mavenVersion;
    }

    /**
     * Set the maven version.
     *
     * @param mavenVersion  A string representing the new maven version.
     */
    public void setMavenVersion(String mavenVersion)
    {
        this.mavenVersion = StringUtil.validateStringArgument(mavenVersion);
    }

    /**
     * Set the android maven plugin.
     *
     * @return  A string representing the android maven plugin.
     */
    public String getAndroidMavenPlugin()
    {
        return androidMavenPlugin;
    }

    /**
     * Set the android maven plugin string.
     *
     * @param androidMavenPlugin    The new android maven plugin string.
     */
    public void setAndroidMavenPlugin(String androidMavenPlugin)
    {
        this.androidMavenPlugin = StringUtil.validateStringArgument(androidMavenPlugin);
    }
}
