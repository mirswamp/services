// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.util;

import org.apache.log4j.Logger;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Properties;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson@morgridgeinstitute.org
 * Date: 7/24/13
 * Time: 12:35 PM
 */
public final class ConfigFileUtil
{
    /** system swamp configuration property (may not be set). */
    public static final String SWAMP_CONFIG_PROPERTY = "swamp.config";
    /** default swamp configuration file name. */
    public static final String SWAMP_CONFIG_DEFAULT_FILE = "swamp.conf";

    /** set up logger. */
    private static final Logger LOG = Logger.getLogger(ConfigFileUtil.class.getName());

    /** URL assembly parameter - prefix. */
    private static final String URL_PREFIX = "http://";
    /** URL assembly parameter - postfix. */
    private static final String URL_POSTFIX = "/";
    /** URL assembly parameters - port separator. */
    private static final String URL_PORT_SEP = ":";

    // no need to ever create an object of this class.
    private ConfigFileUtil()
    {
    }

    /**
     * Read a properties file from the file system.
     *
     * @param filename  The name of the file.
     * @return          The properties object.
     */
    public static Properties readFileFromFileSystem(String filename)
    {
        Properties prop = new Properties();
        FileInputStream fis = null;

        try
        {
            // load a properties file from file system, inside static method
            fis = new FileInputStream(filename);
            prop.load(fis);
        }
        catch (FileNotFoundException ex)
        {
            LOG.error("error reading config file from file system " + filename);
            prop = null;
        }
        catch (IOException ex)
        {
            LOG.error("error reading config file from file system " + filename);
            prop = null;
        }
        finally
        {
            closeInputStream(fis);
        }

        return prop;
    }

    /**
     * Read a properties file from a file located in the class path.
     *
     * @param filename  The name of the file.
     * @return          The properties object.
     */
    public static Properties readFileFromClasspath(String filename)
    {
        Properties prop = new Properties();
        InputStream is = null;
        try
        {
            //load a properties file from class path, inside static method
            ClassLoader cl = ConfigFileUtil.class.getClassLoader();
            if (cl != null)
            {
                is = cl.getResourceAsStream(filename);        	
            }
            
            if (is == null)
            {
                prop = null;
            }
            else
            {
        	    prop.load(is);
            }
        }
        catch (IOException ex)
        {
            LOG.error("error reading config file from class path " + filename);
            prop = null;
        }
        finally
        {
            closeInputStream(is);
        }

        return prop;
    }

    /**
     * Utility method to close an input stream.
     *
     * @param is    The input stream to be closed.
     */
    private static void closeInputStream(InputStream is)
    {
        if (is != null)
        {
            try
            {
                is.close();
            }
            catch (IOException e)
            {
                LOG.error("problem closing input file: " + e.getMessage());
            }
        }
    }

    /**
     * Writes a properties object to a file.
     *
     * @param filename  The name of the file.
     * @param prop      The properties object
     */
    public static void writeFileToFileSystem(String filename, Properties prop)
    {
        OutputStream out = null;
        try
        {
            File file = new File(filename);
            out = new FileOutputStream(file);
            prop.store(out, "updated configuration file");
        }
        catch (FileNotFoundException e)
        {
            LOG.error("problem writing to config file " + filename + ": " + e.getMessage());
        }
        catch (IOException e)
        {
            LOG.error("problem writing to config file " + filename + ": " + e.getMessage());
        }
        finally
        {
            closeOutputStream(out);
        }

    }

    /**
     * Utility method to close an output stream with appropriate exception handling.
     *
     * @param os   The output stream to be closed.
     */
    private static void closeOutputStream(OutputStream os)
    {
        if (os != null)
        {
            try
            {
                os.close();
            }
            catch (IOException e)
            {
                LOG.error("problem closing output stream: " + e.getMessage());
            }
        }
    }

