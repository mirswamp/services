// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2016 Software Assurance Marketplace

package org.cosalab.swamp.collector;

import java.util.HashMap;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson@morgridgeinstitute.org
 * Date: 7/25/13
 * Time: 9:33 AM
 */
public interface ResultCollector
{
    /**
     * Save results to the database.
     *
     * @param args      Hash map with arguments for the database request.
     * @return          Hash map with the results for the request.
     */
    HashMap<String, String> saveResult(HashMap<String, String> args);
}
