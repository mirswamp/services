// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2016 Software Assurance Marketplace

package org.cosalab.swamp.test.arcontroller;

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
 * User: jjohnson@morgridgeinstitute.org
 * Date: 8/15/13
 * Time: 12:19 PM
 */
public class AssessmentRunControllerTest
{
    /** Set up logging for this class. */
    private static final Logger LOG = Logger.getLogger(AssessmentRunControllerTest.class.getName());

    /**
     * Main method for the run controller test. For this test to function, the assessment
     * run controller must be running.
     *
     * @param args      Command line arguments are ignored.
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

        // set up as a client of the agent dispatcher
        String controlURL = ConfigFileUtil.getDispatcherURL(prop);

        XmlRpcClient controlClient = null;

        try
        {
            XmlRpcClientConfigImpl controlConfig = new XmlRpcClientConfigImpl();
            controlConfig.setServerURL(new URL(controlURL));
            controlClient = new XmlRpcClient();
            controlClient.setConfig(controlConfig);
        }
        catch (MalformedURLException e)
        {
            LOG.error("bad dispatcher URL: " + controlURL);
            System.exit(0);
        }

        testSonatypeBillOfGoods(controlClient);

    }

    /**
     * Test the SonatypeRunHandler's bill of goods method.
     *
     * @param client  XML-RPC client which should be able to communicate with the assessment run controller
     * @return true if we receive the bill of goods, false otherwise
     */

    private static boolean testSonatypeBillOfGoods(XmlRpcClient client)
    {
        boolean success = false;

        HashMap<String, String> resultHash, requestMap;
        ArrayList params;

        try
        {
            requestMap = new HashMap<String, String>();
            requestMap.put("gav", "test-gav");
            requestMap.put("packagename", "test-package-name.foo");
            requestMap.put("packagepath", "/test-path/test-package-name.foo");
            params = new ArrayList();
            params.add(requestMap);
            resultHash = (HashMap<String, String>)client.execute("swamp.sonatypeRunController.doTestBOG", params);
            LOG.info("test results");
            for (Map.Entry<String, String> entry : resultHash.entrySet())
            {
                LOG.info("Key = " + entry.getKey() + ", Value = " + entry.getValue());
            }

            // TODO add some meaningful testing of the bill of goods contents

        }
        catch (XmlRpcException e)
        {
            LOG.error("could not send request to assessment run controller: " + e.getMessage());
        }

        return success;
    }

}
