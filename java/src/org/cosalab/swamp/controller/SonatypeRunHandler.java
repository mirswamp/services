// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2016 Software Assurance Marketplace

package org.cosalab.swamp.controller;

import org.apache.log4j.Logger;
import org.apache.xmlrpc.XmlRpcException;
import org.apache.xmlrpc.client.XmlRpcClient;
import org.cosalab.swamp.dispatcher.AgentDispatcher;
import org.cosalab.swamp.util.StringUtil;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.HashMap;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson@morgridgeinstitute.org
 * Date: 7/29/13
 * Time: 3:32 PM
 */
public class SonatypeRunHandler implements RunController
{
    /** Set up logging for this class. */
    private static final Logger LOG = Logger.getLogger(SonatypeRunHandler.class.getName());
    /** Error key for hash maps. */
    private static final String ERROR_KEY = StringUtil.ERROR_KEY;

    /** Command strings. */
    private final String cmdStart, cmdCreateID;
    /** Directory prefix (root of results folder). */
    private final String dirPrefix;

    /**
     * Constructor is called when the assessment run controller gets a request
     */
    public SonatypeRunHandler()
    {
        LOG.info("*** The Sonatype Run Handler is on the job ***");
        // retrieve xml-xpc commands from the assessment run controller
        cmdStart = AgentDispatcher.getStringStart();
        cmdCreateID = AgentDispatcher.getStringCreateExecID();
        // get the sonatype root directory from the assessment run controller
        dirPrefix = AgentDispatcher.getSonatypeRootDir();
    }

    /**
     * Handle an error by logging it and then adding the error message to the result hash map.
     *
     * @param bog       The result hash map.
     * @param msg       The error message.
     */
    protected void handleError(HashMap<String, String> bog, String msg)
    {
        LOG.error(msg);
        bog.put(ERROR_KEY, msg);
    }

    /**
     * Assemble all the required information to launch an assessment run and pass it to the launch pad.
     *
     * @param args  Hash map that contains the required input information
     * @return      Hash map with the results of launching the run.
     */
    @Override
    public HashMap<String, String> doRun(HashMap<String, String> args)
    {
        // create the results hash map - this wil be the return value of the method.
        HashMap<String, String> results = new HashMap<String, String>();

        // make sure we have what we need to launch the assessment run
        if (args == null)
        {
            handleError(results, "null argument");
            return results;
        }

        String gav = args.get("gav");
        if (gav == null || gav.isEmpty())
        {
            handleError(results, "invalid GAV");
            return results;
        }

        String packageName = args.get("packagename");
        if (packageName == null || packageName.isEmpty())
        {
            handleError(results, "package name is invalid");
            return results;
        }

        String packagePath = args.get("packagepath");
        if (packagePath == null || packagePath.isEmpty())
        {
            handleError(results, "package path is invalid");
            return results;
        }

        LOG.debug("** GAV: " + gav + " package name: " + packageName + " package path: " + packagePath + " **");

        // set ourselves up as a client for the launch pad
        LaunchPadClient launchPadClient = LaunchPadClient.getInstance();
        XmlRpcClient client = launchPadClient.getClient();
        if (client == null)
        {
            String msg = "problem initializing the launch pad client";
            handleError(results, msg);
            return results;
        }

        // ask the launch pad for an exec ID
        String execrunID;
        try
        {
            execrunID = getExecRunID(client);
        }
        catch (XmlRpcException e)
        {
            String msg = "launch pad execution failed: " + e.getMessage();
            LOG.error("error: " + AgentDispatcher.getAgentMonitorURL() + "\n\t\t" + msg);
            results.put(ERROR_KEY, msg);
            return results;
        }

        // we must copy the file here because there is no quartermaster.
        // create a directory using the execrunID and then copy the file - keeping the same file name
        String dirName = dirPrefix + execrunID;
        Path dirPath = Paths.get(dirName);
        Path filePath = dirPath.resolve(packageName);
        Path sourcePath = Paths.get(packagePath);

        try
        {
            copyFile(dirPath, filePath, sourcePath);
        }
        catch (IOException e)
        {
            String msg = "file copying problem: " + e.getMessage();
            handleError(results, msg);
            return results;
        }

        // ok, now assemble the bill of goods
        HashMap <String, String> bog = createSonatypeBillOfGoods(gav, filePath.toFile().getName(),
                                                                 filePath.toFile().getPath(), execrunID);

        // call the launch pad to start the job
        ArrayList params = new ArrayList();
        params.add(bog);
        try
        {
            HashMap<String, String> resultHash = (HashMap<String, String>)client.execute(cmdStart, params);
            if (resultHash.get(ERROR_KEY) != null)
            {
                LOG.error("starting job: error: " + resultHash.get(ERROR_KEY));
            }
            else
            {
                LOG.info("job started: " + gav);
            }
        }
        catch (XmlRpcException e)
        {
            String msg = "launchpad execution failed: " + e.getMessage();
            handleError(results, msg);
            return results;
        }

        // all done
        return results;
    }

