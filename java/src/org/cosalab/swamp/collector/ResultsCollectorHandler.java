// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.collector;

import org.apache.log4j.Logger;
import org.cosalab.swamp.util.StringUtil;

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
        LOG.info("request to saveResult");
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

        // this method call stores the results in the database
        insertResultsIntoDB(results, execrunID, pathname, checkSum, sourcePath, sourceChecksum,
                            logPath, logChecksum, weaknessCount);

        return results;
    }

    /**
     * Convert the string representation of the number of weaknesses to an integer.
     *
     * @param weaknessCount     number of weaknesses in SWAMP string format
     * @return                  integer number of weaknesses. could be -1 if the input string
     *                          is bad, could be zero if there is a parsing error.
     */
    protected int handleWeaknessCount(String weaknessCount)
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
