// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.collector;

import java.util.HashMap;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson@morgridgeinstitute.org
 * Date: 7/25/13
 * Time: 10:16 AM
 */
public interface ExecCollector
{
    /**
     * Handle the request to update the execution results.
     *
     * @param args      Hash map with the execution results to be sent to the database.
     * @return          Hash map with the results of the request.
     */
    HashMap<String, String> updateExecutionResults(HashMap<String, String> args);

    /**
     * Handle the request to get a single execution record.
     *
     * @param args      Hash map with the arguments that need to be sent to the database.
     * @return          Hash map with the results of the request.
     */
    HashMap<String, String> getSingleExecutionRecord(HashMap<String, String> args);
}
