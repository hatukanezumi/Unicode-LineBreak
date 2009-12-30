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

extern const unsigned short linebreak_prop_index[];
extern const propval_t linebreak_prop_array[];

#define BLKLEN (5)

static propval_t
PROPENT_HAN[] =        {LB_ID, EA_W, GB_Other, SC_Han},
PROPENT_TAG[] =        {LB_CM, EA_Z, GB_Control, SC_Common},
PROPENT_VSEL[] =       {LB_CM, EA_Z, GB_Extend, SC_Inherited},
PROPENT_PRIVATE[] =    {LB_AL, EA_A, GB_Other, SC_Unknown}, /* XX */
PROPENT_UNKNOWN[] =    {LB_AL, EA_N, GB_Other, SC_Unknown}; /* XX/SG */

/** Search for character properties.
 * 
 * Configuration parameters of linebreak object:
 *
 * * map, mapsiz: custom property map overriding built-in map.
 *
 * * options: if LINEBREAK_OPTION_EASTASIAN_CONTEXT bit is set,
 *   LB_AI and EA_A are resolved to LB_ID and EA_F. Otherwise, LB_AL and EA_N,
 *   respectively.
 *
 * @param[in] obj linebreak object.
 * @param[in] c Unicode character.
 * @param[out] lbcptr UAX #14 line breaking class.
 * @param[out] eawptr UAX #11 East_Asian_Width property value.
 * @param[out] gbcptr UAX #29 Grapheme_Cluster_Break property value.
 * @param[out] scrptr Script (limited to several scripts).
 * @return none.
 */
void linebreak_charprop(linebreak_t *obj, unichar_t c,
			propval_t *lbcptr, propval_t *eawptr,
			propval_t *gbcptr, propval_t *scrptr)
{
    mapent_t *top, *bot, *cur;
    propval_t lbc = PROP_UNKNOWN, eaw = PROP_UNKNOWN, gbc = PROP_UNKNOWN,
	scr = PROP_UNKNOWN, *ent;

    /* First, search custom map using binary search. */
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
		lbc = cur->lbc;
		eaw = cur->eaw;
		gbc = cur->gbc;
		/* Complement unknown Grapheme_Cluster_Break property. */
		if (lbc != PROP_UNKNOWN && gbc == PROP_UNKNOWN) {
		    switch (lbc) {
		    case LB_CR:
			gbc = GB_CR;
			break;
		    case LB_LF:
			gbc = GB_LF;
			break;
		    case LB_BK: case LB_NL: case LB_WJ: case LB_ZW:
			gbc = GB_Control;
			break;
		    case LB_CM:
			gbc = GB_Extend;
			break;
		    case LB_H2:
			gbc = GB_LV;
			break;
		    case LB_H3:
			gbc = GB_LVT;
			break;
		    case LB_JL:
			gbc = GB_L;
			break;
		    case LB_JV:
			gbc = GB_V;
			break;
		    case LB_JT:
			gbc = GB_T;
			break;
		    default:
			gbc = GB_Other;
			break;
		    }
		}
		break;
	    }
	}
    }

    /* Otherwise, search built-in map using hash table. */
    if ((lbcptr && lbc == PROP_UNKNOWN) ||
	(eawptr && eaw == PROP_UNKNOWN) ||
	(gbcptr && gbc == PROP_UNKNOWN)) {
	if (c < 0x20000) {
	    ent = linebreak_prop_array + (linebreak_prop_index[c >> BLKLEN] +
		  (c & ((1 << BLKLEN) - 1))) * 4;
	} else if (c <= 0x2FFFD || (0x30000 <= c && c <= 0x3FFFD))
	    ent = PROPENT_HAN;
	else if (c == 0xE0001 || (0xE0020 <= c && c <= 0xE007E) ||
	       c == 0xE007F)
	    ent = PROPENT_TAG;
	else if (0xE0100 <= c && c <= 0xE01EF)
	    ent = PROPENT_VSEL;
	else if ((0xF0000 <= c && c <= 0xFFFFD) ||
		 (0x100000 <= c && c <= 0x10FFFD))
	    ent = PROPENT_PRIVATE;
	else
	    ent = PROPENT_UNKNOWN;

	if (lbcptr && lbc == PROP_UNKNOWN)
	    lbc = ent[0];
	if (eawptr && eaw == PROP_UNKNOWN)
	    eaw = ent[1];
	if (gbcptr && gbc == PROP_UNKNOWN)
	    gbc = ent[2];
	if (scrptr)
	    scr = ent[3];
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
