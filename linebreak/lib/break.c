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
gcstring_t *_preprocess(linebreak_t *lbobj, unistr_t *str)
{
    gcstring_t *t, *result;

    if (str == NULL)
	return NULL;
    else if (lbobj->user_data == NULL || lbobj->user_func == NULL ||
	     (result = (*(lbobj->user_func))(lbobj, str)) == NULL) {
	t = gcstring_new(str, lbobj);
	result = gcstring_copy(t);
	t->str = NULL;
	t->len = 0;
	gcstring_destroy(t);
    }
    return result;
}

static
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

static
double _sizing(linebreak_t *lbobj, double len,
	       gcstring_t *pre, gcstring_t *spc, gcstring_t *str, size_t max)
{
    double ret;

    if (lbobj->sizing_data == NULL || lbobj->sizing_func == NULL ||
	(ret = (*(lbobj->sizing_func))(lbobj, len, pre, spc, str, max)) < 0.0)
	return linebreak_strsize(lbobj, len, pre, spc, str, max);
    return ret;
}

static
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

#define unistr_append(us, appe)						\
    if (appe != NULL && appe->len != 0) {				\
	if (((us)->str =						\
	     realloc((us)->str,						\
		     sizeof(unichar_t) * ((us)->len + appe->len))) == NULL) \
	    return NULL;						\
	memcpy((us)->str + (us)->len, appe->str,			\
	       sizeof(unichar_t) * appe->len);				\
	(us)->len += appe->len;						\
    }

#define unistrp_destroy(ustr)			\
    if (ustr) {					\
	if (ustr->str) free(ustr->str);		\
	free(ustr);				\
    }

