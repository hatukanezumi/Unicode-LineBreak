/*
 * linebreak.c - implementation of Linebreak object.
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

extern propval_t *linebreak_rules[];
extern size_t linebreak_rulessiz;
extern void linebreak_charprop(linebreak_t *, unichar_t,
                               propval_t *, propval_t *, propval_t *,
                               propval_t *);

static const linebreak_t initlbobj = {
    1UL,			/* refcount */
    LINEBREAK_STATE_NONE,	/* state */
    {(unichar_t *)NULL, 0},	/* bufstr */
    {(unichar_t *)NULL, 0},	/* bufspc */
    0.0,			/* bufcols */
    {(unichar_t *)NULL, 0},	/* unread */
    0,				/* charmax */
    998.0,			/* colmax */
    0.0,			/* colmin */
    (mapent_t *)NULL,		/* map */
    0,				/* mapsiz */
    {(unichar_t *)NULL, 0},	/* newline */
    0,				/* options */
    NULL,			/* format_data */
    NULL,			/* sizing_data */
    NULL,			/* urgent_data */
    NULL,			/* user_data */
    NULL,			/* stash */
    (gcstring_t *(*)())NULL,	/* format_func */
    (double (*)())NULL,		/* sizing_func */
    (gcstring_t *(*)())NULL,	/* urgent_func */
    (gcstring_t *(*)())NULL,	/* user_func */
    (void (*)())NULL		/* ref_func */
};

linebreak_t *linebreak_new()
{
    linebreak_t *obj;
    if ((obj = malloc(sizeof(linebreak_t)))== NULL)
	return NULL;
    memcpy(obj, &initlbobj, sizeof(linebreak_t));
    obj->refcount = 1UL;
    return obj;
}

linebreak_t *linebreak_incref(linebreak_t *obj)
{
    obj->refcount += 1UL;
    return obj;
}

linebreak_t *linebreak_copy(linebreak_t *obj)
{
    linebreak_t *newobj;
    mapent_t *newmap;
    unichar_t *newstr;

    if ((newobj = malloc(sizeof(linebreak_t)))== NULL)
	return NULL;
    memcpy(newobj, obj, sizeof(linebreak_t));

    if (obj->map && obj->mapsiz) {
	if ((newmap = malloc(sizeof(mapent_t) * obj->mapsiz))== NULL) {
	    free(newobj);
	    return NULL;
	}
	memcpy(newmap, obj->map, sizeof(mapent_t) * obj->mapsiz);
	newobj->map = newmap;
    }
    else
	newobj->map = NULL;
    if (obj->newline.str && obj->newline.len) {
	if ((newstr = malloc(sizeof(unichar_t) * obj->newline.len)) == NULL) {
	    if (newobj->map) free(newobj->map);
	    free(newobj);
	    return NULL;
	}
	memcpy(newstr, obj->newline.str, sizeof(unichar_t) * obj->newline.len);
	newobj->newline.str = newstr;
    }
    else
	newobj->newline.str = NULL;
    if (obj->bufstr.str && obj->bufstr.len) {
	if ((newstr = malloc(sizeof(unichar_t) * obj->bufstr.len)) == NULL) {
	    if (newobj->map) free(newobj->map);
	    if (newobj->newline.str) free(newobj->newline.str);
	    free(newobj);
	    return NULL;
	}
	memcpy(newstr, obj->bufstr.str, sizeof(unichar_t) * obj->bufstr.len);
	newobj->bufstr.str = newstr;
    }
    else
	newobj->bufstr.str = NULL;
    if (obj->bufspc.str && obj->bufspc.len) {
	if ((newstr = malloc(sizeof(unichar_t) * obj->bufspc.len)) == NULL) {
	    if (newobj->map) free(newobj->map);
	    if (newobj->newline.str) free(newobj->newline.str);
	    if (newobj->bufstr.str) free(newobj->bufstr.str);
	    free(newobj);
	    return NULL;
	}
	memcpy(newstr, obj->bufspc.str, sizeof(unichar_t) * obj->bufspc.len);
	newobj->bufspc.str = newstr;
    }
    else
	newobj->bufspc.str = NULL;
    if (obj->unread.str && obj->unread.len) {
	if ((newstr = malloc(sizeof(unichar_t) * obj->unread.len)) == NULL) {
	    if (newobj->map) free(newobj->map);
	    if (newobj->newline.str) free(newobj->newline.str);
	    if (newobj->bufstr.str) free(newobj->bufstr.str);
	    if (newobj->bufspc.str) free(newobj->bufspc.str);
	    free(newobj);
	    return NULL;
	}
	memcpy(newstr, obj->unread.str, sizeof(unichar_t) * obj->unread.len);
	newobj->unread.str = newstr;
    }
    else
	newobj->unread.str = NULL;

    if (newobj->ref_func) {
	if (newobj->stash)
	    (*newobj->ref_func)(newobj->stash, LINEBREAK_REF_STASH, +1);
	if (newobj->format_data)
	    (*newobj->ref_func)(newobj->format_data, LINEBREAK_REF_FORMAT, +1);
	if (newobj->sizing_data)
	    (*newobj->ref_func)(newobj->sizing_data, LINEBREAK_REF_SIZING, +1);
	if (newobj->urgent_data)
	    (*newobj->ref_func)(newobj->urgent_data, LINEBREAK_REF_URGENT, +1);
	if (newobj->user_data)
	    (*newobj->ref_func)(newobj->user_data, LINEBREAK_REF_USER, +1);
    }
    newobj->refcount = 1UL;
    return newobj;
}

