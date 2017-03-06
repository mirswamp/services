// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.dispatcher;

import org.apache.log4j.Logger;
import org.apache.xmlrpc.XmlRpcException;
import org.apache.xmlrpc.server.PropertyHandlerMapping;
import org.apache.xmlrpc.server.XmlRpcServer;
import org.apache.xmlrpc.webserver.WebServer;
import org.cosalab.swamp.collector.ExecCollectorHandler;
import org.cosalab.swamp.collector.ResultsCollectorHandler;
import org.cosalab.swamp.controller.RunHandler;
import org.cosalab.swamp.util.ConfigFileUtil;
import org.cosalab.swamp.util.StringUtil;

import java.io.IOException;
import java.util.Properties;


/**
 * Created with IntelliJ IDEA.
 * User: jjohnson@morgridgeinstitute.org
 * Date: 7/17/13
 * Time: 8:19 AM
 */
public class AgentDispatcher
{
    /** Set up logging for this class. */
    private static final Logger LOG = Logger.getLogger(AgentDispatcher.class.getName());

    /** URLs for the quartermaster and the agent monitor. */
    private static String quartermasterURL, monitorURL;

    /** Method string. */
    private static final String BILLOFGOODS = "method.QUARTERMASTER_BILLOFGOODS";
    /** Method string. */
    private static final String LAUNCHPAD_START = "method.LAUNCHPAD_START";
    /** Method string. */
    private static final String CSAAGENT_STOP = "method.CSAAGENT_STOP";
    /** Method string. */
    private static final String CREATEEXECID = "method.LAUNCHPAD_CREATEEXECID";

    /** Command strings. */
    private static String serverCmdBOG, serverCmdStart, serverCmdStop, serverCmdCreateID;

    /** Results paths for normal runs. */
    private static String resultsFolderRoot;

    /** The database URL. */
    private static String dbURL;
    /** The database user name. */
    private static String dbUser;
    /** The database password. */
    private static String dbPasswd;

    /**
     * Get the database URL.
     *
     * @return  The URL.
     */
    public static String getDbURL()
    {
        return dbURL;
    }

    /**
     * Get the database user name.
     *
     * @return  The user name.
     */
    public static String getDbUser()
    {
        return dbUser;
    }

    /**
     * Get the database password.
     *
     * @return  The password.
     */
    public static String getDbPasswd()
    {
        return dbPasswd;
    }

    /**
     * Get the Quartermaster URL.
     *
     * @return  The URL.
     */
    public static String getQuartermasterURL()
    {
        return quartermasterURL;
    }

    /**
     * Get the Agent Monitor URL.
     *
     * @return  The URL.
     */
    public static String getAgentMonitorURL()
    {
        return monitorURL;
    }

    /**
     * Get the command string for the BOG.
     *
     * @return  The command string.
     */
    public static String getStringBOG()
    {
        return serverCmdBOG;
    }

    /**
     * Get the command string for Start.
     *
     * @return  The command string.
     */
    public static String getStringStart()
    {
        return serverCmdStart;
    }

    /**
     * Get the command string for Stop.
     *
     * @return  The command string.
     */
    public static String getStringStop()
    {
        return serverCmdStop;
    }

    /**
     * Get the command string for Create an exec run ID.
     *
     * @return  The command string.
     */
    public static String getStringCreateExecID()
    {
        return serverCmdCreateID;
    }

    /**
     * Get the root of the results folder.
     *
     * @return  The results folder root directory.
     */
    public static String getResultsFolderRoot()
    {
        return resultsFolderRoot;
    }

    /**
     * Launch the AgentDispatcher and register the handlers.
     *
     * @param args  The arguments are currently ignored.
     */
    public static void main (final String [] args)
    {
        // get configuration properties
        final Properties prop = ConfigFileUtil.getSwampConfigProperties(ConfigFileUtil.SWAMP_CONFIG_DEFAULT_FILE);
        if (prop == null)
        {
            // could not find the configuration file, so we will have to quit.
            LOG.error("*** fatal error: could not find configuration file. ***");
            System.exit(0);
        }

        // get the XML-RPC quartermaster URL
        quartermasterURL = ConfigFileUtil.getQuartermasterURL(prop);

        monitorURL = ConfigFileUtil.getAgentMonitorURL(prop);

        serverCmdBOG = ConfigFileUtil.getMethodString(BILLOFGOODS, prop);
        serverCmdStart = ConfigFileUtil.getMethodString(LAUNCHPAD_START, prop);
        serverCmdStop = ConfigFileUtil.getMethodString(CSAAGENT_STOP, prop);
        serverCmdCreateID = ConfigFileUtil.getMethodString(CREATEEXECID, prop);

        resultsFolderRoot = ConfigFileUtil.getResultsFolder(prop);

        // get the database stuff
        dbURL = prop.getProperty("dbQuartermasterURL", "");
        dbUser = prop.getProperty("dbQuartermasterUser", "").trim();
        dbPasswd = prop.getProperty("dbQuartermasterPass", "").trim();

        try
        {
            // get the XML-RPC server port
            final int dispatchPort = Integer.parseInt(ConfigFileUtil.getDispatcherPort(prop));

            LOG.info("Attempting to start XML-RPC Server...");
            final WebServer webServer = new WebServer(dispatchPort);
//            webServer.acceptClient("127.0.0.1");

            final XmlRpcServer server =  webServer.getXmlRpcServer();
            final PropertyHandlerMapping phm = new PropertyHandlerMapping();
            phm.addHandler("swamp.resultCollector", ResultsCollectorHandler.class);
            phm.addHandler("swamp.execCollector", ExecCollectorHandler.class);
            phm.addHandler("swamp.runController", RunHandler.class);
            server.setHandlerMapping(phm);

            webServer.start();
            LOG.info("Started successfully.");
            LOG.info("Agent Dispatcher Java version: " + StringUtil.getJavaVersion());
            LOG.info("Accepting requests on port " + dispatchPort + ". (Halt program to stop.)");
            
        }
        catch (XmlRpcException exception)
        {
            LOG.error("AgentDispatcher: " + exception.getMessage());
        }
        catch (IOException exception)
        {
            LOG.error("AgentDispatcher: " + exception.getMessage());
        }
    }
}