unistr_t *linebreak_break_partial(linebreak_t *lbobj, unistr_t *input)
{
    gcstring_t *s;
    unistr_t unistr;
    size_t i;

    int eot = (input == NULL);
    int state;
    gcstring_t *str, *bufStr, *bufSpc;
    double bufCols;
    size_t bBeg, bLen, bCM, bSpc, aCM, urgEnd;
    unistr_t *result;

    /***
     *** Unread and additional input.
     ***/

    unistr.str = lbobj->unread.str;
    unistr.len = lbobj->unread.len;
    lbobj->unread.str = NULL;
    lbobj->unread.len = 0;
    unistr_append(&unistr, input);

    /***
     *** Preprocessing.
     ***/

    /* perform user breaking */
    str = _preprocess(lbobj, &unistr);
    if (unistr.str)
	free(unistr.str);
    if (str == NULL)
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

    /***
     *** Initialize status.
     ***/

    str->pos = 0;

    /*
     * Line buffer.
     * bufStr: Unbreakable text fragment.
     * bufSpc: Trailing spaces.
     * bufCols: Columns of bufStr: can be differ from gcstring_columns().
     * state: Start of text/paragraph status.
     *   0: Start of text not done.
     *   1: Start of text done while start of paragraph not done.
     *   2: Start of paragraph done while end of paragraph not done.
     */
    state = lbobj->state;

    unistr.str = lbobj->bufstr.str;
    unistr.len = lbobj->bufstr.len;
    bufStr = gcstring_new(&unistr, lbobj);
    lbobj->bufstr.str = NULL;
    lbobj->bufstr.len = 0;
    if (bufStr == NULL) {
	gcstring_destroy(str);
	return NULL;
    }

    unistr.str = lbobj->bufspc.str;
    unistr.len = lbobj->bufspc.len;
    bufSpc = gcstring_new(&unistr, lbobj);
    lbobj->bufspc.str = NULL;
    lbobj->bufspc.len = 0;
    if (bufSpc == NULL) {
	gcstring_destroy(str);
	gcstring_destroy(bufStr);
	return NULL;
    }    

    bufCols = lbobj->bufcols;

    /*
     * Indexes and flags
     * bBeg:  Start of unbreakable text fragment.
     * bLen:  Length of unbreakable text fragment.
     * bSpc:  Length of trailing spaces.
     * urgEnd: End of substring broken by urgent breaking.
     *
     * ...read...| before :CM |  spaces  | after :CM |...unread...|
     *           ^       ->bCM<-         ^      ->aCM<-           ^
     *           |<-- bLen -->|<- bSpc ->|           ^            |
     *          bBeg                 candidate    str->pos     end of
     *                                breaking                  input
     *                                 point
     * `read' positions shall never be read more.
     */
    bBeg = bLen = bCM = bSpc = aCM = urgEnd = 0;

    /* Result. */
    if ((result = malloc(sizeof(unistr_t))) == NULL) {
	gcstring_destroy(str);
	gcstring_destroy(bufStr);
	gcstring_destroy(bufSpc);
	return NULL;
    }
    result->str = NULL;
    result->len = 0;

    while (1) {
	/***
	 *** Chop off a pair of unbreakable character clusters from text.
	 ***/
	int action = 0;
	propval_t lbc;
	gcstring_t *beforeFrg, *fmt;
	double newcols;

	/* Go ahead reading input. */
	while (!gcstring_eos(str)) {
	    lbc = str->gcstr[str->pos].lbc;

	    /**
	     ** Append SP/ZW/eop to ``before'' buffer.
	     **/
	    switch (lbc) {
	    /* - Explicit breaks and non-breaks */

	    /* LB7(1): × SP+ */
	    case LB_SP:
		gcstring_next(str);
		bSpc++;

		/* End of input. */
		continue; /* while (!gcstring_eos(str)) */

	    /* - Mandatory breaks */

	    /* LB4 - LB7: × SP* (BK | CR LF | CR | LF | NL) ! */
	    case LB_BK:
	    case LB_CR:
	    case LB_LF:
	    case LB_NL:
		gcstring_next(str);
		bSpc++;
		goto last_CHARACTER_PAIR; /* while (!gcstring_eos(str)) */

	    /* - Explicit breaks and non-breaks */

	    /* LB7(2): × (SP* ZW+)+ */
	    case LB_ZW:
		gcstring_next(str);
		bLen += bSpc + 1;
		bCM = 0;
		bSpc = 0;

		/* End of input */
		continue; /* while (!gcstring_eos(str)) */
	    }

	    /**
	     ** Then fill ``after'' buffer.
	     **/

	    gcstring_next(str);

	    /* skip to end of unbreakable fragment by user/complex/urgent
	       breaking. */
	    while (!gcstring_eos(str) && str->gcstr[str->pos].flag &
		   LINEBREAK_FLAG_PROHIBIT_BEFORE)
		gcstring_next(str);

	    /* - Combining marks   */
	    /* LB9: Treat X CM+ as if it were X
	     * where X is anything except BK, CR, LF, NL, SP or ZW
	     * (NB: Some CM characters may be single grapheme cluster
	     * since they have Grapheme_Cluster_Break property Control.) */
	    while (!gcstring_eos(str) && str->gcstr[str->pos].lbc == LB_CM) {
		gcstring_next(str);
		aCM++;
	    }

	    /* - Start of text */

	    /* LB2: sot × */
	    if (0 < bLen || 0 < bSpc)
		break; /* while (!gcstring_eos(str)) */

	    /* shift buffers. */
	    /* XXX bBeg += bLen + bSpc; */
	    bLen = str->pos - bBeg;
	    bSpc = 0;
	    bCM = aCM;
	    aCM = 0;
	} /* while (!gcstring_eos(str)) */
      last_CHARACTER_PAIR:

	/***
	 *** Determin line breaking action by classes of adjacent characters.
	 ***/

	/* Mandatory break. */
	if (0 < bSpc &&
	    (lbc = str->gcstr[bBeg + bLen + bSpc - 1].lbc) != LB_SP &&
	    (lbc != LB_CR || eot || !gcstring_eos(str))) {
	    /* CR at end of input may be part of CR LF therefore not be eop. */
	    action = MANDATORY;
	/* LB11 - LB31: Tailorable rules (except LB11, LB12). */
	/* Or urgent breaking. */
	} else if (bBeg + bLen + bSpc < str->pos) {
	    if (str->gcstr[bBeg + bLen + bSpc].flag &
		LINEBREAK_FLAG_BREAK_BEFORE)
		action = DIRECT;
	    else if (str->gcstr[bBeg + bLen + bSpc].flag &
		     LINEBREAK_FLAG_PROHIBIT_BEFORE)
		action = PROHIBITED;
	    else if (bLen == 0 && 0 < bSpc)
		/* Prohibit break at sot or after breaking,
		   alhtough rules doesn't tell it obviously. */
		action = PROHIBITED;
	    else {
		propval_t blbc, albc;

		#define lbclass_custom(xlbc, base)			\
									\
		xlbc = str->gcstr[base].lbc;				\
		/* LB10: Treat any remaining CM+ as if it were AL. */	\
		switch (xlbc) {						\
		case LB_CM:						\
		    xlbc = LB_AL;					\
		    break;						\
		/* LB27: Treat hangul syllable as if it were ID (or AL). */ \
		case LB_H2:						\
		case LB_H3:						\
		case LB_JL:						\
		case LB_JV:						\
		case LB_JT:						\
		    xlbc = (lbobj->options & LINEBREAK_OPTION_HANGUL_AS_AL)? \
			LB_AL: LB_ID;					\
		    break;						\
		}

		lbclass_custom(blbc, bBeg + bLen - bCM - 1); /* LB9 */
		lbclass_custom(albc, bBeg + bLen + bSpc);
		action = linebreak_lbrule(blbc, albc);
	    }

	    /* Check prohibited break. */
	    if (action == PROHIBITED ||	(action == INDIRECT && bSpc == 0)) {
		/* When conjunction is expected to exceed charmax,
		   try urgent breaking. */
		if (lbobj->charmax < str->gcstr[str->pos - 1].idx +
		    str->gcstr[str->pos - 1].len - str->gcstr[bBeg].idx) {
		    gcstring_t *broken;
		    size_t charmax, chars;

		    s = gcstring_substr(str, bBeg, str->pos - bBeg, NULL);
		    broken = _urgent_break(lbobj, 0, NULL, NULL, s);
		    gcstring_destroy(s);

		    /* If any of urgently broken fragments still
		       exceed CharactersMax, force chop them. */
		    charmax = lbobj->charmax;
		    broken->pos = 0;
		    chars = gcstring_next(broken)->len;
		    while (!gcstring_eos(broken)) {
			if (broken->gcstr[broken->pos].flag &
			    LINEBREAK_FLAG_BREAK_BEFORE)
			    chars = 0;
			else if (charmax <
				 chars + broken->gcstr[broken->pos].len) {
			    broken->gcstr[broken->pos].flag |=
				LINEBREAK_FLAG_BREAK_BEFORE;
			    chars = 0;
			} else
			    chars += broken->gcstr[broken->pos].len;
			gcstring_next(broken);
		    } /* while (!gcstring_eos(broken)) */

		    urgEnd = broken->gclen;
		    gcstring_substr(str, 0, str->pos, broken);
		    gcstring_destroy(broken);
		    str->pos = 0;
		    bBeg = bLen = bCM = bSpc = aCM = 0;
		    continue; /* while (1) */
		} /* if (lbobj->charmax < ...) */

		/* Otherwise, fragments may be conjuncted safely. Read more. */
		bLen = str->pos - bBeg;
		bSpc = 0;
		bCM = aCM;
		aCM = 0;
		continue; /* while (1) */
	    } /* if (action == PROHIBITED || ...) */
	} /* if (0 < bSpc && ...) */

        /***
	 *** Check end of input.
	 ***/
	if (!eot && str->gclen <= bBeg + bLen + bSpc) {
	    /* Save status then output partial result. */
	    lbobj->bufstr.str = bufStr->str;
	    lbobj->bufstr.len = bufStr->len;
	    bufStr->str = NULL;
	    bufStr->len = 0;
	    gcstring_destroy(bufStr);

	    lbobj->bufspc.str = bufSpc->str;
	    lbobj->bufspc.len = bufSpc->len;
	    bufSpc->str = NULL;
	    bufSpc->len = 0;
	    gcstring_destroy(bufSpc);

            lbobj->bufcols = bufCols;

	    s = gcstring_substr(str, bBeg, str->gclen - bBeg, NULL);
            lbobj->unread.str = s->str;
            lbobj->unread.len = s->len;
	    s->str = NULL;
	    s->len = 0;
	    gcstring_destroy(s);
	    
	    lbobj->state = state;
	    
            return result;
        }

	/* After all, possible actions are MANDATORY and arbitrary. */

	/***
	 *** Examine line breaking action
	 ***/

	beforeFrg = gcstring_substr(str, bBeg, bLen, NULL);

	if (state == LINEBREAK_STATE_NONE) { /* sot undone. */
	    /* Process start of text. */
	    fmt = _format(lbobj, LINEBREAK_STATE_SOT, beforeFrg);
	    if (gcstring_cmp(beforeFrg, fmt) != 0) {
		s = gcstring_substr(str, bBeg + bLen, bSpc, NULL);
		gcstring_append(fmt, s);
		gcstring_destroy(s);
		s = gcstring_substr(str, bBeg + bLen + bSpc,
				    str->pos - (bBeg + bLen + bSpc), NULL);
		gcstring_append(fmt, s);
		gcstring_destroy(s);
		gcstring_substr(str, 0, str->pos, fmt);
		str->pos = 0;
		bBeg = bLen = bCM = bSpc = aCM = 0;
		urgEnd = 0;

		state = LINEBREAK_STATE_SOT_FORMAT;
		gcstring_destroy(fmt);
		gcstring_destroy(beforeFrg);

		continue; /* while (1) */
	    }
	    gcstring_destroy(fmt);
	    state = LINEBREAK_STATE_SOL;
	} else if (state == LINEBREAK_STATE_SOT_FORMAT)
	    state = LINEBREAK_STATE_SOL;
	else if (state == LINEBREAK_STATE_SOT) { /* sop undone. */
	    /* Process start of paragraph. */
	    fmt = _format(lbobj, LINEBREAK_STATE_SOP, beforeFrg);
	    if (gcstring_cmp(beforeFrg, fmt) != 0) {
		s = gcstring_substr(str, bBeg + bLen, bSpc, NULL);
		gcstring_append(fmt, s);
		gcstring_destroy(s);
		s = gcstring_substr(str, bBeg + bLen + bSpc,
				    str->pos - (bBeg + bLen + bSpc), NULL);
		gcstring_append(fmt, s);
		gcstring_destroy(s);
		gcstring_substr(str, 0, str->pos, fmt);
		str->pos = 0;
		bBeg = bLen = bCM = bSpc = aCM = 0;
		urgEnd = 0;

		state = LINEBREAK_STATE_SOP_FORMAT;
		gcstring_destroy(fmt);
		gcstring_destroy(beforeFrg);

		continue; /* while (1) */
	    }
	    gcstring_destroy(fmt);
	    state = LINEBREAK_STATE_SOP;
	} else if (state == LINEBREAK_STATE_SOP_FORMAT)
	    state = LINEBREAK_STATE_SOP;

	/***
	 *** Check if arbitrary break is needed.
	 ***/
	newcols = _sizing(lbobj, bufCols, bufStr, bufSpc, beforeFrg, 0);
	if (0 < lbobj->colmax && lbobj->colmax < newcols) {
	    newcols = _sizing(lbobj, 0, NULL, NULL, beforeFrg, 0); 

	    /**
	     ** When arbitrary break is expected to generate very short line,
	     ** or beforeFrg will exceed colmax, try urgent breaking.
	     **/
	    if (urgEnd < bBeg + bLen + bSpc) {
		gcstring_t *broken = NULL;

		if (0 < bufCols && bufCols < lbobj->colmin)
		    broken = _urgent_break(lbobj, bufCols, bufStr, bufSpc,
					   beforeFrg);
		else if (lbobj->colmax < newcols)
		    broken = _urgent_break(lbobj, 0, NULL, NULL, beforeFrg);

		if (broken != NULL) {
		    s = gcstring_substr(str, bBeg + bLen, bSpc, NULL);
		    gcstring_append(broken, s);
		    gcstring_destroy(s);
		    gcstring_substr(str, 0, bBeg + bLen + bSpc, broken);
		    gcstring_destroy(broken);
		    str->pos = 0;
		    urgEnd = broken->gclen;
		    bBeg = bLen = bCM = bSpc = aCM = 0;

		    gcstring_destroy(beforeFrg);
		    continue; /* while (1) */
		}
	    }

	    /**
	     ** Otherwise, process arbitrary break.
	     **/
	    if (bufStr->len || bufSpc->len) {
		s = _format(lbobj, LINEBREAK_STATE_LINE, bufStr);
		unistr_append(result, s);
		gcstring_destroy(s);
		s = _format(lbobj, LINEBREAK_STATE_EOL, bufSpc);
		unistr_append(result, s);
		gcstring_destroy(s);

		fmt = _format(lbobj, LINEBREAK_STATE_SOL, beforeFrg);
		if (gcstring_cmp(beforeFrg, fmt) != 0) {
		    gcstring_destroy(beforeFrg);
		    beforeFrg = fmt;
		    newcols = _sizing(lbobj, 0, NULL, NULL, beforeFrg, 0);
		} else 
		    gcstring_destroy(fmt);
	    }
	    gcstring_shrink(bufStr, 0);
	    gcstring_append(bufStr, beforeFrg);

	    gcstring_shrink(bufSpc, 0);
	    s = gcstring_substr(str, bBeg + bLen, bSpc, NULL);
	    gcstring_append(bufSpc, s);
	    gcstring_destroy(s);

	    bufCols = newcols;
	/***
	 *** Arbitrary break is not needed.
	 ***/
	} else {
	    gcstring_append(bufStr, bufSpc);
	    gcstring_append(bufStr, beforeFrg);

	    gcstring_shrink(bufSpc, 0);
	    s = gcstring_substr(str, bBeg + bLen, bSpc, NULL);
	    gcstring_append(bufSpc, s);
	    gcstring_destroy(s);

	    bufCols = newcols;
	} /* if (0 < lbobj->colmax && lbobj->colmax < newcols) */

	gcstring_destroy(beforeFrg);

        /***
	 *** Mandatory break or end-of-text.
	 ***/
        if (eot && str->gclen <= bBeg + bLen + bSpc)
	    break; /* while (1) */

        if (action == MANDATORY) {
            /* Process mandatory break. */
	    s = _format(lbobj, LINEBREAK_STATE_LINE, bufStr);
	    unistr_append(result, s);
	    gcstring_destroy(s);
	    s = _format(lbobj, LINEBREAK_STATE_EOP, bufSpc);
	    unistr_append(result, s);
	    gcstring_destroy(s);

	    /* eop done then sop must be carried out. */
	    state = LINEBREAK_STATE_SOT;

	    gcstring_shrink(bufStr, 0);
	    gcstring_shrink(bufSpc, 0);
	    bufCols = 0;
        }

        /***
	 *** Shift buffers.
	 ***/
        bBeg += bLen + bSpc;
        bLen = str->pos - bBeg;
        bSpc = 0;
        bCM = aCM;
        aCM = 0;
    } /* while (1) */

    /***
     *** Process end of text.
     ***/
    s = _format(lbobj, LINEBREAK_STATE_LINE, bufStr);
    unistr_append(result, s);
    gcstring_destroy(s);
    s = _format(lbobj, LINEBREAK_STATE_EOT, bufSpc);
    unistr_append(result, s);
    gcstring_destroy(s);

    /* Reset status then return the rest of result. */
    linebreak_reset(lbobj);
    return result;
}

