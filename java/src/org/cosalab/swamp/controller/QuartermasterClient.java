// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2016 Software Assurance Marketplace

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
 * Date: 9/16/13
 * Time: 12:28 PM
 */
public final class QuartermasterClient
{
    /** Set up logging for the quartermaster client. */
    private static final Logger LOG = Logger.getLogger(QuartermasterClient.class.getName());

    /** The instance of this singleton. */
    private static final QuartermasterClient INSTANCE = new QuartermasterClient();

    /** Error string. */
    private static final String ERROR_STR = "bad quartermaster URL: ";

    /** The actual XML-RPC client. */
    private XmlRpcClient client;

    /**
     * Private constructor to enforce the singleton design of this class.
     */
    private QuartermasterClient()
    {
        try
        {
            XmlRpcClientConfigImpl config = new XmlRpcClientConfigImpl();
            config.setServerURL(new URL(AgentDispatcher.getQuartermasterURL()));
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
     * @return  The quartermaster client object.
     */
    public static QuartermasterClient getInstance()
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
