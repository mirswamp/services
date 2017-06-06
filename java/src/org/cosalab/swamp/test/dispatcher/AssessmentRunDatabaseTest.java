// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.test.dispatcher;

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
 * Date: 9/17/13
 * Time: 2:23 PM
 */
public class AssessmentRunDatabaseTest
{
    /** Set up logging for this class. */
    private static final Logger LOG = Logger.getLogger(AssessmentRunDatabaseTest.class.getName());

    /** Test failed message. */
    private static final String TEST_FAIL = "*** test failed ***";
    /** Successful test message. */
    private static final String TEST_PASS = "*** test succeeded ***";
    /** Error key for hash maps. */
    private static final String ERROR_KEY = "error";
    /** Run uuid key for hash maps. */
    private static final String RUN_ID_KEY = "execrunid";

    /** Common error related string. */
    private static final String ERROR_FOUND_IN_RESULT_STRING = "error found in result hash map: ";

    /**
     * Main method for test. For this to work, the agent dispatcher must be running.
     *
     * @param args      The command line arguments are ignored.
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
        String dispatcherURL = ConfigFileUtil.getDispatcherURL(prop);

        XmlRpcClient dispatchClient = null;

        try
        {
            XmlRpcClientConfigImpl dispatchConfig = new XmlRpcClientConfigImpl();
            dispatchConfig.setServerURL(new URL(dispatcherURL));
            dispatchClient = new XmlRpcClient();
            dispatchClient.setConfig(dispatchConfig);
        }
        catch (MalformedURLException e)
        {
            LOG.error("bad dispatcher URL: " + dispatcherURL);
            System.exit(0);
        }

        String testid = "a01f8714-f391-11e6-bf70-001a4a81450b";
/*
        if (testDispatcherBog(dispatchClient, testid))
        {
            LOG.info(TEST_PASS);
        }
        else
        {
            LOG.error(TEST_FAIL);
        }

*/

        testid = "TEST_EXEC_UUID";
/*
        if (testExecCollectorDB(dispatchClient, testid))
        {
            LOG.info(TEST_PASS);
        }
        else
        {
            LOG.error(TEST_FAIL);
        }
*/
        if (testExecCollectorSingleRecord(dispatchClient, testid))
        {
            LOG.info(TEST_PASS);
        }
        else
        {
            LOG.error(TEST_FAIL);
        }

        if (testExecCollectorFieldUpdate(dispatchClient, testid))
        {
            LOG.info(TEST_PASS);
        }
        else
        {
            LOG.error(TEST_FAIL);
        }

