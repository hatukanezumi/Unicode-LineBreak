/*
 * strerror.c - Fallback implementaion of strerror(3).
 *
 * Copyright (C) 2006 by Hatuka*nezumi - IKEDA Soji.
 *
 * This file is part of the Linebreak Package.  This program is free
 * software; you can redistribute it and/or modify it under the terms
 * of the GNU General Public License as published by the Free Software
 * Foundation; either version 2 of the License, or (at your option)
 * any later version.  This program is distributed in the hope that
 * it will be useful, but WITHOUT ANY WARRANTY; without even the
 * implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
 * PURPOSE.  See the COPYING file for more details.
 *
 * $id$
 */

#include <stdio.h>

extern int sys_nerr;
extern char *sys_errlist[];

char *strerror(int errnum)
{
  static char buf[26];
  if (errnum >= 0 && errnum < sys_nerr)
    return sys_errlist[errnum];
  else
    sprintf(buf, sizeof(buf), "Unknown error %d", errnum);
  return buf;
}
