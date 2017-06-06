// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.util;

import org.apache.log4j.Logger;

import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Date;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 9/18/13
 * Time: 4:29 PM
 */
public class StringUtil
{
    /** Set up logging for this class. */
    private static final Logger LOG = Logger.getLogger(StringUtil.class.getName());

    /** Hash map key for error messages. */
    public static final String ERROR_KEY = "error";

    /** Input date format. */
    private static final String INPUT_DATE_PATTERN = "EEE MMM d HH:mm:ss yyyy";
    /** Output date format. */
    private static final String OUTPUT_DATE_PATTERN = "yyyy-MM-dd HH:mm:ss";

    /** Label for execution run UUID logging. */
    public static final String EXEC_RUN_ID_LABEL = "exec run ID: ";
    /** Label for viewer UUID logging. */
    public static final String VIEWER_ID_LABEL = "viewer ID: ";
    /** Label for viewer UUID logging. */
    public static final String STATUS_KEY_LABEL = "status key: ";
    /** Separator for logging labels. */
    public static final String LOG_LABEL_SEPARATOR = " | ";

    /**
     * Takes a string that encodes an integer by putting one or more underscores in front of the integer's digits
     * and returns the original integer.
     * @param string     the encoded string
     * @return the integer
     */
    public static int decodeIntegerFromString(String string)
    {
        if (string == null || string.isEmpty())
        {
            return 0;
        }

        String[] sArray = string.split("_");

        // check to see if the line actually split
        if (sArray.length <= 1)
        {
            // nope, the string probably was "i__" so just return 0
            LOG.warn("decodeIntegerFromString: bad input string = " + string);
            return 0;
        }

        // the integer string will be the last in the split array
        String sLast = sArray[sArray.length-1];
        if (sLast.isEmpty())
        {
            return 0;
        }

        // get the integer value
        int value;
        try
        {
            value = Integer.parseInt(sLast);
        }
        catch (NumberFormatException nfe)
        {
            LOG.warn("decodeIntegerFromString: " + nfe.getMessage());
            value = 0;
        }
        catch (NullPointerException npe)
        {
            LOG.warn("decodeIntegerFromString: " + npe.getMessage());
            value = 0;
        }

        return value;
    }

    /**
     * Decode a double value from a formatted string.
     *
     * @param string    The formatted string.
     * @return          The double value.
     */
    public static double decodeDoubleFromString(String string)
    {
        if (string == null || string.isEmpty())
        {
            return 0.0;
        }

        String[] sArray = string.split("_");

        // check to see if the line actually split
        if (sArray.length <= 1)
        {
            // nope, log a warning and return 0.0
            LOG.warn("decodeDoubleFromString: bad input string = " + string);
            return 0.0;
        }

        // the double string will be the last in the split array
        String sLast = sArray[sArray.length-1];
        if (sLast.isEmpty())
        {
            return 0.0;
        }

        // get the double value
        double value;
        try
        {
            value = Double.parseDouble(sLast);
        }
        catch (NumberFormatException nfe)
        {
            LOG.warn("decodeDoubleFromString: " + nfe.getMessage());
            value = 0.0;
        }
        catch (NullPointerException npe)
        {
            LOG.warn("decodeDoubleFromString: " + npe.getMessage());
            value = 0.0;
        }

        return value;

    }

    /**
     * Convert a date string between formats.
     *
     * @param yDate     The initial date string.
     * @return          The converted date string.
     * @throws ParseException
     */
    public static String convertDateString(String yDate) throws ParseException
    {
        if (yDate == null || yDate.isEmpty())
        {
            return yDate;
        }

        SimpleDateFormat sdf = new SimpleDateFormat(INPUT_DATE_PATTERN);

        Date date;
        String zDate;
        date = sdf.parse(yDate);
        sdf.applyPattern(OUTPUT_DATE_PATTERN);
        zDate = sdf.format(date);

        return zDate;
    }

    /**
     * Validate a string that is to be used in a hash map. If the string is empty or null
     * the string "null" is returned, otherwise the original string is returned.
     *
     * @param arg   The string to be validated.
     * @return      The validated string.
     */
    public static String validateStringArgument(String arg)
    {
        String result;
        if (arg == null || arg.isEmpty())
        {
            result = "null";
        }
        else
        {
            result = arg;
        }

        return result;
    }

    /**
     * Check the string argument for null. If the argument is null, return an
     * empty string; otherise resturn the string argument.
     *
     * @param arg   The string to be validated.
     * @return      The validated string.
     */
    public static String checkStringForNull(String arg)
    {
        String result;
        if (arg == null)
        {
            result = "";
        }
        else
        {
            result = arg;
        }

        return result;
    }

    /**
     * Checks a string to see if it is null or empty. If the argument is null the
     * string "null" is returned. If the argument is an empty string, the string
     * "empty" is returned. Otherwise the original stirng is returned.
     *
     * @param arg   The string to be checked.
     * @return      A string with the results of the check.
     */
    public static String checkStringArgument(String arg)
    {
        String result;
        if (arg == null)
        {
            result = "null";
        }
        else if (arg.isEmpty())
        {
            result = "empty";
        }
        else
        {
            result = arg;
        }

        return result;
    }

    public static String createLogIDString(String label, String id)
    {
        return LOG_LABEL_SEPARATOR + label + validateStringArgument(id);
    }

    /**
     * Create a string for logging the execution run UUID.
     *
     * @param id    The execution run UUID. This will be validated.
     * @return      The logging string.
     */
    public static String createLogExecIDString(String id)
    {
        return createLogIDString(EXEC_RUN_ID_LABEL, id);
    }

    /**
     * Create a string for logging the viewer UUID.
     *
     * @param id    The viewer UUID. This will be validated.
     * @return      The logging string.
     */
    public static String createLogViewerIDString(String id)
    {
        return createLogIDString(VIEWER_ID_LABEL, id);
    }

    /**
     * Create a string for logging the system status key.
     *
     * @param key   The system status key. This will be validated.
     * @return      The logging string.
     */
    public static String createLogStatusKeyString(String key)
    {
        return createLogIDString(STATUS_KEY_LABEL, key);
    }

    /**
     * Returns the version of the Java Runtime Environment as a string.
     *
     * @return  A string with the JRE version.
     */
    public static String getJavaVersion()
    {
        String javaVersion = Runtime.class.getPackage().getImplementationVersion();

        return validateStringArgument(javaVersion);
    }

    /**
     * Formats the error message for the case when a tool or package is rejected because the checksums don't match.
     *
     * @param header            String with the initial message, should specify whether it's a package or a tool.
     * @param path              The path to the tool or package.
     * @param dbChecksum        The checksum from the database.
     * @param calcChecksum      The checksum that was computed by the quartermaster.
     * @return                  The error message.
     */
    public static String formatChecksumErrorMsg(String header, String path, String dbChecksum, String calcChecksum)
    {
        StringBuilder buffer = new StringBuilder(header);
        buffer.append("\npath: ");
        buffer.append(path);
        buffer.append("\nchecksum (db): ");
        buffer.append(dbChecksum);
        buffer.append("\nchecksum (calc): ");
        buffer.append(calcChecksum);

        return buffer.toString();
    }

    /**
     * Constructor.
     */
    private StringUtil()
    {
        // nothing to do
    }
}
