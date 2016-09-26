// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2016 Software Assurance Marketplace

package org.cosalab.swamp.quartermaster;

import java.util.HashMap;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson@morgridgeinstitute.org
 * Date: 7/23/13
 * Time: 9:41 AM
 */
public interface Quartermaster
{
    /**
     * Get the bill of goods.
     *
     * @param args      Hash map with arguments used to create a bill of goods.
     * @return          Hash map with results of the operation.
     */
    HashMap<String, String> getBillOfGoods(HashMap<String, String> args);

}
