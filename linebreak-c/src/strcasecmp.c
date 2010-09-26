/*
 * strcasecmp.c - Fallback implementaion of strcasecmp(3).
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

#define TOUPPER(c) \
    (('a' <= c && c <= 'z')? c - ('a' - 'A'): c)

int strcasecmp(const char *s1, const char *s2)
{
    size_t i;
    char c1, c2;

    if (s1 == NULL || s2 == NULL)
	return ((s1 != NULL)? 1: 0) - ((s2 != NULL)? 1: 0);
    for (i = 0; (c1 = TOUPPER(s1[i])) && (c2 = TOUPPER(s2[i])); i++)
        if (c1 != c2)
            return c1 - c2;
    return c1 - c2;    
}
