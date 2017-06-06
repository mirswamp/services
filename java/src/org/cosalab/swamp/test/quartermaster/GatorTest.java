// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.test.quartermaster;

import org.apache.log4j.Logger;
import org.apache.xmlrpc.XmlRpcException;
import org.apache.xmlrpc.client.XmlRpcClient;
import org.apache.xmlrpc.client.XmlRpcClientConfigImpl;
import org.cosalab.swamp.util.ConfigFileUtil;
import org.cosalab.swamp.util.StringUtil;

import java.net.MalformedURLException;
import java.net.URL;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;
import java.util.Properties;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 8/27/13
 * Time: 2:58 PM
 */
public class GatorTest
{
    /** Set up logging for the gator test class. The results of the tests will be displayed in the log. */
    private static final Logger LOG = Logger.getLogger(GatorTest.class.getName());

    /** Command strings. */
    private static String cmdListTools, cmdListPackages, cmdListPlatforms;

    private static boolean useDispatcher = true;

    /**
     * The gator test main method. This method controls the tests that will be run.
     *
     * @param args      The args are not currently used in this method.
     */
    public static void main(String[] args)
    {
        // read the configuration file
        // get configuration properties
        Properties prop = ConfigFileUtil.getSwampConfigProperties(ConfigFileUtil.SWAMP_CONFIG_DEFAULT_FILE);
        if (prop == null)
        {
            // could not find the configuration file, so we will have to quit.
            LOG.error("*** fatal error: could not find configuration file. ***");
            System.exit(0);
        }

        // set up as a client of the quartermaster or agent dispatcher
        // get the XML-RPC controller URL
        String quartermasterURL = ConfigFileUtil.getQuartermasterURL(prop);
        String dispatcherURL = ConfigFileUtil.getDispatcherURL(prop);
        LOG.info("\t quartermaster URL: " + quartermasterURL);
        LOG.info("\t dispatcher URL: " + dispatcherURL);

        // method name translations.
        cmdListTools = ConfigFileUtil.getMethodString("method.GATOR_LISTTOOLS", prop);
        cmdListPackages = ConfigFileUtil.getMethodString("method.GATOR_LISTPACKAGES", prop);
        cmdListPlatforms = ConfigFileUtil.getMethodString("method.GATOR_LISTPLATFORMS", prop);

        String serverURL;
        if (useDispatcher)
        {
            serverURL = dispatcherURL;
            LOG.info("*** use Dispatcher ***");
        }
        else
        {
            serverURL = quartermasterURL;
            LOG.info("*** use Quartermaster ***");
        }

        XmlRpcClient client = null;

        try
        {
            XmlRpcClientConfigImpl config = new XmlRpcClientConfigImpl();
            config.setServerURL(new URL(serverURL));
            client = new XmlRpcClient();
            client.setConfig(config);
        }
        catch (MalformedURLException e)
        {
            LOG.error("bad quartermaster URL: " + quartermasterURL);
            System.exit(0);
        }

        if(testPlatformList(client))
        {
            LOG.info("*** testPlatformList succeeded. ***");
        }
        else
        {
            LOG.info("*** testPlatformList failed. ***");
        }

        if(testPackageList(client))
        {
            LOG.info("*** testPackageList succeeded. ***");
        }
        else
        {
            LOG.info("*** testPackageList failed. ***");
        }

        if(testToolList(client))
        {
            LOG.info("*** testToolList succeeded. ***");
        }
        else
        {
            LOG.info("*** testToolList failed. ***");
        }
    }

    /**
     * Perform the tool list test: retrieve the tool list from the quartermaster server and display
     * it in the log.
     *
     * @param client    The quartermaster client.
     * @return          true if the tool list was retrieved and displayed; false otherwise.
     */
    private static boolean testToolList(XmlRpcClient client)
    {
        boolean success = false;

        HashMap<String, String> resultHash;
        ArrayList params;

        try
        {
            params = new ArrayList();
            resultHash = (HashMap<String, String>)client.execute(cmdListTools, params);
            LOG.info("tool test results");
            for (Map.Entry<String, String> entry : resultHash.entrySet())
            {
                LOG.info("Key = " + entry.getKey() + ", Value = " + entry.getValue());
            }

            if (!resultHash.containsKey(StringUtil.ERROR_KEY))
            {
                success = true;
            }

        }
        catch (XmlRpcException e)
        {
            LOG.error("could not send request to quartermaster: " + e.getMessage());
        }

        return success;
    }

    /**
     * Perform the package list test: retrieve the list of packages from the quartermaster and
     * display it in the log.
     *
     * @param client    The quartermaster client.
     * @return          true if the package list test is successful; false otherwise.
     */
    private static boolean testPackageList(XmlRpcClient client)
    {
        boolean success = false;

        HashMap<String, String> resultHash;
        ArrayList params;

        try
        {
            params = new ArrayList();
            resultHash = (HashMap<String, String>)client.execute(cmdListPackages, params);
            LOG.info("package test results");
            for (Map.Entry<String, String> entry : resultHash.entrySet())
            {
                LOG.info("Key = " + entry.getKey() + ", Value = " + entry.getValue());
            }

            if (!resultHash.containsKey(StringUtil.ERROR_KEY))
            {
                success = true;
            }

        }
        catch (XmlRpcException e)
        {
            LOG.error("could not send request to quartermaster: " + e.getMessage());
        }

        return success;
    }

    /**
     * Perform the platform list test: retrieve the list of platforms from the quartermaster and
     * display it in the log file.
     *
     * @param client    The quartermaster client.
     * @return          true if the platform list test is successful; false otherwise.
     */
    private static boolean testPlatformList(XmlRpcClient client)
    {
        boolean success = false;

        HashMap<String, String> resultHash;
        ArrayList params;

        try
        {
            params = new ArrayList();
            resultHash = (HashMap<String, String>)client.execute(cmdListPlatforms, params);
            LOG.info("platform test results");
            for (Map.Entry<String, String> entry : resultHash.entrySet())
            {
                LOG.info("Key = " + entry.getKey() + ", Value = " + entry.getValue());
            }

            if (!resultHash.containsKey(StringUtil.ERROR_KEY))
            {
                success = true;
            }

        }
        catch (XmlRpcException e)
        {
            LOG.error("could not send request to quartermaster: " + e.getMessage());
        }

        return success;
    }
}