        if (testExecCollectorSingleRecord(dispatchClient, testid))
        {
            LOG.info(TEST_PASS);
        }
        else
        {
            LOG.error(TEST_FAIL);
        }

/*
        if (testResultCollectorDB(dispatchClient, testid))
        {
            LOG.info(TEST_PASS);
        }
        else
        {
            LOG.error(TEST_FAIL);
        }
        */
    }

    private static boolean testAssessmentRunDB(XmlRpcClient client, String runID)
    {
        boolean success = false;

        HashMap<String, String> resultHash, requestMap;
        ArrayList params;

        try
        {
            requestMap = new HashMap<String, String>();
            requestMap.put(RUN_ID_KEY, runID);
            params = new ArrayList();
            params.add(requestMap);
            resultHash = (HashMap<String, String>)client.execute("swamp.runController.doDatabaseTest", params);
            logHashMap(resultHash, "database test results");

            if (runID.equalsIgnoreCase(resultHash.get(RUN_ID_KEY)))
            {
                success = true;
            }

            if (resultHash.containsKey(ERROR_KEY))
            {
                LOG.info(ERROR_FOUND_IN_RESULT_STRING + resultHash.get(ERROR_KEY));
                success = false;
            }

        }
        catch (XmlRpcException e)
        {
            LOG.error("could not send request to run controller: " + e.getMessage());
        }

        return success;
    }


    private static boolean testDispatcherBog(XmlRpcClient client, String runID)
    {
        boolean success = false;

        HashMap<String, String> resultHash, requestMap;
        ArrayList params;

        try
        {
            requestMap = new HashMap<String, String>();
            requestMap.put(RUN_ID_KEY, runID);
            params = new ArrayList();
            params.add(requestMap);
            resultHash = (HashMap<String, String>)client.execute("swamp.runController.doBogTest", params);
            logHashMap(resultHash, "dispather BOG test results");

            if (runID.equalsIgnoreCase(resultHash.get(RUN_ID_KEY)))
            {
                success = true;
            }

            if (resultHash.containsKey(ERROR_KEY))
            {
                LOG.info(ERROR_FOUND_IN_RESULT_STRING + resultHash.get(ERROR_KEY));
                success = false;
            }
        }
        catch (XmlRpcException e)
        {
            LOG.error("could not send request to run controller: " + e.getMessage());
        }

        return success;
    }

    private static boolean testExecCollectorDB(XmlRpcClient client, String runID)
    {
        boolean success = false;

        String status = "X_COMPLETE";
        String timeStart = "Thu Sep 19 12:42:07 2013";
        String timeEnd = "Thu Sep 19 13:19:30 2013";
        String execNode = "NODULE_2";
        int loc = 100;
        String cpuUtil = "d__98.6";
        String timestamp = "__1379612605";

        HashMap<String, String> resultHash, requestMap;
        ArrayList params;

        try
        {
            requestMap = new HashMap<String, String>();
            requestMap.put(RUN_ID_KEY, runID);
            requestMap.put("status", status);
            requestMap.put("run_date", timeStart);
            requestMap.put("completion_date", timeEnd);
            requestMap.put("execute_node_architecture_id", execNode);
            requestMap.put("lines_of_code", "__" + loc);
            requestMap.put("cpu_utilization", cpuUtil);
            requestMap.put("timestamp", timestamp);
            params = new ArrayList();
            params.add(requestMap);
            resultHash = (HashMap<String, String>)client.execute("swamp.execCollector.updateExecutionResults", params);
            logHashMap(resultHash, "exec collector database test results");

            if (resultHash.containsKey(ERROR_KEY))
            {
                LOG.info(ERROR_FOUND_IN_RESULT_STRING + resultHash.get(ERROR_KEY));
            }
            else
            {
                success = true;
            }

        }
        catch (XmlRpcException e)
        {
            LOG.error("could not send request to run controller: " + e.getMessage());
        }

        return success;
    }

    private static boolean testExecCollectorSingleRecord(XmlRpcClient client, String runID)
    {
        boolean success = false;

        HashMap<String, String> resultHash, requestMap;
        ArrayList params;

        try
        {
            requestMap = new HashMap<String, String>();
            requestMap.put(RUN_ID_KEY, runID);
            params = new ArrayList();
            params.add(requestMap);
            resultHash = (HashMap<String, String>)client.execute("swamp.execCollector.getSingleExecutionRecord", params);
            logHashMap(resultHash, "exec collector single record results");

            if (runID.equalsIgnoreCase(resultHash.get(RUN_ID_KEY)))
            {
                success = true;
            }

            if (resultHash.containsKey(ERROR_KEY))
            {
                LOG.info(ERROR_FOUND_IN_RESULT_STRING + resultHash.get(ERROR_KEY));
                success = false;
            }

        }
        catch (XmlRpcException e)
        {
            LOG.error("could not send request to run controller: " + e.getMessage());
        }

        return success;
    }

    private static boolean testExecCollectorFieldUpdate(XmlRpcClient client, String runID)
    {
        boolean success = false;

        String status = "blort69";
        String timeStart = "Thu Sep 19 12:42:07 2013";
        String timeEnd = "Thu Sep 19 13:19:30 2013";
        String execNode = "NODULE_KM";
        int loc = 1485;
        String cpuUtil = "d__98.6";
        String timestamp = "__1379612605";
        String vm_password = "mobyFoo";
        String vm_hostname = "MIT-MC";
        String vm_username = "Lar-the-Bear";
        String tool_filename = "Screwdriver.exe";
        String vm_image = "cheap-mirrorX";
        String vm_ip_address = "127.0.0.2";

        HashMap<String, String> resultHash, requestMap;
        ArrayList params;

        try
        {
            requestMap = new HashMap<String, String>();
            requestMap.put(RUN_ID_KEY, runID);
            requestMap.put("statusX", status);
            requestMap.put("run_date", timeStart);
            requestMap.put("completion_date", timeEnd);
            requestMap.put("execute_node_architecture_id", execNode);
            requestMap.put("lines_of_code", "__" + loc);
            requestMap.put("cpu_utilization", cpuUtil);
            requestMap.put("timestamp", timestamp);           // is this in the new query? is it still used?
            requestMap.put("vm_password", vm_password);
            requestMap.put("vm_hostname", vm_hostname);
            requestMap.put("vm_username", vm_username);
            requestMap.put("tool_filename", tool_filename);
            requestMap.put("vmip", vm_ip_address);
            requestMap.put("vm_image", vm_image);
            params = new ArrayList();
            params.add(requestMap);
            resultHash = (HashMap<String, String>)client.execute("swamp.execCollector.updateExecutionResults", params);
            logHashMap(resultHash, "exec collector updateExecutionResultsTest results");

            if (runID.equalsIgnoreCase(resultHash.get(RUN_ID_KEY)))
            {
                success = true;
            }

            if (resultHash.containsKey(ERROR_KEY))
            {
                LOG.info(ERROR_FOUND_IN_RESULT_STRING + resultHash.get(ERROR_KEY));
                success = false;
            }

        }
        catch (XmlRpcException e)
        {
            LOG.error("could not send request to run controller: " + e.getMessage());
        }

        return success;
    }


    private static boolean testResultCollectorDB(XmlRpcClient client, String runID)
    {
        boolean success = false;

        String resultPath = "/var/lib/mysql/test_result.result";
        String resultChecksum = "12345";
        String sourcePath = "/var/lib/mysql/test_source.archive";
        String sourceChecksum = "23459";
        String logPath = "/var/lib/mysql/test_log.log";
        String logChecksum = "34567";

        HashMap<String, String> resultHash, requestMap;
        ArrayList params;

        try
        {
            requestMap = new HashMap<String, String>();
            requestMap.put(RUN_ID_KEY, runID);
            requestMap.put("pathname", resultPath);
            requestMap.put("sha512sum", resultChecksum);
            requestMap.put("sourcepathname", sourcePath);
            requestMap.put("source512sum", sourceChecksum);
            requestMap.put("logpathname", logPath);
            requestMap.put("log512sum", logChecksum);

            params = new ArrayList();
            params.add(requestMap);
            resultHash = (HashMap<String, String>)client.execute("swamp.resultCollector.testResultsDB", params);
            logHashMap(resultHash, "result collector database test results");

            success = true;

            if (resultHash.containsKey(ERROR_KEY))
            {
                LOG.info(ERROR_FOUND_IN_RESULT_STRING + resultHash.get(ERROR_KEY));
                success = false;
            }

        }
        catch (XmlRpcException e)
        {
            LOG.error("could not send request to result collector: " + e.getMessage());
        }

        return success;
    }

    private static void logHashMap(HashMap<String, String> resultHash, String title)
    {
        LOG.info(title);
        for (Map.Entry<String, String> entry : resultHash.entrySet())
        {
            LOG.info("Key = " + entry.getKey() + ", Value = " + entry.getValue());
        }
    }

}
