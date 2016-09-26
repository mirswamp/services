// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2016 Software Assurance Marketplace

package org.cosalab.swamp.collector;

import org.apache.log4j.Logger;
import org.cosalab.swamp.util.CheckSumUtil;
import org.cosalab.swamp.util.StringUtil;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.sql.SQLException;
import java.util.HashMap;
import java.util.Map;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson@morgridgeinstitute.org
 * Date: 7/18/13
 * Time: 10:59 AM
 */
public class ResultsCollectorHandler extends BaseCollectorHandler implements ResultCollector
{
    /** Thread sleep between sonatype attempts. */
    private static final long SLEEP_INTERVAL = 1000;
    /** Maximum number of sonatype attempts. */
    private static final int MAX_INTERVAL_TIMEOUT = 60;

    /** Set up logging for this class. */
    private static final Logger LOG = Logger.getLogger(ResultsCollectorHandler.class.getName());

    /**
     * Constructor.
     */
    public ResultsCollectorHandler()
    {
        super();

        LOG.debug("*** The Results Collector is on the job ***");
    }

    /**
     * Main method for saving results to the database.
     *
     * @param args      Hash map with arguments for the database request.
     * @return          Hash map with results of the request.
     */
    @Override
    public HashMap<String, String> saveResult(HashMap<String, String> args)
    {
        LOG.info("saveResult called");
        HashMap<String, String> results = new HashMap<String, String>();

        if (args == null)
        {
            handleError(results, "null argument", LOG);
            return results;
        }

        for (Map.Entry<String, String> entry : args.entrySet())
        {
            LOG.debug("\tKey = " + entry.getKey() + ", Value = " + entry.getValue());
        }

        // do usual workflow here - store the results someplace and tell the database

        String execrunID = args.get("execrunid");
        if (execrunID == null || execrunID.isEmpty())
        {
            results.put(ERROR_KEY, "bad assessment run ID");
            return results;
        }

        // we have a valid exec run ID, so we can set the ID label.
        setIDLabel(StringUtil.createLogExecIDString(execrunID));

        String pathname = args.get("pathname");
        String checkSum = args.get("sha512sum");
        String sourcePath = args.get("sourcepathname");
        String sourceChecksum = args.get("source512sum");
        String logPath = args.get("logpathname");
        String logChecksum = args.get("log512sum");
        String weakness = args.get("weaknesses");

        int weaknessCount = handleWeaknessCount(weakness);
        String gav = args.get("gav");               // this wil be null for non-Sonatype jobs

        // this method call stores the results in the database
        insertResultsIntoDB(results, execrunID, pathname, checkSum, sourcePath, sourceChecksum,
                            logPath, logChecksum, weaknessCount);

        // check for a Sonatype job
        if (gav != null)
        {
            // this must be a sonatype job
            if (gav.isEmpty())
            {
                handleError(results, "Sonatype job: invalid GAV", LOG);
            }
            else if (pathname == null || pathname.isEmpty())
            {
                handleError(results, "Sonatype job: bad results file pathname", LOG);
            }
            else
            {
                // get the results as a string

                String rawReport;
                try
                {
                    rawReport = getSonatypeResults(pathname, checkSum);
                }
                catch (IOException e)
                {
                    String msg = "Sonatype: results file: " + pathname + ": " + e.getMessage();
                    handleError(results, msg, LOG);
                    return results;
                }

                // use the azolla client to send the report to azolla
                AzollaClient azollaClient = AzollaClient.getInstance();

                // format the results as a JSON string
                String token = azollaClient.formatSingleReportToken(gav, rawReport);
                String report = azollaClient.formatCompleteReport1(token);

                LOG.debug("Sonatype JSON for azolla: " + report + idLabel);
                if (!azollaClient.sendReport(results, gav, report))
                {
                    // something bad happened and we were unable to send the report
                    LOG.warn("problem sending report to azolla for GAV: " + gav);
                }
            }
        }   // end of special sonatype case

        return results;
    }

    /**
     * Convert the string representation of the number of weaknesses to an integer.
     *
     * @param weaknessCount     number of weaknesses in SWAMP string format
     * @return                  integer number of weaknesses. could be -1 if the input string
     *                          is bad, could be zero if there is a parsing error.
     */
    int handleWeaknessCount(String weaknessCount)
    {
        int result;
        if (weaknessCount == null || weaknessCount.isEmpty()
                || weaknessCount.compareToIgnoreCase("undefined") == 0)
        {
            result = -1;
            LOG.warn("weakness count string is null or empty; setting count to -1" + idLabel);
        }
        else
        {
            result = StringUtil.decodeIntegerFromString(weaknessCount);
        }

        return result;

    }

