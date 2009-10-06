/*
 * charprop.c - character property handling.
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

extern mapent_t linebreak_map[];
extern const unsigned short linebreak_hash[];
extern const unsigned short linebreak_index[];
extern size_t linebreak_hashsiz;

#define HASH_MODULUS (1U << 13)

/*
 * linebreak_charprop (obj, c, *lbcptr, *eawptr, *gbcptr, *scrptr)
 * Examine hash table search.
 */
static mapent_t
PROPENT_HAN =        {0, 0, LB_ID, EA_W, GB_Other, SC_Han},
PROPENT_HANGUL_LV =  {0, 0, LB_H2, EA_W, GB_LV, SC_Hangul},
PROPENT_HANGUL_LVT = {0, 0, LB_H3, EA_W, GB_LVT, SC_Hangul},
PROPENT_PRIVATE =    {0, 0, LB_AL, EA_A, GB_Other, SC_Unknown}, /* XX */
PROPENT_UNKNOWN =    {0, 0, LB_AL, EA_N, GB_Other, SC_Unknown}; /* XX/SG */

void linebreak_charprop(linebreak_t *obj, unichar_t c,
			propval_t *lbcptr, propval_t *eawptr,
			propval_t *gbcptr, propval_t *scrptr)
{
    size_t key, idx, end;
    mapent_t *top, *bot, *cur, *ent;
    propval_t lbc = PROP_UNKNOWN, eaw = PROP_UNKNOWN, gbc = PROP_UNKNOWN,
	scr = PROP_UNKNOWN;

    /* First, search custom map. */
    if (obj->map && obj->mapsiz) {
	top = obj->map;
	bot = obj->map + obj->mapsiz - 1;
	while (top <= bot) {
	    cur = top + (bot - top) / 2;
	    if (c < cur->beg)
		bot = cur - 1;
	    else if (cur->end < c)
		top = cur + 1;
	    else {
		if (lbcptr) lbc = cur->lbc;
		if (eawptr) eaw = cur->eaw;
		if (gbcptr) gbc = cur->gbc;
		break;
	    }
	}
    }

    /* Otherwise, search built-in map. */
    if ((lbcptr && lbc == PROP_UNKNOWN) ||
	(eawptr && eaw == PROP_UNKNOWN) ||
	(gbcptr && gbc == PROP_UNKNOWN)) {
	ent = NULL;
	key = c % HASH_MODULUS;
	idx = linebreak_index[key];
	if (idx < linebreak_hashsiz) {
	    end = linebreak_index[key + 1];
	    for ( ; idx < end; idx++) {
		cur = linebreak_map + (size_t)(linebreak_hash[idx]);
		if (c < cur->beg)
		    break;
		else if (c <= cur->end) {
		    ent = cur;
		    break;
		}
	    }
	}
	if (ent == NULL) {
	    if ((0x3400 <= c && c <= 0x4DBF) ||
		(0x4E00 <= c && c <= 0x9FFF) ||
		(0xF900 <= c && c <= 0xFAFF) ||
		(0x20000 <= c && c <= 0x2FFFD) ||
		(0x30000 <= c && c <= 0x3FFFD)) {
		ent = &PROPENT_HAN;
	    } else if (0xAC00 <= c && c <= 0xD7A3) {
		if (c % 28 == 16)
		    ent = &PROPENT_HANGUL_LV;
		else
		    ent = &PROPENT_HANGUL_LVT;
	    } else if ((0xE000 <= c && c <= 0xF8FF) ||
		       (0xF0000 <= c && c <= 0xFFFFD) ||
		       (0x100000 <= c && c <= 0x10FFFD)) {
		ent = &PROPENT_PRIVATE;
	    }
	}
	if (ent == NULL)
	    ent = &PROPENT_UNKNOWN;

	if (lbcptr && lbc == PROP_UNKNOWN)
	    lbc = ent->lbc;
	if (eawptr && eaw == PROP_UNKNOWN)
	    eaw = ent->eaw;
	if (gbcptr && gbc == PROP_UNKNOWN)
	    gbc = ent->gbc;
	if (scrptr)
	    scr = ent->scr;
    }

    /* Resolve context-dependent property values. */
    if (lbcptr && lbc == LB_AI)
	lbc = (obj->options & LINEBREAK_OPTION_EASTASIAN_CONTEXT)?
	    LB_ID: LB_AL;
    if (eawptr && eaw == EA_A)
	eaw = (obj->options & LINEBREAK_OPTION_EASTASIAN_CONTEXT)?
	    EA_F: EA_N;

    if (lbcptr) *lbcptr = lbc;
    if (eawptr) *eawptr = eaw;
    if (gbcptr) *gbcptr = gbc;
    if (scrptr) *scrptr = scr;
}
