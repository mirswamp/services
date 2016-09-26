// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2016 Software Assurance Marketplace

package org.cosalab.swamp.quartermaster;

import org.apache.log4j.Logger;
import org.apache.xmlrpc.XmlRpcException;
import org.apache.xmlrpc.server.PropertyHandlerMapping;
import org.apache.xmlrpc.server.XmlRpcServer;
import org.apache.xmlrpc.webserver.WebServer;
import org.cosalab.swamp.util.ConfigFileUtil;
import org.cosalab.swamp.util.StringUtil;

import java.io.IOException;
import java.util.Properties;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 9/13/13
 * Time: 11:00 AM
 */
public class QuartermasterServer
{
    /** Set up logging for the quartermaster server class. */
    private static final Logger LOG = Logger.getLogger(QuartermasterServer.class.getName());

    /** The quartermaster database URL. */
    private static String dbQuarterURL;
    /** The quartermaster database user name. */
    private static String dbQuarterUser;
    /** The quartermaster database password. */
    private static String dbQuarterPass;

    /** The version of the bil of goods. Not really needed now, but for future use. */
    private static final String BOG_VERSION = "2";

    /**
     * Get the quartermaster database URL.
     *
     * @return      The URL.
     */
    public static String getDbQuartermasterURL()
    {
        return dbQuarterURL;
    }

    /**
     * Get the quartermaster database user name.
     *
     * @return      The user name.
     */
    public static String getDbQuatermasterUser()
    {
        return dbQuarterUser;
    }

    /**
     * Get the quartermaster database password.
     *
     * @return      The password.
     */
    public static String getDbQuartermasterPasswd()
    {
        return dbQuarterPass;
    }

    /**
     * Get the bill of goods version number.
     *
     * @return      The version number as a string.
     */
    public static String getBOGVersion()
    {
        return BOG_VERSION;
    }

    /**
     * The quartermaster's main method.
     *
     * @param args  The command line arguments are ignored.
     */
    public static void main (String [] args)
    {
        // get configuration properties
        Properties prop = ConfigFileUtil.getSwampConfigProperties(ConfigFileUtil.SWAMP_CONFIG_DEFAULT_FILE);
        if (prop == null)
        {
            // could not find the configuration file, so we will have to quit.
            LOG.error("*** fatal error: could not find configuration file. ***");
            System.exit(0);
        }

        // get the Quartermaster's database stuff
        dbQuarterURL = prop.getProperty("dbQuartermasterURL", "");
        // need to trim these two just in case there are spaces on the end of the line in the config file
        dbQuarterUser = prop.getProperty("dbQuartermasterUser", "").trim();
        dbQuarterPass = prop.getProperty("dbQuartermasterPass", "").trim();

        try
        {
            // get the correct port for the controller to act as a server
            int serverPort = Integer.parseInt(ConfigFileUtil.getQuartermasterPort(prop));

            // initialize the XML-RPC server
            initServer(serverPort);
        }
        catch (XmlRpcException exception)
        {
            LOG.error("QuatermasterServer XML-RPC exception: " + exception.getMessage());
        }
        catch (IOException exception)
        {
            LOG.error("QuatermasterServer IO exception: " + exception.getMessage());
        }
    }

    /**
     * Initialize the XML-RPC server.
     *
     * @param serverPort        Port number for the server to listen on.
     * @throws XmlRpcException
     * @throws IOException
     */
    private static void initServer(int serverPort) throws XmlRpcException, IOException
    {
        LOG.info("Attempting to start Quartermaster XML-RPC Server...");
        WebServer webServer = new WebServer(serverPort);
//            webServer.acceptClient("127.0.0.1");

        XmlRpcServer server =  webServer.getXmlRpcServer();
        PropertyHandlerMapping phm = new PropertyHandlerMapping();
        phm.addHandler("swamp.quartermaster", QuartermasterHandler.class);
        phm.addHandler("swamp.gator", GatorHandler.class);
        phm.addHandler("swamp.admin", AdminHandler.class);
        server.setHandlerMapping(phm);

        webServer.start();
        LOG.info("Started successfully.");
        LOG.info("Quartermaster Java version: " + StringUtil.getJavaVersion());
        LOG.info("Accepting requests on port " + serverPort + ". (Halt program to stop.)");
    }
}
