// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2016 Software Assurance Marketplace

package org.cosalab.swamp.quartermaster;

import java.util.HashMap;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 5/19/15
 * Time: 10:01 AM
 */
public interface ViewerOps
{
    /**
     * Store the viewer database.
     *
     * @param args      Hash map with arguments used to store the viewer database.
     * @return          Hash map with results of the operation.
     */
    HashMap<String, String> storeViewerDatabase(HashMap<String, String> args);

    /**
     * Update the viewer instance.
     *
     * @param args      Hash map with arguments used to update the viewer.
     * @return          Hash map with results of the operation.
     */
    HashMap<String, String> updateViewerInstance(HashMap<String, String> args);

}