void linebreak_destroy(linebreak_t *obj)
{
    if (obj == NULL)
	return;
    if ((obj->refcount -= 1UL))
	return;
    if (obj->map) free(obj->map);
    if (obj->newline.str) free(obj->newline.str);
    if (obj->bufstr.str) free(obj->bufstr.str);
    if (obj->unread.str) free(obj->unread.str);
    if (obj->ref_func) {
	if (obj->stash)
	    (*obj->ref_func)(obj->stash, LINEBREAK_REF_STASH, -1);
	if (obj->format_data)
	    (*obj->ref_func)(obj->format_data, LINEBREAK_REF_FORMAT, -1);
	if (obj->sizing_data)
	    (*obj->ref_func)(obj->sizing_data, LINEBREAK_REF_SIZING, -1);
	if (obj->urgent_data)
	    (*obj->ref_func)(obj->urgent_data, LINEBREAK_REF_URGENT, -1);
	if (obj->user_data)
	    (*obj->ref_func)(obj->user_data, LINEBREAK_REF_USER, -1);
    }
    free(obj);
}

void linebreak_reset(linebreak_t *lbobj)
{
    if (lbobj == NULL)
	return;
    if (lbobj->unread.str) {
	free(lbobj->unread.str);
	lbobj->unread.str = NULL;
	lbobj->unread.len = 0;
    }
    if (lbobj->bufstr.str) {
	free(lbobj->bufstr.str);
	lbobj->bufstr.str = NULL;
	lbobj->bufstr.len = 0;
    }
    if (lbobj->bufspc.str) {
	free(lbobj->bufspc.str);
	lbobj->bufspc.str = NULL;
	lbobj->bufspc.len = 0;
    }
    lbobj->bufcols = 0.0;
    lbobj->state = LINEBREAK_STATE_NONE;
}

propval_t linebreak_lbrule(propval_t b_idx, propval_t a_idx)
{
    propval_t result = PROP_UNKNOWN;

    if (b_idx < 0 || linebreak_rulessiz <= b_idx ||
	a_idx < 0 || linebreak_rulessiz <= a_idx)
	;
    else
	result = linebreak_rules[b_idx][a_idx];
    if (result == PROP_UNKNOWN)
	return DIRECT;
    return result;
}

propval_t linebreak_lbclass(linebreak_t *obj, unichar_t c)
{
    propval_t lbc, gbc, scr;

    linebreak_charprop(obj, c, &lbc, NULL, &gbc, &scr);
    if (lbc == LB_SA) {
#ifdef USE_LIBTHAI
	if (scr != SC_Thai)
#endif
	    lbc = (gbc == GB_Extend || gbc == GB_SpacingMark)? LB_CM: LB_AL;
    }
    return lbc;
}

propval_t linebreak_eawidth(linebreak_t *obj, unichar_t c)
{
    propval_t eaw;
    
    linebreak_charprop(obj, c, NULL, &eaw, NULL, NULL);
    return eaw;
}

double linebreak_strsize(linebreak_t *obj, double len, gcstring_t *pre,
			 gcstring_t *spc, gcstring_t *str, size_t max)
{
    gcstring_t *spcstr;
    size_t idx, pos;

    if (max < 0)
	max = 0;
    if ((!spc || !spc->str || !spc->len) && (!str || !str->str || !str->len))
	return max? 0: len;

    if (!spc || !spc->str)
	spcstr = gcstring_copy(str);
    else if ((spcstr = gcstring_concat(spc, str)) == NULL)
	return -1;
    if (!max) {
	len += gcstring_columns(spcstr);
	gcstring_destroy(spcstr);
	return len;
    }

    for (idx = 0, pos = 0; pos < spcstr->gclen; pos++) {
	gcchar_t *gc;
	size_t gcol;

	gc = spcstr->gcstr + pos;
	gcol = gc->col;

	if (max < len + gcol) {
	    if (!spc || !spc->str)
		;
	    else if (idx < spc->len)
		idx = 0;
	    else
		idx -= spc->len;
	    gcstring_destroy(spcstr);
	    return (double)idx;
	}
	idx += gc->len;
	len += gcol;
    }
    gcstring_destroy(spcstr);
    return (double)(str->len);
}
