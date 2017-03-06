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
 * Date: 8/30/13
 * Time: 2:07 PM
 */

// you may need to run the QuartermasterServer with the JVM argument -Dtesting=true
public class QuartermasterTest
{
    /** Set up logging for the quartermaster test class. */
    private static final Logger LOG = Logger.getLogger(QuartermasterTest.class.getName());

    /** Command strings. */
    private static String serverCmdBOG, serverCmdViewerUpdate;

    /** Package test data. */
    private static String package1 = "7999443d-163c-11e3-b57a-001a4a81450b";
    /** Package test data. */
    private static String package2 = "f36c74e4-6eae-f3e0-810f-a3d6da770cd3";
    /** Tool test data. */
    private static String tool1 = "16414980-156e-11e3-a239-001a4a81450b";
    /** Platform test data. */
    private static String platform1 = "fc5737ef-09d7-11e3-a239-001a4a81450b";
    /** Platform test data. */
    private static String platform2 = "35bc77b9-7d3e-11e3-88bb-001a4a81450b";

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
        serverCmdBOG = ConfigFileUtil.getMethodString("method.QUARTERMASTER_BILLOFGOODS", prop);
        serverCmdViewerUpdate = ConfigFileUtil.getMethodString("method.QUARTERMASTER_UPDATEVIEWER", prop);
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

        String packageID = package1;
        String toolID = tool1;
        String platformID = platform2;

        boolean result;
        if (args.length == 0)
        {
            result = testBillOfGoods(client, platformID, toolID, packageID);
            if (result)
            {
                LOG.info("quartermaster test succeeded");
            }
            else
            {
                LOG.info("quartermaster test failed");
            }
        }
        else
        {
            for (String s : args)
            {
                if (s.equalsIgnoreCase("updateviewer"))
                {
                    result = testViewerUpdate(client);
                }
                else
                {
                    result = testBillOfGoods(client, platformID, toolID, packageID);
                }

                if (result)
                {
                    LOG.info("quartermaster test succeeded");
                }
                else
                {
                    LOG.info("quartermaster test failed");
                }
            }
        }

    }

    /**
     * Perform the bill of goods test: send a request to the quartermaster and check the BOG.
     *
     * @param client    The quartermaster XML-RPC client.
     * @param platID    The platform uuid.
     * @param toolID    The tool uuid.
     * @param packID    The package uuid.
     * @return          true if the test succeeds; false otherwise.
     */
    private static boolean testBillOfGoods(XmlRpcClient client, String platID, String toolID, String packID)
    {
        boolean success = false;

        HashMap<String, String> resultHash, requestMap;
        ArrayList params;

        try
        {
            requestMap = new HashMap<String, String>();
            requestMap.put("execrunid", "123-quartermaster-test");
            requestMap.put("projectid", "bogus");
            requestMap.put("platformid", platID);
            requestMap.put("toolid", toolID);
            requestMap.put("packageid", packID);
            params = new ArrayList();
            params.add(requestMap);
            resultHash = (HashMap<String, String>)client.execute(serverCmdBOG, params);
            LOG.info("test bill of goods results");
            for (Map.Entry<String, String> entry : resultHash.entrySet())
            {
                LOG.info("Key = " + entry.getKey() + ", Value = " + entry.getValue());
            }

            if (!resultHash.containsKey("error"))
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
     * Perform the viewer update test: send a dummy viewer update to the quartermaster.
     *
     * @param client    The quartermaster XML-RPC client.
     * @return          true if the test succeeds; false otherwise.
     */
    private static boolean testViewerUpdate(XmlRpcClient client)
    {
        boolean success = false;

        HashMap<String, String> resultHash, requestMap;
        ArrayList params;

        try
        {
            requestMap = new HashMap<String, String>();
            requestMap.put("vieweruuid", "6606b99e-cb01-11e3-8775-001a4a81450b");
            requestMap.put("viewerstatus", "blatz");
//            requestMap.put("vieweraddress", "127.0.0.1");
            requestMap.put("viewerproxyurl", "null");
            params = new ArrayList();
            params.add(requestMap);
            resultHash = (HashMap<String, String>)client.execute(serverCmdViewerUpdate, params);
            LOG.info("test viewer update results");
            for (Map.Entry<String, String> entry : resultHash.entrySet())
            {
                LOG.info("Key = " + entry.getKey() + ", Value = " + entry.getValue());
            }

            if (!resultHash.containsKey("error"))
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
/*
    private static boolean testStoreViewer(XmlRpcClient client)
    {
        boolean success = false;

        HashMap<String, String> resultHash, requestMap;
        ArrayList params;

        try
        {
            requestMap = new HashMap<String, String>();
            requestMap.put("execrunid", "123-quartermaster-test");
            requestMap.put("platformid", "fc5737ef-09d7-11e3-a239-001a4a81450b");
            requestMap.put("toolid", "16414980-156e-11e3-a239-001a4a81450b");
            requestMap.put("packageid", "7999443d-163c-11e3-b57a-001a4a81450b");
            params = new ArrayList();
            params.add(requestMap);
            resultHash = (HashMap<String, String>)client.execute("swamp.quartermaster.storeViewerDatabase", params);
            LOG.info("test store viewer database results");
            for (Map.Entry<String, String> entry : resultHash.entrySet())
            {
                LOG.info("Key = " + entry.getKey() + ", Value = " + entry.getValue());
            }

            if (!resultHash.containsKey("error"))
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
    */

}
