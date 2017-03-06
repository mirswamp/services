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

import java.net.MalformedURLException;
import java.net.URL;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;
import java.util.Properties;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 5/2/14
 * Time: 2:24 PM
 */
public class AdminTest
{
    /** Set up logging for the admin test class. */
    private static final Logger LOG = Logger.getLogger(AdminTest.class.getName());

    /** Command strings. */
    private static String cmdInsertEvent, cmdInsertStatus;

    /**
     * Main method for test.
     *
     * @param args      Command line arguments are not used.
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

        // set up as a client of the quartermaster
        // get the XML-RPC controller URL
        String quartermasterURL = ConfigFileUtil.getQuartermasterURL(prop);
        cmdInsertEvent = ConfigFileUtil.getMethodString("method.ADMIN_INSERT_EXEC_EVENT", prop);
        cmdInsertStatus = ConfigFileUtil.getMethodString("method.ADMIN_INSERT_SYSTEM_STATUS", prop);
        XmlRpcClient client = null;

        try
        {
            XmlRpcClientConfigImpl config = new XmlRpcClientConfigImpl();
            config.setServerURL(new URL(quartermasterURL));
            client = new XmlRpcClient();
            client.setConfig(config);
        }
        catch (MalformedURLException e)
        {
            LOG.error("bad quartermaster URL: " + quartermasterURL);
            System.exit(0);
        }

        if (testEventInsertion(client))
        {
            LOG.info("*** testEventInsertion succeeded. ***");
        }
        else
        {
            LOG.info("*** testEventInsertion failed. ***");
        }

        if (testStatusInsertion(client))
        {
            LOG.info("*** testStatusInsertion succeeded. ***");
        }
        else
        {
            LOG.info("*** testStatusInsertion failed. ***");
        }
    }

    /**
     * Perform the event insertion test on the quartermaster.
     *
     * @param client    The quartermaster XML-RPC client.
     * @return          true if the test succeeds; false otherwise.
     */
    private static boolean testEventInsertion(XmlRpcClient client)
    {
        boolean success = false;

        HashMap<String, String> requestMap, resultHash;
        ArrayList params;

        try
        {
            requestMap = new HashMap<String, String>();
//            requestMap.put("execrecorduuid", "bogus");
            requestMap.put("execrecorduuid", "05592da4-8ba7-11e3-88bb-001a4a81450b");
            requestMap.put("eventtime", "11:07:02.001");
            requestMap.put("eventname", "blatz");
            requestMap.put("eventpayload", "payloads are fun");
            params = new ArrayList();
            params.add(requestMap);

            resultHash = (HashMap<String, String>)client.execute(cmdInsertEvent, params);
            LOG.info("insert event test results");
            for (Map.Entry<String, String> entry : resultHash.entrySet())
            {
                LOG.info("Key = " + entry.getKey() + ", Value = " + entry.getValue());
            }
            success = true;

        }
        catch (XmlRpcException e)
        {
            LOG.error("could not send request to quartermaster: " + e.getMessage());
        }

        return success;
    }

    /**
     * Perform the status insertion test on the quartermaster.
     *
     * @param client    The quartermaster XML-RPC client.
     * @return          true if the test succeeds; false otherwise.
     */
    private static boolean testStatusInsertion(XmlRpcClient client)
    {
        boolean success = false;

        HashMap<String, String> requestMap, resultHash;
        ArrayList params;

        try
        {
            requestMap = new HashMap<String, String>();
//            requestMap.put("execrecorduuid", "bogus");
            requestMap.put("statuskey", "blort");
            requestMap.put("statusvalue", "oblong");
            params = new ArrayList();
            params.add(requestMap);

            resultHash = (HashMap<String, String>)client.execute(cmdInsertStatus, params);
            LOG.info("insert system status results");
            for (Map.Entry<String, String> entry : resultHash.entrySet())
            {
                LOG.info("Key = " + entry.getKey() + ", Value = " + entry.getValue());
            }
            success = true;

        }
        catch (XmlRpcException e)
        {
            LOG.error("could not send request to quartermaster: " + e.getMessage());
        }

        return success;
    }
}
