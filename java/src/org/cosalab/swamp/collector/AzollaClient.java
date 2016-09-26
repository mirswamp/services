// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2016 Software Assurance Marketplace

package org.cosalab.swamp.collector;

import org.apache.log4j.Logger;
import org.cosalab.swamp.dispatcher.AgentDispatcher;
import org.cosalab.swamp.util.StringUtil;

import java.io.*;
import java.net.*;
import java.text.MessageFormat;
import java.util.HashMap;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 9/11/13
 * Time: 11:45 AM
 */
public final class AzollaClient
{
    /** Set up logging for the azolla client. */
    private static final Logger LOG = Logger.getLogger(AzollaClient.class.getName());
    /** String used in formatting. */
    private static final String SEPARATOR = " : ";
    /** The instance of this singleton class. */
    private static AzollaClient instance = null;
    /** Hash map error key. */
    private static final String ERROR_KEY = StringUtil.ERROR_KEY;

    /** The URL of the azolla web service. */
    private final String azollaURL;

    private AzollaClient()
    {
        azollaURL = AgentDispatcher.getAzollaURL();
    }

    /**
     * Get the singleton instance.
     *
     * @return      The single AzollaClient object.
     */
    public static synchronized AzollaClient getInstance()
    {
        if (instance == null)
        {
            instance = new AzollaClient();
        }
        return instance;
    }

    /**
     * Formats a single report token.
     *
     * @param gavString         String with the package GAV.
     * @param reportString      String with the report information for the package.
     * @return                  Formatted string.
     */
    public String formatSingleReportToken(String gavString, String reportString)
    {
        return MessageFormat.format("'{' \"gav\": \"{0}\", \"report\": \"{1}\" '}'", gavString, reportString);

    }

    /**
     * Formats the complete report.
     *
     * @param report    String containing the report information.
     * @return          The formatted report string.
     */
    public String formatCompleteReport1(String report)
    {
        return MessageFormat.format("'{' \"report\": [ {0} ] '}'", report);
    }

    /**
     * Send the report to the azolla service.
     *
     * @param results       The results hash map.
     * @param gav           The package identifying GAV.
     * @param report        The formatted report.
     * @return              true if the report was sent successfully; false otherwise.
     */
    public boolean sendReport(HashMap<String, String> results, String gav, String report)
    {
        boolean success = false;

        try
        {
            String data = URLEncoder.encode(report, "UTF-8");

            // send to azolla
            String urlString = azollaURL + "?metadata=" + data;

            URL url = new URL(urlString);
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setDoOutput(true);
            conn.setRequestMethod("POST");
            conn.setRequestProperty("Content-Type", "application/json");

            OutputStream stream = conn.getOutputStream();
            Writer writer = new OutputStreamWriter(stream, "UTF-8");

            writer.write("metadata=");
            writer.write(data);

            writer.close();
            stream.close();

            int responseCode = conn.getResponseCode();
            LOG.debug("server response: " + responseCode);

            if (responseCode != HttpURLConnection.HTTP_OK)
            {
                String msg = "Azolla failed: GAV: " + gav + " HTTP error code : " + conn.getResponseCode();
                LOG.error(msg);
                results.put(ERROR_KEY, msg);
            }
            else
            {

                // do we care what azolla returns? no, i didn't think so.
            /*
            BufferedReader br = new BufferedReader(new InputStreamReader(conn.getInputStream()));

            String output;
            LOG.info("Output from Server ....");
            while ((output = br.readLine()) != null)
            {
                LOG.info(output);
            }
            LOG.info(" .... done");
             */

                // close the connection
                LOG.info("sent report for " + gav + ". closing connection to azolla");
                success = true;
            }
            // make sure we disconnect
            conn.disconnect();
        }
        catch (MalformedURLException e)
        {
            String msg = "URL exception for " + gav + SEPARATOR + e.getMessage();
            LOG.error(msg);
            results.put(ERROR_KEY, msg);
        }
        catch (ProtocolException e)
        {
            String msg = "protocol exception for " + gav + SEPARATOR + e.getMessage();
            LOG.error(msg);
            results.put(ERROR_KEY, msg);
        }
        catch (UnsupportedEncodingException e)
        {
            String msg = "UTF-8 encoding exception for " + gav + SEPARATOR + e.getMessage();
            LOG.error(msg);
            results.put(ERROR_KEY, msg);
        }
        catch (IOException e)
        {
            String msg = "IO exception for " + gav + SEPARATOR + e.getMessage();
            LOG.error(msg);
            results.put(ERROR_KEY, msg);
        }
        return success;
    }

}
