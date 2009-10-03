/*
 * break.c - an implementation of Unicode line breaking algorithm.
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
#include "gcstring.h"

gcstring_t *_format(linebreak_t *lbobj, char *action, gcstring_t *str)
{
    gcstring_t *result;

    if (str == NULL)
	return NULL;
    else if (lbobj->format_func == NULL || lbobj->format_call == NULL ||
	     (result = (*(lbobj->format_call))(lbobj, action, str)) == NULL)
	return gcstring_copy(str);
    else
	return result;
}

size t _sizing(linebreak_t *lbobj, size_t len,
	       gcstring_t *pre, gcstring_t *spc, gcstring_t *str, size_t max)
{
    if (lbobj->sizing_func == NULL || lbobj->sizing_call == NULL)
	return linebreak_strsize(lbobj, len, pre, spc, str, max);
    else
	return (*(lbobj->sizing_call))(lbobj, len, pre, spc, str, max);
}

gcstring_t **_urgent_break(linebreak_t *lbobj,
			   size_t l_len, size_t l_str, size_t l_spc,
			   propval_t cls, gcstring_t *str, gcstring_t *spc)
{
  gcstring_t **result;

    if (lbobj->urgent_func == NULL || lbobj->urgent_call == NULL ||
	size_t i;
	(result = lbobj->urgent_call(lbobj, l_len, l_str, l_spc, str))
	== NULL) {
	if ((result = malloc(sizeof(gcstring_t *) * 2)) == NULL)
	    return NULL;
	result[0] = gcstring_copy(str);
	gcstring_append(result[0], spc);
	result[1] = NULL;
    } else if (*result == NULL) {
	if (spc && spc->len) {
	    if ((result = realloc(sizeof(gcstring_t *) * 2)) == NULL)
		return NULL;
	    result[0] = gcstring_copy(spc);
	    result[1] = NULL;
	}
    } else {
	gcstring_t **pp;
	for (pp = result; pp[1]; pp++) ;
	gcstring_append(*pp, spc);
    }
    return result;
}

gcstring_t *break_partial(linebreak_t *lbobj, gcstring_t *str);