    /**
     * Read the Swamp configuration properties. First we'll check to see if the system
     * has the swamp configuration property set; if so we'll use that file name. Otherwise
     * we will look for a file in the class path with the provided file name.
     *
     * @param filename  The name of the properties file in the class path. This can be null if the
     *                  system has the config property set.
     * @return          The swamp configuration properties object.
     */
    public static Properties getSwampConfigProperties(String filename)
    {
        Properties configProp = null;
        String value = System.getProperty(SWAMP_CONFIG_PROPERTY);
        if (value != null)
        {
            // try to read from the file system
            configProp = ConfigFileUtil.readFileFromFileSystem(value);
        }

        if (value == null || configProp == null)
        {
            // we'll try to read it from the classpath
            configProp = readFileFromClasspath(filename);
        }

        return configProp;

    }

    /**
     * Return the agent dispatcher URL from the swamp config properties
     *
     * @param prop  The swamp config properties
     * @return  The URL as a String
     */
    public static String getDispatcherURL(Properties prop)
    {
        String host = prop.getProperty("dispatcherHost","");
        String port = getDispatcherPort(prop);

        return URL_PREFIX + host.trim() + URL_PORT_SEP + port + URL_POSTFIX;

    }

    /**
     * Return the agent dispatcher port number from the swamp config properties
     *
     * @param prop  The swamp config properties
     * @return  The port number as a String
     */
    public static String getDispatcherPort(Properties prop)
    {
        String port = prop.getProperty("dispatcherPort","");
        return port.trim();
    }

    /**
     * Assemble the assessment controller XML-RPC server URL from the swamp configuration
     * properties.
     *
     * @param prop The swamp configuration properties that were read in from the configuration file
     * @return the server URL as a String object
     */
//    public static String getAssessmentControllerURL(Properties prop)
//    {
//        String host = prop.getProperty("controllerHost","");
//        String port = getAssessmentControllerPort(prop);
//
//        return URL_PREFIX + host.trim() + URL_PORT_SEP + port + URL_POSTFIX;
//
//    }

    /**
     * Return the assessment controller XML-RPC server port number from the swamp config properties
     *
     * @param prop  The swamp config properties
     * @return  The port number as a String
     */

//    public static String getAssessmentControllerPort(Properties prop)
//    {
//        String port = prop.getProperty("controllerPort","");
//        return port.trim();
//    }

    /**
     * Assemble the assessment controller XML-RPC server URL from the swamp configuration
     * properties.
     *
     * @param prop The swamp configuration properties that were read in from the configuration file
     * @return the server URL as a String object
     */
    public static String getQuartermasterURL(Properties prop)
    {
        String host = prop.getProperty("quartermasterHost","");
        String port = getQuartermasterPort(prop);

        return URL_PREFIX + host.trim() + URL_PORT_SEP + port + URL_POSTFIX;

    }

    /**
     * Return the quartermaster server XML-RPC server port number from the swamp config properties
     *
     * @param prop  The swamp config properties
     * @return  The port number as a String
     */
    public static String getQuartermasterPort(Properties prop)
    {
        String port = prop.getProperty("quartermasterPort","");
        return port.trim();
    }

    /**
     * Assemble the agent monitor XML-RPC server URL from the swamp configuration
     * properties.
     *
     * @param prop The swamp configuration properties that were read in from the configuration file
     * @return the server URL as a String object
     */
    public static String getAgentMonitorURL(Properties prop)
    {
        String host = prop.getProperty("agentMonitorHost","");
        String port = getAgentMonitorPort(prop);

        return URL_PREFIX + host.trim() + URL_PORT_SEP + port + URL_POSTFIX;

    }

    /**
     * Return the agent monitor XML-RPC server port number from the swamp config properties
     *
     * @param prop  The swamp config properties
     * @return  The port number as a String
     */

    public static String getAgentMonitorPort(Properties prop)
    {
        String port = prop.getProperty("agentMonitorPort","");
        return port.trim();
    }

    /**
     * Return the string corresponding to a method from the swamp config properties
     *
     * @param method    The method name as a String
     * @param prop      The swamp config properties
     * @return          The method string
     */
    public static String getMethodString(String method, Properties prop)
    {
        String methodName = prop.getProperty(method,"");
        return methodName.trim();
    }

    /**
     * Return the results folder name from the swamp config properties
     *
     * @param prop  The swamp config properties
     * @return  The name of the results folder as a String
     */
    public static String getResultsFolder(Properties prop)
    {
        String dir = prop.getProperty("resultsFolder", "");
        return dir.trim();
    }

}
