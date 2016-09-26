// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2016 Software Assurance Marketplace

package org.cosalab.swamp.quartermaster;

import java.util.HashMap;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 5/2/14
 * Time: 1:42 PM
 */
public interface Admin
{
    /**
     * Insert an execution event into the database.
     *
     * @param args      Hash map with the information to be sent to the data base.
     * @return          A hash map with the results of the insertion request.
     */
    HashMap<String, String> insertExecutionEvent(HashMap<String, String> args);

    /**
     * Insert a system status event into the database.
     *
     * @param args  Hash map with the information to be sent to the data base.
     * @return      A hash map with the results of the insertion request.
     */
    HashMap<String, String> insertSystemStatus(HashMap<String, String> args);
}