unistr_t *linebreak_break_fast(linebreak_t *lbobj, unistr_t *input)
{
    unistr_t *ret, *t;

    if (input == NULL || input->len == 0) {
	ret = malloc(sizeof(unistr_t));
	if (ret) {
	    ret->str = NULL;
	    ret->len = 0;
	}
	return ret;
    }

    ret = linebreak_break_partial(lbobj, input);
    t = linebreak_break_partial(lbobj, NULL);
    unistr_append(ret, t);
    unistrp_destroy(t);

    return ret;
}

unistr_t *linebreak_break(linebreak_t *lbobj, unistr_t *input)
{
    unichar_t *str;
    unistr_t unistr = {0, 0}, *t, *ret;
    size_t i;

    if ((ret = malloc(sizeof(unistr_t))) == NULL)
	return NULL;
    ret->str = NULL;
    ret->len = 0;
    if (input == NULL || input->str == NULL || input->len == 0)
	return ret;

    if ((str = malloc(sizeof(unichar_t) * 1000)) == NULL)
	return NULL;
    for (i = 0; 1000 < input->len - i; i += 1000) {
	unistr.str = input->str + i;
	unistr.len = 1000;
	t = linebreak_break_partial(lbobj, &unistr);
	unistr_append(ret, t);
	unistrp_destroy(t);
    }
    unistr.str = input->str + i;
    unistr.len = input->len - i;
    t = linebreak_break_partial(lbobj, &unistr);
    unistr_append(ret, t);
    unistrp_destroy(t);

    t = linebreak_break_partial(lbobj, NULL);
    unistr_append(ret, t);
    unistrp_destroy(t);

    free(str);
    return ret;
}
