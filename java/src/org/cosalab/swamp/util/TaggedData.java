// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.util;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 8/30/13
 * Time: 8:40 AM
 */
public interface TaggedData
{
    /**
     * Set the data tag.
     *
     * @param tag   The data tag.
     */
    public void setTag(String tag);

    /**
     * Get the data tag.
     *
     * @return  The data tag.
     */
    public String getTag();
}
