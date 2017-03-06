// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.controller;

import java.util.HashMap;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson@morgridgeinstitute.org
 * Date: 7/25/13
 * Time: 10:48 AM
 */
public interface RunController
{
    /**
     * Initiate an assessment run by assembling the required information and passing
     * it along to the launch pad.
     *
     * @param args  a HashMap that contains the required input information.
     * @return      a HashMap containing the status of the request. If an error is
     *              encountered, the "error" key should be used to return the error
     *              message.
     */
    HashMap<String, String> doRun(HashMap<String, String> args);
}
