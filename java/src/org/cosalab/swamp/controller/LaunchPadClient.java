// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.controller;

import org.apache.log4j.Logger;
import org.apache.xmlrpc.client.XmlRpcClient;
import org.apache.xmlrpc.client.XmlRpcClientConfigImpl;
import org.cosalab.swamp.dispatcher.AgentDispatcher;

import java.net.MalformedURLException;
import java.net.URL;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 9/10/13
 * Time: 3:18 PM
 */
public final class LaunchPadClient
{
    /** Set up logging for the launch pad client. */
    private static final Logger LOG = Logger.getLogger(LaunchPadClient.class.getName());

    /** The instance of this singleton. */
    private static final LaunchPadClient INSTANCE = new LaunchPadClient();

    /** Error string. */
    private static final String ERROR_STR = "bad agent monitor URL: ";

    /** The actual XML-RPC client. */
    private XmlRpcClient client;

    /**
     * Private constructor to enforce the singleton design of this class.
     */
    private LaunchPadClient()
    {
        try
        {
            XmlRpcClientConfigImpl config = new XmlRpcClientConfigImpl();
            config.setServerURL(new URL(AgentDispatcher.getAgentMonitorURL()));
            client = new XmlRpcClient();
            client.setConfig(config);
        }
        catch (MalformedURLException e)
        {
            String msg = ERROR_STR + e.getMessage();
            LOG.error(msg);
            client = null;
        }

    }

    /**
     * Get the single instance.
     *
     * @return  The launch pad client object.
     */
    public static LaunchPadClient getInstance()
    {
        return INSTANCE;
    }

    /**
     * Get the XML-RPC client.
     *
     * @return  The XML-RPC client.
     */
    public XmlRpcClient getClient()
    {
        return client;
    }
}