    /**
     * Get the execution run ID from the agent monitor
     *
     * @param client    xml-rpc client that talks to the agent monitor
     * @return          string containing the exec run ID
     * @throws XmlRpcException
     */
    private String getExecRunID(XmlRpcClient client) throws XmlRpcException
    {
        ArrayList params = new ArrayList();
        HashMap<String, String> resultHash, requestHash;
        // no arguments needed - send an empty hash map
        requestHash = new HashMap<String, String>();
        params.add(requestHash);

        resultHash = (HashMap<String, String>)client.execute(cmdCreateID, params);
        String execrunID = resultHash.get("execrunid");
        LOG.debug("retrieve execrunid: " + execrunID);

        return execrunID;
    }

    /**
     * Copies a file to a new directory
     * @param dirPath       path of the new directory that is created
     * @param filePath      path of the file in the new directory
     * @param sourcePath    path of the source file
     * @throws IOException
     */
    private void copyFile(Path dirPath, Path filePath, Path sourcePath) throws IOException
    {
        Files.createDirectory(dirPath);
        LOG.debug("directory created: " + dirPath.toFile().getName());
        Files.copy(sourcePath, filePath);
        LOG.debug("file copied to: " + filePath.toFile().getPath());
    }

    /**
     * Creates the bill of goods for a Sonatype assessment run on a package
     *
     * @param gav   the package's gav
     * @param name  name of the package
     * @param path  full path to the package on the filesystem
     * @param runID the execrun id for the assessment run
     * @return a HashMap containing the bill of goods.
     */
    private HashMap<String, String> createSonatypeBillOfGoods(String gav, String name, String path, String runID)
    {
        HashMap<String, String> bog = new HashMap<String, String>();

        bog.put("execrunid", runID);
        bog.put("platform", "rhel-6.4-64");
        bog.put("toolname", "FindBugs.1.2.3.4");
        bog.put("toolpath", dirPrefix + "exectest/findbugs-2.0.2.tar.gz");
        bog.put("toolinvoke", "findbugs-2.0.2/bin/findbugs packageinvoke");
        bog.put("tooldeploy", "tar xvf toolpath");
        bog.put("packagename", name);
        bog.put("packagebuild", "");
        bog.put("packagedeploy", "");
        bog.put("packageinvoke", name);
        bog.put("packagepath", path);

        bog.put("resultsfolder", dirPrefix + "results/");
        bog.put("gav", gav);

        return bog;
    }

    /**
     * Run a simple test of the bill of goods creation for a sonatype project run.
     *
     * @param args      Hash map with the arguments needed to create a bill of goods.
     * @return          Bill of goods hash map.
     */
    public HashMap<String, String> doTestBOG(HashMap<String, String> args)
    {
        String gav = args.get("gav");
        if (gav == null || gav.isEmpty())
        {
            LOG.warn("problem with test GAV");
            gav = "bad-gav";
        }

        String name = args.get("packagename");
        if (name == null || name.isEmpty())
        {
            LOG.warn("problem with test file name");
            name = "bad-file-name";
        }

        String path = args.get("packagepath");
        if (path == null || path.isEmpty())
        {
            LOG.warn("problem with test file path");
            path = "bad-file-path";
        }

        return createSonatypeBillOfGoods(gav, name, path, "test-run-id");
    }

}
