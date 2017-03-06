// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2017 Software Assurance Marketplace

package org.cosalab.swamp.util;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson
 * Date: 11/15/13
 * Time: 10:33 AM
 */

/**
 * When we have a bad tool or bad package returned from the data base, this is the exception
 * that should be thrown.
*/
public class InvalidDBObjectException extends Exception
{
    /**
     * Create a new object with a string message.
     *
     * @param message   The message.
     */
    public InvalidDBObjectException(String message)
    {
        super(message);
    }

    /**
     * Create a new object from a message and another throwable object.
     *
     * @param message       The message.
     * @param throwable     The throwable object.
     */
    public InvalidDBObjectException(String message, Throwable throwable)
    {
        super(message, throwable);
    }

    /**
     * Create a new object from another throwable object.
     *
     * @param throwable     The throwable object.
     */
    public InvalidDBObjectException(Throwable throwable)
    {
        super(throwable);
    }

}
