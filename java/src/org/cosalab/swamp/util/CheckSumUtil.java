// This file is subject to the terms and conditions defined in
// 'LICENSE.txt', which is part of this source code distribution.
//
// Copyright 2012-2016 Software Assurance Marketplace

package org.cosalab.swamp.util;

import com.google.common.hash.HashCode;
import com.google.common.hash.Hashing;
import com.google.common.io.Files;

import java.io.File;
import java.io.IOException;

/**
 * Created with IntelliJ IDEA.
 * User: jjohnson@morgridgeinstitute.org
 * Date: 7/18/13
 * Time: 10:23 AM
 */
public final class CheckSumUtil
{
    private CheckSumUtil()
    {
        // shouldn't need to create an object for this class
    }

    /**
     * Compute the SHA-512 checksum of a file.
     *
     * @param filename          The name of the file.
     * @return                  The checksum.
     * @throws IOException
     */
    public static String getFileCheckSumSHA512(final String filename) throws IOException
    {
        File file = new File(filename);
        HashCode hashCode = Files.hash(file, Hashing.sha512());
//        String sss = "SHA-512: " + hashCode.toString();
//        System.out.println(sss);
        return hashCode.toString();
    }

    /**
     * Compute the SHA-1 checksum of a file.
     *
     * @param filename          The name of the file.
     * @return                  The checksum.
     * @throws IOException
     */
    public static String getFileCheckSumSHA1(final String filename) throws IOException
    {
        File file = new File(filename);
        HashCode hashCode = Files.hash(file, Hashing.sha1());
//        String sss = "SHA-1: " + hashCode.toString();
//        System.out.println(sss);
        return hashCode.toString();
    }

    /**
     * Compute the MD5 checksum of a file.
     *
     * @param filename          The name of the file.
     * @return                  The checksum.
     * @throws IOException
     */
    public static String getFileCheckSumMD5(final String filename) throws IOException
    {
        File file = new File(filename);
        HashCode hashCode = Files.hash(file, Hashing.md5());
//        String sss = "MD5: " + hashCode.toString();
//        System.out.println(sss);
        return hashCode.toString();
    }
}
