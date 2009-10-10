/*
 * Break.c - an implementation of Unicode line breaking algorithm.
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

#include "linebreak.h"

static
gcstring_t *_preprocess(linebreak_t *lbobj, gcstring_t *str)
{
    gcstring_t *result;

    if (str == NULL)
	return NULL;
    else if (lbobj->user_data == NULL || lbobj->user_func == NULL ||
	     (result = (*(lbobj->user_func))(lbobj, str)) == NULL)
	return gcstring_copy(str);
    else
	return result;
}

/* static */
gcstring_t *_format(linebreak_t *lbobj, linebreak_state_t action,
		    gcstring_t *str)
{
    gcstring_t *result;

    if (str == NULL)
	return NULL;
    else if (lbobj->format_data == NULL || lbobj->format_func == NULL ||
	     (result = (*(lbobj->format_func))(lbobj, action, str)) == NULL)
	return gcstring_copy(str);
    else
	return result;
}

/* static */
double _sizing(linebreak_t *lbobj, double len,
	       gcstring_t *pre, gcstring_t *spc, gcstring_t *str, size_t max)
{
    double ret;

    if (lbobj->sizing_data == NULL || lbobj->sizing_func == NULL ||
	(ret = (*(lbobj->sizing_func))(lbobj, len, pre, spc, str, max)) < 0.0)
	return linebreak_strsize(lbobj, len, pre, spc, str, max);
    return ret;
}

/* static */
gcstring_t *_urgent_break(linebreak_t *lbobj, double cols,
			  gcstring_t *pre, gcstring_t *spc, gcstring_t *str)
{
  gcstring_t *result;

    if (lbobj->urgent_data == NULL || lbobj->urgent_func == NULL ||
	(result = lbobj->urgent_func(lbobj, cols, pre, spc, str)) == NULL) {
	result = gcstring_copy(str);
    }
    return result;
}

gcstring_t *linebreak_break_partial(linebreak_t *lbobj, gcstring_t *input)
{
    int eot = (input == NULL);
    gcstring_t *str, *newstr;
    unistr_t unistr;
    size_t i;

    unistr.str = lbobj->unread;
    unistr.len = lbobj->unreadsiz;
    if ((str = gcstring_new(&unistr, lbobj)) == NULL)
	return NULL;
    lbobj->unread = NULL;
    lbobj->unreadsiz = 0;
    if (gcstring_append(str, input) == NULL)
	return NULL;
    /* perform user breaking */
    newstr = _preprocess(lbobj, str);
    gcstring_destroy(str);
    if ((str = newstr) == NULL)
	return NULL;
    /* Legacy-CM: Treat SP CM+ as if it were ID.  cf. [UAX #14] 9.1. */
    if (lbobj->options & LINEBREAK_OPTION_LEGACY_CM)
	for (i = 1; i < str->gclen; i++)
	    if (str->gcstr[i].lbc == LB_CM && str->gcstr[i - 1].lbc == LB_SP) {
		str->gcstr[i - 1].len += str->gcstr[i].len;
		str->gcstr[i - 1].lbc = LB_ID;
		if (str->gclen - i - 1)
		    memmove(str->gcstr + i, str->gcstr + i + 1,
			    sizeof(gcchar_t) * (str->gclen - i - 1));
		str->gclen--;
		i--;
	    }
    /* South East Asian complex breaking. */
    linebreak_southeastasian_flagbreak(str);

/*
 * *********************************************************************
 */

    return str;
}
