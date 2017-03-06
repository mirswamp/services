// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.quartermaster;

import java.util.HashMap;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 8/27/13
 * Time: 2:41 PM
 */
public interface Gator
{
    /**
     * Create a list of the available tools.
     *
     * @return      Hash map with the tool list.
     */
    HashMap<String, String> listTools();

    /**
     * Create a list of packages.
     *
     * @return  Hash map with the package list.
     */
    HashMap<String, String> listPackages();

    /**
     * Create a list of platforms.
     *
     * @return  Hash map with the platform list.
     */
    HashMap<String, String> listPlatforms();

}
