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

gcstring_t *linebreak_break_partial(linebreak_t *lbobj, gcstring_t *input)
{
    int eot = (input == NULL);
    gcstring_t *str, *s;
    unistr_t unistr;
    size_t i;

    int state;
    gcstring_t *bufStr, *bufSpc, *result;
    double bufCols;
    size_t bBeg = 0, bLen = 0, bCM = 0, bSpc = 0, aCM = 0, urgEnd = 0;

    /***
     *** Unread and additional input.
     ***/

    unistr.str = lbobj->unread;
    unistr.len = lbobj->unreadsiz;
    if ((str = gcstring_new(&unistr, lbobj)) == NULL)
	return NULL;
    lbobj->unread = NULL;
    lbobj->unreadsiz = 0;
    if (gcstring_append(str, input) == NULL)
	return NULL;

    /***
     *** Preprocessing.
     ***/

    /* perform user breaking */
    s = _preprocess(lbobj, str);
    gcstring_destroy(str);
    if ((str = s) == NULL)
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
     * bufCols: Columns of befStr: can be differ from bufStr->columns.
     * state: Start of text/paragraph status.
     *   0: Start of text not done.
     *   1: Start of text done while start of paragraph not done.
     *   2: Start of paragraph done while end of paragraph not done.
     */
    state = lbobj->state;

    unistr.str = lbobj->bufstr;
    unistr.len = lbobj->bufstrsiz;
    bufStr = gcstring_new(&unistr, lbobj);
    lbobj->bufstr = NULL;
    lbobj->bufstrsiz = 0;

    unistr.str = lbobj->bufspc;
    unistr.len = lbobj->bufspcsiz;
    bufSpc = gcstring_new(&unistr, lbobj);
    lbobj->bufspc = NULL;
    lbobj->bufspcsiz = 0;

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

    /* Result. */
    unistr.str = NULL;
    unistr.len = 0;
    result = gcstring_new(&unistr, lbobj);

    while (1) {
	/***
	 *** Chop off a pair of unbreakable character clusters from text.
	 ***/
	int action = 0;
	propval_t lbc;
	gcstring_t *beforeFrg, *fmt;
	double newcols;

	while (!gcstring_eos(str)) {
	    propval_t lbc;

	    if (1) {
		/* Go ahead reading input. */

		lbc = str->gcstr[str->pos].lbc;

		/**
		 ** Append SP/ZW/eop to ``before'' buffer.
		 **/
		while (1) {
		    switch (lbc) {
		    /* - Explicit breaks and non-breaks */

		    /* LB7(1): × SP+ */
		    case LB_SP:
			gcstring_next(str);
			bSpc++;

			/* End of input. */
			if gcstring_eos(str)
			    goto last_CHARACTER_PAIR;
			lbc = str->gcstr[str->pos].lbc;
			continue; /* while (1) */

		    /* - Mandatory breaks */

		    /* LB4 - LB7: × SP* (BK | CR LF | CR | LF | NL) ! */
		    case LB_BK:
		    case LB_CR:
		    case LB_LF:
		    case LB_NL:
			gcstring_next(str);
			bSpc++;
			goto last_CHARACTER_PAIR;

		    /* - Explicit breaks and non-breaks */

		    /* LB7(2): × (SP* ZW+)+ */
		    case LB_ZW:
			gcstring_next(str);
			bLen += bSpc + 1;
			bCM = 0;
			bSpc = 0;

			/* End of input */
			if gcstring_eos(str)
			    goto last_CHARACTER_PAIR;
			lbc = str->gcstr[str->pos].lbc;
			continue; /* while (1) */
		    }

		    break; /* while (1) */
		} /* while (1) */

		/**
		 ** Then fill ``after'' buffer.
		 **/

		/* - Rules for other line breaking classes */
		gcstring_next(str);

		/* - Combining marks   */
		/* LB9: Treat X CM+ as if it were X
		 * where X is anything except BK, CR, LF, NL, SP or ZW
		 * (NB: Some CM characters may be single grapheme cluster
		 * since they have Grapheme_Cluster_Break property Control.) */
		while (!gcstring_eos(str) &&
		        str->gcstr[str->pos].lbc == LB_CM) {
		    gcstring_next(str);
		    aCM++;
		}
	    } /* if (1) */

	    /* - Start of text */

	    /* LB2: sot × */
	    if (0 < bLen || 0 < bSpc)
		break; /* CHARACTER_PAIR */

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
	    action = MANDATORY;
	/* LB11 - LB29 and LB31: Tailorable rules (except LB11, LB12). */
	/* Or urgent breaking. */
	} else if (bBeg + bLen + bSpc < str->pos) {
	    if (str->gcstr[bBeg + bLen + bSpc].flag &
		LINEBREAK_FLAG_BREAK_BEFORE) {
		action = DIRECT;
	    } else if (str->gcstr[bBeg + bLen + bSpc].flag &
		     LINEBREAK_FLAG_PROHIBIT_BEFORE) {
		action = PROHIBITED;
	    } else if (bLen == 0 && 0 < bSpc) {
		/* Prohibit break at sot or after breaking,
		   alhtough rules doesn't tell it obviously. */
		action = PROHIBITED;
	    } else {
		propval_t blbc, albc;

		#define lbclass_custom(xlbc, base)			\
		/* LB9: Treat X CM+ as if it were X			\
		   where X is anything except BK, CR, LF, NL, SP or ZW */ \
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

		lbclass_custom(blbc, bBeg + bLen - bCM - 1);
		lbclass_custom(albc, bBeg + bLen + bSpc);
		action = linebreak_lbrule(blbc, albc);
	    }

	    /* Check prohibited break. */
	    if (action == PROHIBITED ||	(action == INDIRECT && bSpc == 0)) {
		/* When conjunction is expected to exceed charmax,
		   try urgent breaking. */
		if (lbobj->charmax < str->gcstr[str->pos - 1].idx +
		    str->gcstr[str->pos - 1].len - str->gcstr[bBeg].idx) {
		    gcstring_t *bsa, *broken;
		    size_t charmax, chars;

		    bsa = gcstring_substr(str, bBeg, str->pos - bBeg, NULL);
		    broken = _urgent_break(lbobj, 0, NULL, NULL, bsa);
		    gcstring_destroy(bsa);

		    /* If any of urgently broken fragments still
		       exceed CharactersMax, force chop them. */
		    charmax = lbobj->charmax;
		    broken->pos = 0;
		    chars = gcstring_next(broken)->len;
		    while (!gcstring_eos(broken)) {
			if (broken->gcstr[broken->pos].flag &
			    LINEBREAK_FLAG_BREAK_BEFORE) {
			    chars = 0;
			} else if (charmax <
				 chars + broken->gcstr[broken->pos].len) {
			    broken->gcstr[broken->pos].flag |=
				LINEBREAK_FLAG_BREAK_BEFORE;
			    chars = 0;
			} else {
			    chars += broken->gcstr[broken->pos].len;
			}
			gcstring_next(broken);
		    }

		    urgEnd = broken->gclen;
		    gcstring_substr(str, 0, str->pos, broken);
		    gcstring_destroy(broken);
		    str->pos = 0;
		    bBeg = bLen = bCM = bSpc = aCM = 0;
		    continue; /* while (1) */
		} 
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
	    /* FIXME: memory leak */
	    lbobj->bufstr = bufStr->str;
	    lbobj->bufstrsiz = bufStr->len;

	    lbobj->bufspc = bufSpc->str;
	    lbobj->bufspcsiz = bufSpc->len;

            lbobj->bufcols = bufCols;

	    s = gcstring_substr(str, bBeg, str->gclen - bBeg, NULL);
            lbobj->unread = s->str;
            lbobj->unreadsiz = s->len;

            lbobj->state = state;

            return result;
        }

	/* After all, possible actions are MANDATORY and other arbitrary. */

	/***
	 *** Examine line breaking action
	 ***/

	beforeFrg = gcstring_substr(str, bBeg, bLen, NULL);

	if (state == LINEBREAK_STATE_NONE) { /* sot undone. */
	    /* Process start of text. */
	    /* FIXME:need test. */
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

		state = LINEBREAK_STATE_SOT_FORMAT;
		gcstring_destroy(fmt);
		gcstring_destroy(beforeFrg);

		continue; /* while (1) */
	    }
	    gcstring_destroy(fmt);
	    state = LINEBREAK_STATE_SOT;
	} else if (state == LINEBREAK_STATE_SOT_FORMAT) {
	    state = LINEBREAK_STATE_SOT;
	} else if (state == LINEBREAK_STATE_SOT) { /* sop undone. */
	    /* Process start of paragraph. */
	    /* FIXME:need test. */
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

		state = LINEBREAK_STATE_SOP_FORMAT;
		gcstring_destroy(fmt);
		gcstring_destroy(beforeFrg);

		continue; /* while (1) */
	    }
	    gcstring_destroy(fmt);
	    state = LINEBREAK_STATE_SOP;
	} else if (state == LINEBREAK_STATE_SOP_FORMAT) {
	    state = LINEBREAK_STATE_SOP;
	}

	/***
	 *** Check if arbitrary break is needed.
	 ***/
	newcols = _sizing(lbobj, bufCols, bufStr, bufSpc, beforeFrg, 0);
	if (0 < lbobj->colmax && lbobj->colmax < newcols) {
	    newcols = _sizing(lbobj, 0, NULL, NULL, beforeFrg, 0); 

	    /**
	     ** When arbitrary break is expected to generate very short line,
	     ** or beforeFrg will exceed ColumnsMax, try urgent breaking.
	     **/
	    if (urgEnd < bBeg + bLen + bSpc) {
		gcstring_t *broken = NULL;
		if (0 < bufCols && bufCols < lbobj->colmin) {
		    broken = _urgent_break(lbobj, bufCols, bufStr, bufSpc,
					   beforeFrg);
		} else if (lbobj->colmax < newcols) {
		    broken = _urgent_break(lbobj, 0, NULL, NULL, beforeFrg);
		}
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
		} else {
		    /* FIXME */
		}
	    }

	    /**
	     ** Otherwise, process arbitrary break.
	     **/
	    if (bufStr->len || bufSpc->len) {
		s = _format(lbobj, LINEBREAK_STATE_LINE, bufStr);
		gcstring_append(result, s);
		gcstring_destroy(s);
		s = _format(lbobj, LINEBREAK_STATE_EOL, bufSpc);
		gcstring_append(result, s);
		gcstring_destroy(s);

		fmt = _format(lbobj, LINEBREAK_STATE_SOL, beforeFrg);
		if (gcstring_cmp(beforeFrg, fmt) != 0) {
		    gcstring_destroy(beforeFrg);
		    beforeFrg = fmt;
		    newcols = _sizing(lbobj, 0, NULL, NULL, beforeFrg, 0);
		}
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
        if (eot && str->gclen <= bBeg + bLen + bSpc) {
	    break; /* while (1) */
        }
        if (action == MANDATORY) {
            /* Process mandatory break. */
	    s = _format(lbobj, LINEBREAK_STATE_LINE, bufStr);
	    gcstring_append(result, s);
	    gcstring_destroy(s);

	    s = _format(lbobj, LINEBREAK_STATE_EOP, bufSpc);
	    gcstring_append(result, s);
	    gcstring_destroy(s);

	    state = 1; /* eop done then sop must be carried out. */

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
    gcstring_append(result, s);
    gcstring_destroy(s);
    s = _format(lbobj, LINEBREAK_STATE_EOT, bufSpc);
    gcstring_append(result, s);
    gcstring_destroy(s);

    /* Reset status then return the rest of result. */
    linebreak_reset(lbobj);
    return result;
}
