// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.util;

import org.cosalab.swamp.quartermaster.QuartermasterServer;

import java.util.HashMap;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 8/19/16
 * Time: 2:44 PM
 */
public final class BogUtil
{

    // no need to ever create an object of this class.
    private BogUtil()
    {
    }

    /**
     * Write the tool information to the bill of goods.
     *
     * @param tool      Tool data object.
     * @param bog       Bill of goods hash map.
     */
    public static void writeToolInBOG(ToolData tool, HashMap<String, String> bog)
    {
        bog.put("toolname", tool.getToolName());
        bog.put("toolpath", tool.getPath());
        bog.put("toolarguments", tool.getToolArguments());
        bog.put("toolexecutable", tool.getToolExecutable());
        bog.put("tooldirectory", tool.getToolDirectory());
        bog.put("tool-version", tool.getVersionName());
        bog.put("buildneeded", String.valueOf(tool.isBuildNeeded()));
    }

    /**
     * Write the package data to the bill of goods.
     *
     * @param packageData   Package data object.
     * @param bog           Bill of goods hash map.
     */
    public static void writePackageInBOG(PackageData packageData, HashMap<String, String> bog)
    {
        bog.put("packagename", packageData.getPackageName());
        bog.put("packagebuild_target", packageData.getBuildTarget());
        bog.put("packagebuild_system", packageData.getBuildSystem());
        bog.put("packagebuild_dir", packageData.getBuildDir());
        bog.put("packagebuild_opt", packageData.getBuildOpt());
        bog.put("packagebuild_cmd", packageData.getBuildCmd());
        bog.put("packageconfig_opt", packageData.getConfigOpt());
        bog.put("packageconfig_dir", packageData.getConfigDir());
        bog.put("packageconfig_cmd", packageData.getConfigCmd());
        bog.put("packagepath", packageData.getPath());
        bog.put("packagesourcepath", packageData.getSourcePath());
        bog.put("packagebuild_file", packageData.getBuildFile());
        bog.put("packagetype", packageData.getPackageType());
        bog.put("packageclasspath", packageData.getClassPath());
        bog.put("packageauxclasspath", packageData.getAuxClassPath());
        bog.put("packagebytecodesourcepath", packageData.getByteCodeSourcePath());
        bog.put("android_sdk_target", packageData.getAndroidSDKTarget());
        bog.put("android_redo_build", String.valueOf(packageData.getAndroidRedoBuild()));
        bog.put("use_gradle_wrapper", String.valueOf(packageData.getUseGradleWrapper()));
        bog.put("android_lint_target", packageData.getAndroidLintTarget());
        bog.put("language_version", packageData.getLanguageVersion());
        bog.put("maven_version", packageData.getMavenVersion());
        bog.put("android_maven_plugin", packageData.getAndroidMavenPlugin());
        bog.put("package_language", packageData.getLangauge());
    }

    /**
     * Write the platform data to the bill of goods.
     *
     * @param platform      Platform data object.
     * @param bog           Bill of goods hash map.
     */
    public static void writePlatformInBOG(PlatformData platform, HashMap<String, String> bog)
    {
        bog.put("platform", platform.getPlatformPath());
    }

    /**
     * Write the version to the bill of goods. this may be handy as the system evolves.
     *
     * @param bog   Bill of goods hash map.
     */
    public static void writeVersionInBOG(HashMap<String, String> bog)
    {
        bog.put("version", QuartermasterServer.getBOGVersion());
    }

    /**
     * Write the dependency list to the bill of goods.
     *
     * @param dependencyList    The list of dependencies
     * @param bog               The bill of goods hash map.
     */
    public static void writeDependencyListInBOG(String dependencyList, HashMap<String, String> bog)
    {
        bog.put("packagedependencylist", dependencyList);
    }

    /**
     * Write an error message into the hash map using the standard error key.
     *
     * @param message       The error message
     * @param bog           The hash map
     */
    public static void writeErrorMsgInBOG(String message, HashMap<String, String> bog)
    {
        bog.put(StringUtil.ERROR_KEY, message);
    }

}
