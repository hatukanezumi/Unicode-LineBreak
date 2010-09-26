/*
 * southeastasian.c - interfaces for South East Asian complex breaking.
 * 
 * Copyright (C) 2009 by Hatuka*nezumi - IKEDA Soji.  All rights reserved.
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

#include <assert.h>
#include "linebreak_defs.h"
#ifdef USE_LIBTHAI
#    include "thai/thwchar.h"
#    include "thai/thwbrk.h"
#endif /* USE_LIBTHAI */

/** Flag to determin whether South East Asian word segmentation is supported.
 */
const char *linebreak_southeastasian_supported =
#ifdef USE_LIBTHAI
    "Thai:" USE_LIBTHAI " "
#else /* USE_LIBTHAI */
    NULL
#endif /* USE_LIBTHAI */
    ;

void linebreak_southeastasian_flagbreak(gcstring_t *gcstr)
{
#ifdef USE_LIBTHAI
    wchar_t *buf;
    size_t i, j, k;
    int brk;

    if (gcstr == NULL || gcstr->gclen == 0)
	return;
    /* Copy string to temp buffer so that abuse of external module avoided. */
    if ((buf = malloc(sizeof(wchar_t) * (gcstr->len + 1))) == NULL)
	return;
    for (i = 0; i < gcstr->len; i++)
	buf[i] = gcstr->str[i];
    buf[i] = (wchar_t)0;
    k = i;

    /* Flag breaking points. */
    for (i = 0, j = 0; buf[j] && th_wbrk(buf + j, &brk, 1); j += brk) {
	/* check if external module is broken. */
	assert(0 <= brk);
	assert(brk != 0);
	assert(brk < k);

	for (; i < gcstr->gclen && gcstr->gcstr[i].idx <= j + brk; i++) {
	    /* check if external module break temp buffer. */
	    assert(buf[i] == gcstr->str[i]);

	    if (gcstr->gcstr[i].lbc == LB_SA && !gcstr->gcstr[i].flag)
		gcstr->gcstr[i].flag = 
		    (gcstr->gcstr[i].idx == j + brk)?
		    LINEBREAK_FLAG_BREAK_BEFORE:
		    LINEBREAK_FLAG_PROHIBIT_BEFORE;
	}
    }
    for (; i < gcstr->gclen && gcstr->gcstr[i].lbc == LB_SA; i++)
	if (!gcstr->gcstr[i].flag)
	    gcstr->gcstr[i].flag = LINEBREAK_FLAG_PROHIBIT_BEFORE;

    free(buf);
#endif /* USE_LIBTHAI */
}
