/*
 * common.h - common definitions
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

#ifndef _LINEBREAK_COMMON_H_

#include "config.h"
#include <errno.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#ifdef HAVE_STRINGS_H
#    include <strings.h>
#endif /* HAVE_STRINGS_H */

/* Primitive types */
typedef unsigned int unichar_t;
typedef unsigned char propval_t;

/* Unicode string */
typedef struct {
    unichar_t *str;
    size_t len;
} unistr_t;

/* Grapheme cluster */
typedef struct {
    size_t idx; size_t len;
    size_t col;
    propval_t lbc;
    unsigned char flag;
} gcchar_t;

/* Property map entry */
typedef struct {
    unichar_t beg;
    unichar_t end;
    propval_t lbc;
    propval_t eaw;
    propval_t gbc;
    propval_t scr;
} mapent_t;

#define LINEBREAK_REF_STASH (0)
#define LINEBREAK_REF_FORMAT (1)
#define LINEBREAK_REF_SIZING (2)
#define LINEBREAK_REF_URGENT (3)
#define LINEBREAK_REF_USER (4)

/* LineBreak object */
typedef struct {
    size_t charmax;
    size_t colmax;
    size_t colmin;
    mapent_t *map;
    size_t mapsiz;
    unichar_t *newline;
    size_t newlinesiz;
    unsigned int options;
    void *format_data;
    void *(*format_func)(); /* gcstring_t* */
    void *sizing_data;
    size_t (*sizing_func)();
    void *urgent_data;
    void *(*urgent_func)(); /* gcstring_t** */
    void *user_data;
    void *(*user_func)(); /* gcstring_t** */
    void *stash;
    void (*ref_func)();
    unsigned long int refcount;
} linebreak_t;

/* GCString object */
typedef struct {
    unichar_t *str;
    size_t len;
    gcchar_t *gcstr;
    size_t gclen;
    size_t pos;
    linebreak_t *lbobj;
} gcstring_t;

#define LINEBREAK_OPTION_EASTASIAN_CONTEXT (1)
#define LINEBREAK_OPTION_HANGUL_AS_AL (2)
#define LINEBREAK_OPTION_LEGACY_CM (4)

#define PROP_UNKNOWN ((propval_t)~0)

#define M (4)
#define D (3)
#define I (2)
#define P (1)

#define MANDATORY (M)
#define DIRECT (D)
#define INDIRECT (I)
#define PROHIBITED (P)
#define URGENT (200)

#define LINEBREAK_FLAG_BREAK_BEFORE (2)
#define LINEBREAK_FLAG_PROHIBIT_BEFORE (1)

#define _LINEBREAK_COMMON_H_
#endif /* _LINEBREAK_COMMON_H_ */
