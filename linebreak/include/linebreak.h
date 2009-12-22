/*
 * linebreak.h - common definitions for linebreak library
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

#ifndef _LINEBREAK_LINEBREAK_H_

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif
#include <errno.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#ifdef HAVE_STRINGS_H
#    include <strings.h>
#endif /* HAVE_STRINGS_H */

/***
 *** Data structure.
 ***/

/* Primitive types */
/** Unicode character */
typedef unsigned int unichar_t;
/** Character property */
typedef unsigned char propval_t;
typedef enum {
    LINEBREAK_STATE_NONE = 0,
    LINEBREAK_STATE_SOT, LINEBREAK_STATE_SOP, LINEBREAK_STATE_SOL,
    LINEBREAK_STATE_LINE,
    LINEBREAK_STATE_EOL, LINEBREAK_STATE_EOP, LINEBREAK_STATE_EOT,
    LINEBREAK_STATE_MAX
} linebreak_state_t;
#define LINEBREAK_STATE_SOT_FORMAT (-LINEBREAK_STATE_SOT)
#define LINEBREAK_STATE_SOP_FORMAT (-LINEBREAK_STATE_SOP)
#define LINEBREAK_STATE_SOL_FORMAT (-LINEBREAK_STATE_SOL)


/** Unicode string */
typedef struct {
    /** Sequence of Unicode character.
     * Note that NUL character (U+0000) may be contained.
     * NULL may specify zero-length string. */
    unichar_t *str;
    /** Length of Unicode character sequence. */
    size_t len;
} unistr_t;

/** Grapheme cluster */
typedef struct {
    /** Offset of Unicode string. */
    size_t idx;
    /** Length of Unicode string. */
    size_t len;
    /** Caliculated number of columns. */
    size_t col;
    /** Line breaking class of grapheme base. */
    propval_t lbc;
    /** Line breaking class of grapheme extender if it is not CM. */
    propval_t elbc;
    /** User-defined flag. */
    unsigned char flag;
} gcchar_t;

/** Property map entry */
typedef struct {
    /** Beginning of UCS range. */
    unichar_t beg;
    /** End of UCS range. */
    unichar_t end;
    /** UAX #14 line breaking class. */
    propval_t lbc;
    /** UAX #11 East_Asian_Width property value. */
    propval_t eaw;
    /** UAX #29 Grapheme_Cluster_Break property value. */
    propval_t gbc;
    /** Script property value. */
    propval_t scr;
} mapent_t;

/** Grapheme cluster string. */
typedef struct {
    /** Sequence of Unicode characters.
     * Note that NUL character (U+0000) may be contained.
     * NULL may specify zero-length string. */
    unichar_t *str;
    /** Number of Unicode characters. */
    size_t len;
    /** Sequence of grapheme clusters. */
    gcchar_t *gcstr;
    /** Number of grapheme clusters.
	NULL may specify zero-length string. */
    size_t gclen;
    /** Next position. */
    size_t pos;
    /** linebreak object. */
    void *lbobj;
} gcstring_t;

/** LineBreak object */
typedef struct {
    /***
     * private members
     */
    /** reference count */
    unsigned long int refcount;
    /** state */
    int state;
    /** buffered line */
    unistr_t bufstr;
    /** spaces trailing to buffered line */
    unistr_t bufspc;
    /** caliculated columns of buffered line */
    double bufcols;
    /** unread input */
    unistr_t unread;

    /***
     * public members
     */
    /** Maximum number of Unicode characters each line may contain. */
    size_t charmax;
    /** Maximum number of columns. */
    double colmax;
    /** Minimum number of columns. */
    double colmin;
    /** User-tailored property map. */
    mapent_t *map;
    size_t mapsiz;
    /** Newline sequence. */
    unistr_t newline;
    /** Options.  See Defines. */
    unsigned int options;
    void *format_data;
    void *sizing_data;
    void *urgent_data;
    void *user_data;
    /** User-defined private data. */
    void *stash;
    /** Format function.
     *
     */
    gcstring_t *(*format_func)();
    /** Sizing function.
     *
     */
    double (*sizing_func)();
    /** Urgent breaking function.
     *
     */
    gcstring_t *(*urgent_func)();
    /** Preprocessing function.
     *
     */
    gcstring_t *(*user_func)();
    /** Reference Count function.
     *
     */
    void (*ref_func)();
} linebreak_t;

/***
 *** Constants.
 ***/

#define LINEBREAK_OPTION_EASTASIAN_CONTEXT (1)
#define LINEBREAK_OPTION_HANGUL_AS_AL (2)
#define LINEBREAK_OPTION_LEGACY_CM (4)

#define LINEBREAK_REF_STASH (0)
#define LINEBREAK_REF_FORMAT (1)
#define LINEBREAK_REF_SIZING (2)
#define LINEBREAK_REF_URGENT (3)
#define LINEBREAK_REF_USER (4)

#define PROP_UNKNOWN ((propval_t)~0)

#define M (4)
#define D (3)
#define I (2)
#define P (1)

#define MANDATORY (M)
#define DIRECT (D)
#define INDIRECT (I)
#define PROHIBITED (P)

#include "linebreak_constants.h"

#define LINEBREAK_FLAG_BREAK_BEFORE (2)
#define LINEBREAK_FLAG_PROHIBIT_BEFORE (1)

/***
 *** Public functions, global variables and macros.
 ***/
extern gcstring_t *gcstring_new(unistr_t *, linebreak_t *);
extern gcstring_t *gcstring_newcopy(unistr_t *, linebreak_t *);
extern gcstring_t *gcstring_copy(gcstring_t *);
extern void gcstring_destroy(gcstring_t *);
extern gcstring_t *gcstring_append(gcstring_t *, gcstring_t *);
extern size_t gcstring_columns(gcstring_t *);
extern int gcstring_cmp(gcstring_t *, gcstring_t *);
extern gcstring_t *gcstring_concat(gcstring_t *, gcstring_t *);
extern gcchar_t *gcstring_next(gcstring_t *);
extern void gcstring_setpos(gcstring_t *, int);
extern void gcstring_shrink(gcstring_t *, int);
extern gcstring_t *gcstring_substr(gcstring_t *, int, int, gcstring_t *);

#define gcstring_eos(gcstr) \
  ((gcstr)->gclen <= (gcstr)->pos)
#define gcstring_getpos(gcstr) \
  ((gcstr)->pos)

extern linebreak_t *linebreak_new();
extern linebreak_t *linebreak_copy(linebreak_t *);
extern linebreak_t *linebreak_incref(linebreak_t *);
extern void linebreak_destroy(linebreak_t *);
extern void linebreak_reset(linebreak_t *);
extern propval_t linebreak_eawidth(linebreak_t *, unichar_t);
extern propval_t linebreak_lbclass(linebreak_t *, unichar_t);
extern propval_t linebreak_lbrule(propval_t, propval_t);
extern double linebreak_strsize(linebreak_t *, double, gcstring_t *,
                                gcstring_t *, gcstring_t *, size_t);
extern unistr_t *linebreak_break(linebreak_t *, unistr_t *);
extern unistr_t *linebreak_break_fast(linebreak_t *, unistr_t *);
extern unistr_t *linebreak_break_partial(linebreak_t *, unistr_t *);
extern const char *linebreak_unicode_version;
extern const char *linebreak_southeastasian_supported;
extern void linebreak_southeastasian_flagbreak(gcstring_t *);

#define _LINEBREAK_LINEBREAK_H_
#endif /* _LINEBREAK_LINEBREAK_H_ */