    /**
     * Get the results for a sonatype run as a string suitable for sending to azolla.
     *
     * @param pathname      The path of the results.
     * @param checkSum      The results checksum.
     * @return              The azolla-ready results string.
     * @throws IOException
     */
    private String getSonatypeResults(String pathname, String checkSum) throws IOException
    {
        LOG.info("call to getSonatypeResults() with: " + pathname + idLabel);

        File file = new File(pathname);
        boolean ready = file.canRead();
        int count = 0;

        while (!ready && count < MAX_INTERVAL_TIMEOUT)
        {
            try
            {
                Thread.sleep(SLEEP_INTERVAL);
            }
            catch (InterruptedException e)
            {
                LOG.debug("interrupted sleep exception" + idLabel);
            }
            file = new File(pathname);
            ready = file.canRead();
            count++;
        }

        LOG.debug("sleep interval count = " + count + "\tfile readable? " + ready + idLabel);

        // the file should exist at this point, otherwise we will throw an exception
        // during the check sum calculation, or when we try to open it to read the contents

        // check the checksum if it exists
        if (checkSum != null && !checkSum.isEmpty() && checkSum.compareToIgnoreCase("error") != 0)
        {
            String myCheck = CheckSumUtil.getFileCheckSumSHA512(pathname);
            if (checkSum.compareToIgnoreCase(myCheck) != 0)
            {
                String msg = "check sum error with results file";
                LOG.error(msg + idLabel);
                throw new IOException(msg);
            }
        }
        else
        {
            String msg = "check sum not checked for file: " + pathname;
            LOG.warn(msg + idLabel);
        }

        // now read the file and return the contents as a string
        BufferedReader reader = null;
        StringBuilder builder = new StringBuilder();
        FileInputStream fstream = null;

        try
        {
            fstream = new FileInputStream(pathname);
            reader = new BufferedReader(new InputStreamReader(fstream, "UTF-8"));
            boolean firstLine = true;
            String sCurrentLine;

            while ((sCurrentLine = reader.readLine()) != null)
            {
                LOG.debug(sCurrentLine);
                if (firstLine)
                {
                    firstLine = false;
                }
                else
                {
                    builder.append("\\n");  // need this to fake out azolla, it needs to see a "\n" after each line
                }
                builder.append(sCurrentLine);
            }
        }
        catch (IOException e)
        {
            LOG.warn("problem reading results file: " + e.getMessage() + idLabel);
            throw e;
        }
        finally
        {
            if (reader != null)
            {
                try
                {
                    reader.close();
                }
                catch (IOException e)
                {
                    LOG.warn("problem closing reader: " + e.getMessage() + idLabel);
                }

            }
            if (fstream != null)
            {
                try
                {
                    fstream.close();
                }
                catch (IOException e)
                {
                    LOG.warn("problem closing file: " + e.getMessage() + idLabel);
                }
            }
        }

        if (builder.length() == 0)
        {
            LOG.warn("results file content has zero length" + idLabel);
        }

        return builder.toString();
    }

    /**
     * Simple test for the assessment run database.
     *
     * @param args      Hash map with the test arguments.
     * @return          Test results hash map.
     */
    public HashMap<String, String> testResultsDB(HashMap<String, String> args)
    {
        LOG.info("request to testResultsDB");
        HashMap<String, String> results = new HashMap<String, String>();

        if (args == null)
        {
            results.put(ERROR_KEY, "null argument");
            return results;
        }

        for (Map.Entry<String, String> entry : args.entrySet())
        {
            LOG.info("\tKey = " + entry.getKey() + ", Value = " + entry.getValue());
        }

        String execrunID = args.get("execrunid");
        if (execrunID == null || execrunID.isEmpty())
        {
            results.put(ERROR_KEY, "bad assessment run ID");
            return results;
        }

        String resultPath = args.get("pathname");
        String resultChecksum = args.get("sha512sum");
        String sourcePath = args.get("sourcepathname");
        String sourceChecksum = args.get("source512sum");
        String logPath = args.get("logpathname");
        String logChecksum = args.get("log512sum");
        insertResultsIntoDB(results, execrunID, resultPath, resultChecksum, sourcePath,
                            sourceChecksum, logPath, logChecksum, 0);
        return results;
    }

    /**
     * Make the database connection and store the results in the database.
     *
     * @param results           The results hash map: not stored in the database.
     * @param execrunID         The execution run uuid.
     * @param resultPath        The path to the results.
     * @param resultChecksum    The results checksum
     * @param sourcePath        The source path.
     * @param sourceChecksum    The source checksum.
     * @param logPath           The path to the log files.
     * @param logChecksum       The log checksum.
     * @param weaknessCount     The number of weaknesses found in the assessment run
     *
     */
    private void insertResultsIntoDB(HashMap<String, String> results, String execrunID,
                                     String resultPath, String resultChecksum, String sourcePath, String sourceChecksum,
                                     String logPath, String logChecksum, int weaknessCount)
    {
        // let's set up the data base connections
        if(!initConnections(runDBTest))
        {
            results.put(ERROR_KEY, "problem initializing database connections");
            cleanup();
            return;
        }

        try
        {
            boolean success = assessmentDB.insertResults(execrunID, resultPath, resultChecksum, sourcePath,
                                                         sourceChecksum, logPath, logChecksum, weaknessCount);
            if (!success)
            {
                results.put(ERROR_KEY, "insertResults failed on assessment DB");
            }
        }
        catch (SQLException e)
        {
            String msg = "error inserting results: " + e.getMessage();
            handleError(results, msg, LOG);
        }

        cleanup();
    }
}
