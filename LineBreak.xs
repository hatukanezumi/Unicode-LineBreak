/*
 * LineBreak.xs - Perl XS glue for Linebreak package.
 * 
 * Copyright (C) 2009 Hatuka*nezumi - IKEDA Soji <hatuka(at)nezumi.nu>.
 * 
 * This file is part of the Unicode::LineBreak package.  This program is
 * free software; you can redistribute it and/or modify it under the same
 * terms as Perl itself.
 *
 * $Id$
 */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include "linebreak.h"

/* by CPAN test #5515619 */
#ifndef UTF8_MAXBYTES
#define UTF8_MAXBYTES (13)
#endif

/***
 *** Utilities.
 ***/

/*
 * Create C property map from Perl arrayref.
 */
static
mapent_t *_loadmap(mapent_t *propmap, SV *mapref, size_t *mapsiz)
{
    size_t n;
    AV * map;
    AV * ent;
    SV ** pp;
    IV p;

    if (propmap)
	free(propmap);
    map = (AV *)SvRV(mapref);
    *mapsiz = av_len(map) + 1;
    if (*mapsiz <= 0) {
	*mapsiz = 0;
	propmap = NULL;
    } else if ((propmap = malloc(sizeof(mapent_t) * (*mapsiz))) == NULL) {
	*mapsiz = 0;
	propmap = NULL;
	croak("_loadmap: Can't allocate memory");
    } else {
	for (n = 0; n < *mapsiz; n++) {
	    ent = (AV *)SvRV(*av_fetch(map, n, 0));
	    propmap[n].beg = SvUV(*av_fetch(ent, 0, 0));
	    propmap[n].end = SvUV(*av_fetch(ent, 1, 0));
	    if ((pp = av_fetch(ent, 2, 0)) == NULL || (p = SvIV(*pp)) < 0)
		propmap[n].lbc = PROP_UNKNOWN;
	    else
		propmap[n].lbc = (propval_t)p;
	    if ((pp = av_fetch(ent, 3, 0)) == NULL || (p = SvIV(*pp)) < 0)
		propmap[n].eaw = PROP_UNKNOWN;
	    else
		propmap[n].eaw = (propval_t)p;
	    propmap[n].gbc = PROP_UNKNOWN;
	    propmap[n].scr = PROP_UNKNOWN;
	}
    }
    return propmap;
}

/***
 *** Data conversion.
 ***/

/*
 * Create Unicode string from Perl utf8-flagged string.
 */
static
unistr_t *SVtounistr(unistr_t *buf, SV *str)
{
    U8 *utf8, *utf8ptr;
    STRLEN utf8len, unilen, len;
    unichar_t *uniptr;

    if (!buf) {
	if ((buf = malloc(sizeof(unistr_t))) == NULL)
	    croak("SVtounistr: Can't allocate memory");
    } else if (buf->str)
	free(buf->str);
    buf->str = NULL;
    buf->len = 0;

    if (SvOK(str)) /* prevent segfault. */
	utf8len = SvCUR(str);
    else
	return buf;
    if (utf8len <= 0)
	return buf;
    utf8 = (U8 *)SvPV(str, utf8len);
    unilen = utf8_length(utf8, utf8 + utf8len);
    if ((buf->str = (unichar_t *)malloc(sizeof(unichar_t) * unilen)) == NULL)
	croak("SVtounistr: Can't allocate memory");

    utf8ptr = utf8;
    uniptr = buf->str;
    while (utf8ptr < utf8 + utf8len) {
	*uniptr = (unichar_t)utf8_to_uvuni(utf8ptr, &len);
	if (len < 0)
	    croak("SVtounistr: Not well-formed UTF-8");
	if (len == 0)
	    croak("SVtounistr: Internal error");
	utf8ptr += len;
	uniptr++;
    }
    buf->len = unilen;
    return buf;
}

/*
 * Create Perl utf8-flagged string from Unicode string.
 */
static
SV *unistrtoSV(unistr_t *unistr, size_t uniidx, size_t unilen)
{
    U8 *buf = NULL, *newbuf;
    STRLEN utf8len;
    unichar_t *uniptr;
    SV *utf8;

    if (unistr == NULL || unistr->str == NULL || unilen == 0) {
	utf8 = newSVpvn("", 0);
	SvUTF8_on(utf8);
	return utf8;
    }

    utf8len = 0;
    uniptr = unistr->str + uniidx;
    while (uniptr < unistr->str + uniidx + unilen &&
	   uniptr < unistr->str + unistr->len) {
        if ((newbuf = realloc(buf,
                              sizeof(U8) * (utf8len + UTF8_MAXBYTES + 1)))
            == NULL) {
            croak("unistrtoSV: Can't allocate memory");
        }
        buf = newbuf;
        utf8len = uvuni_to_utf8(buf + utf8len, *uniptr) - buf;
        uniptr++;
    }

    utf8 = newSVpvn((char *)(void *)buf, utf8len);
    SvUTF8_on(utf8);
    free(buf);
    return utf8;
}

/*
 * Convert Perl object to C object
 */
#define PerltoC(type, self) \
    ((type)SvIV(SvRV(self)))

/*
 * Create Perl object from C object
 */
static
SV *CtoPerl(char *klass, void *obj)
{
    SV *ref, *rv;

    ref = newSViv(0);
    rv = newSVrv(ref, klass);
    sv_setiv(rv, (IV)obj);
#if 0
    SvREADONLY_on(rv); /* FIXME:Can't bless derived class */
#endif /* 0 */
    return ref;
}

/*
 * Convert Perl utf8-flagged string to grapheme cluster string.
 */
static
gcstring_t *SVtogcstring(SV *sv, linebreak_t *lbobj)
{
    unistr_t unistr = {0, 0};

    if (!sv_isobject(sv)) {
	SVtounistr(&unistr, sv);
	return gcstring_new(&unistr, lbobj);
    } else if (sv_derived_from(sv, "Unicode::GCString"))
	return PerltoC(gcstring_t *, sv);
    else
	croak("Unknown object %s", HvNAME(SvSTASH(SvRV(sv))));
}

/*
 * Convert Perl SV to boolean (n.b. string "YES" means true).
 */
static
int SVtoboolean(SV *sv)
{
    char *str;

    if (!sv || !SvOK(sv))
	return 0;
    if (SvPOK(sv))
	return strcasecmp((str = SvPV_nolen(sv)), "YES") == 0 ||
	    atof(str) != 0.0;
    return SvNV(sv) != 0.0;
}

/*
 * Create grapheme cluster string with single grapheme cluster.
 */
static
gcstring_t *gctogcstring(gcstring_t *gcstr, gcchar_t *gc)
{
    size_t offset;

    if (gc == NULL)
	return NULL;
    offset = gc - gcstr->gcstr;
    return gcstring_substr(gcstr, offset, 1, NULL);
}

/***
 *** Callbacs for linebreak library.
 ***/

/*
 * Increment/decrement reference count
 */
void refcount(SV *sv, int datatype, int d)
{
    if (0 < d)
	SvREFCNT_inc(sv);
    else if (d < 0)
	SvREFCNT_dec(sv);
}

/*
 * Call preprocess (user breaking) function
 */
static
gcstring_t *user_func(linebreak_t *lbobj, gcstring_t *str)
{
    SV *sv;
    int count;
    gcstring_t *ret;

    dSP;
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    /* FIXME:sync refcount between C & Perl */
    XPUSHs(sv_2mortal(CtoPerl("Unicode::LineBreak", linebreak_copy(lbobj))));
    XPUSHs((SV *)lbobj->user_data); /* shouldn't be mortal. */
    XPUSHs(sv_2mortal(CtoPerl("Unicode::GCString", gcstring_copy(str))));
    PUTBACK;
    count = call_pv("Unicode::LineBreak::preprocess", G_SCALAR | G_EVAL);

    SPAGAIN;
    if (SvTRUE(ERRSV)) {
	warn("%s", SvPV_nolen(ERRSV));
	POPs;
	return NULL;
    } else if (count != 1)
	croak("user_func: internal error");
    else
	sv = POPs; /* note that return value is mortal. */
    ret = SVtogcstring(sv, lbobj);
    if (sv_isobject(sv))
	ret = gcstring_copy(ret);

    PUTBACK;
    FREETMPS;
    LEAVE;

    return ret;
}

/*
 * Call format function
 */
static
char *linebreak_states[] = {
    NULL, "sot", "sop", "sol", "", "eol", "eop", "eot", NULL
};
static
gcstring_t *format_func(linebreak_t *lbobj, linebreak_state_t action,
			gcstring_t *str)
{
    SV *sv;
    char *actionstr;
    int count;
    gcstring_t *ret;

    dSP;
    if (action <= LINEBREAK_STATE_NONE || LINEBREAK_STATE_MAX <= action)
	return NULL;
    actionstr = linebreak_states[(size_t)action];
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    XPUSHs(sv_2mortal(CtoPerl("Unicode::LineBreak", linebreak_copy(lbobj))));
    XPUSHs(sv_2mortal(newSVpv(actionstr, 0)));
    XPUSHs(sv_2mortal(CtoPerl("Unicode::GCString", gcstring_copy(str))));
    PUTBACK;
    count = call_sv(lbobj->format_data, G_SCALAR | G_EVAL);

    SPAGAIN;
    if (SvTRUE(ERRSV)) {
	warn("%s", SvPV_nolen(ERRSV));
	POPs;
	return NULL;
    } else if (count != 1)
	croak("format_func: internal error");
    else
	sv = POPs;
    if (!SvOK(sv))
	ret = NULL;
    else
	ret = SVtogcstring(sv, lbobj);
    if (sv_isobject(sv))
	ret = gcstring_copy(ret);

    PUTBACK;
    FREETMPS;
    LEAVE;

    return ret;
}

/*
 * Call sizing function
 */
static
double sizing_func(linebreak_t *lbobj, double len,
		   gcstring_t *pre, gcstring_t *spc, gcstring_t *str,
		   size_t max)
{
    int count;
    double ret;

    dSP;
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    XPUSHs(sv_2mortal(CtoPerl("Unicode::LineBreak", linebreak_copy(lbobj))));
    XPUSHs(sv_2mortal(newSVnv(len))); 
    XPUSHs(sv_2mortal(CtoPerl("Unicode::GCString", gcstring_copy(pre))));
    XPUSHs(sv_2mortal(CtoPerl("Unicode::GCString", gcstring_copy(spc))));
    XPUSHs(sv_2mortal(CtoPerl("Unicode::GCString", gcstring_copy(str))));
    XPUSHs(sv_2mortal(newSViv(max))); 
    PUTBACK;
    count = call_sv(lbobj->sizing_data, G_SCALAR | G_EVAL);

    SPAGAIN;
    if (SvTRUE(ERRSV)) {
	warn("%s", SvPV_nolen(ERRSV));
	POPs;
	return -1;
    } else if (count != 1)
	croak("sizing_func: internal error");
    else
	ret = POPn;

    PUTBACK;
    FREETMPS;
    LEAVE;

    return ret;
}

/*
 * Call urgent breaking function
 */
static
gcstring_t *urgent_func(linebreak_t *lbobj, double cols,
			gcstring_t *pre, gcstring_t *spc, gcstring_t *str)
{
    SV *sv;
    int count;
    size_t i;
    gcstring_t *gcstr, *ret;

    dSP;
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    XPUSHs(sv_2mortal(CtoPerl("Unicode::LineBreak", linebreak_copy(lbobj))));
    XPUSHs(sv_2mortal(newSVnv(cols)));
    XPUSHs(sv_2mortal(CtoPerl("Unicode::GCString", gcstring_copy(pre))));
    XPUSHs(sv_2mortal(CtoPerl("Unicode::GCString", gcstring_copy(spc))));
    XPUSHs(sv_2mortal(CtoPerl("Unicode::GCString", gcstring_copy(str))));
    PUTBACK;
    count = call_sv(lbobj->urgent_data, G_ARRAY | G_EVAL);

    SPAGAIN;
    if (SvTRUE(ERRSV)) {
	warn("%s", SvPV_nolen(ERRSV));
	return NULL;
    } if (count == 0)
	return NULL;

    ret = gcstring_new(NULL, lbobj);
    for (i = count; i; i--) {
	sv = POPs;
	if (SvOK(sv)) {
	    gcstr = SVtogcstring(sv, lbobj);
	    if (gcstr->gclen)
		gcstr->gcstr[0].flag = LINEBREAK_FLAG_BREAK_BEFORE;
	    gcstring_destroy(gcstring_substr(ret, 0, 0, gcstr));
	    if (!sv_isobject(sv))
		gcstring_destroy(gcstr);
	}
    }

    PUTBACK;
    FREETMPS;
    LEAVE;

    return ret;
}


MODULE = Unicode::LineBreak	PACKAGE = Unicode::LineBreak	

SV *
_new(klass)
	char *klass;
    PROTOTYPE: $
    INIT:
	linebreak_t *lbobj;
    CODE:
	if ((lbobj = linebreak_new()) == NULL)
	    croak("%s->_new: Can't allocate memory", klass);
	RETVAL = CtoPerl(klass, lbobj);
    OUTPUT:
	RETVAL

SV *
copy(self)
	SV *self;
    PROTOTYPE: $
    INIT:
	linebreak_t *lbobj, *ret;
    CODE:
	if (!sv_isobject(self))
	    XSRETURN_UNDEF;
	lbobj = PerltoC(linebreak_t *, self);    
	ret = linebreak_copy(lbobj);
	RETVAL = CtoPerl("Unicode::LineBreak", ret);
    OUTPUT:
	RETVAL

void
DESTROY(self)
	SV *self;
    PROTOTYPE: $
    CODE:
	linebreak_destroy(PerltoC(linebreak_t *, self));

SV *
_config(self, ...)
	SV *self;
    INIT:
	linebreak_t *obj;
	size_t i;
	char *key;
	SV *val;
	size_t mapsiz;
	char *opt;
    CODE:
	if ((obj = PerltoC(linebreak_t *, self)) == NULL) {
	    if ((obj = linebreak_new()) == NULL)
		croak("_config: Can't allocate memory");
	}

	RETVAL = NULL;
	if (items < 2)
	    croak("_config: Too few arguments");
	else if (items < 3) {
	    key = (char *)SvPV_nolen(ST(1));

	    if (strcasecmp(key, "CharactersMax") == 0)
		RETVAL = newSVuv(obj->charmax);
	    else if (strcasecmp(key, "ColumnsMax") == 0)
		RETVAL = newSVnv((NV)obj->colmax);
	    else if (strcasecmp(key, "ColumnsMin") == 0)
		RETVAL = newSVnv((NV)obj->colmin);
	    else if (strcasecmp(key, "Context") == 0) {
		if (obj->options & LINEBREAK_OPTION_EASTASIAN_CONTEXT)
		    RETVAL = newSVpvn("EASTASIAN", 9);
		else
		    RETVAL = newSVpvn("NONEASTASIAN", 12);
	    } else if (strcasecmp(key, "HangulAsAL") == 0)
		RETVAL = newSVuv(obj->options & LINEBREAK_OPTION_HANGUL_AS_AL);
	    else if (strcasecmp(key, "LegacyCM") == 0)
		RETVAL = newSVuv(obj->options & LINEBREAK_OPTION_LEGACY_CM);
	    else if (strcasecmp(key, "Newline") == 0) {
		unistr_t unistr = {obj->newline, obj->newlinesiz};
		if (obj->newline == NULL || obj->newlinesiz == 0)
		    RETVAL = unistrtoSV(&unistr, 0, 0);
		else
		    RETVAL = unistrtoSV(&unistr, 0, obj->newlinesiz);
	    } else {
		warn("_config: Getting unknown option %s", key);
		XSRETURN_UNDEF;
	    }
	} else if (!(items % 2))
	    croak("_config: Argument size mismatch");
	else for (RETVAL = NULL, i = 1; i < items; i += 2) {
	    if (!SvPOK(ST(i)))
		croak("_config: Illegal argument");
	    key = (char *)SvPV_nolen(ST(i));
	    val = ST(i + 1);

	    if (strcmp(key, "UserBreaking") == 0) {
		if (obj->user_data)
		    refcount(obj->user_data, LINEBREAK_REF_USER, -1);
		if (SvOK(val)) {
		    obj->user_data = (void *)val;
		    obj->user_func = user_func;
		    refcount(val, LINEBREAK_REF_USER, +1);
		} else {
		    obj->user_data = NULL;
		    obj->user_func = NULL;
		}
	    } else if (strcmp(key, "Format") == 0) {
		if (obj->format_data)
		    refcount(obj->format_data, LINEBREAK_REF_FORMAT, -1);
		if (SvOK(val)) {
		    obj->format_data = (void *)val;
		    obj->format_func = format_func;
		    refcount(val, LINEBREAK_REF_FORMAT, +1);
		} else {
		    obj->format_data = NULL;
		    obj->format_func = NULL;
		}
	    } else if (strcmp(key, "SizingMethod") == 0) {
		if (obj->sizing_data)
		    refcount((SV *)obj->sizing_data, LINEBREAK_REF_SIZING, -1);
		if (SvOK(val)) {
		    obj->sizing_data = (void *)val;
		    obj->sizing_func = sizing_func;
		    refcount(val, LINEBREAK_REF_SIZING, +1);
		} else {
		    obj->sizing_data = NULL;
		    obj->sizing_func = NULL;
		}
	    } else if (strcmp(key, "UrgentBreaking") == 0) {
		if (obj->urgent_data)
		    refcount(obj->urgent_data, LINEBREAK_REF_URGENT, -1);
		if (SvOK(val)) {
		    obj->urgent_data = (void *)val;
		    obj->urgent_func = urgent_func;
		    refcount(val, LINEBREAK_REF_URGENT, +1);
		} else {
		    obj->urgent_data = NULL;
		    obj->urgent_func = NULL;
		}
	    } else if (strcmp(key, "_map") == 0) {
		if (obj->map) {
		    free(obj->map);
		    obj->map = NULL;
		    obj->mapsiz = 0;
		}
		if (SvOK(val)) {
		    obj->map = _loadmap(obj->map, val, &mapsiz);
		    obj->mapsiz = mapsiz;
		}
	    } else if (strcasecmp(key, "CharactersMax") == 0)
		obj->charmax = SvUV(val);
	    else if (strcasecmp(key, "ColumnsMax") == 0)
		obj->colmax = (double)SvNV(val);
	    else if (strcasecmp(key, "ColumnsMin") == 0)
		obj->colmin = (double)SvNV(val);
	    else if (strcasecmp(key, "Context") == 0) {
		if (SvOK(val))
		    opt = (char *)SvPV_nolen(val);
		else
		    opt = NULL;
		if (opt && strcasecmp(opt, "EASTASIAN") == 0)
		    obj->options |= LINEBREAK_OPTION_EASTASIAN_CONTEXT;
		else
		    obj->options &= ~LINEBREAK_OPTION_EASTASIAN_CONTEXT;
	    } else if (strcasecmp(key, "HangulAsAL") == 0) {
		if (SVtoboolean(val))
		    obj->options |= LINEBREAK_OPTION_HANGUL_AS_AL;
		else
		    obj->options &= ~LINEBREAK_OPTION_HANGUL_AS_AL;
	    } else if (strcasecmp(key, "LegacyCM") == 0) {
		if (SVtoboolean(val))
		    obj->options |= LINEBREAK_OPTION_LEGACY_CM;
		else
		    obj->options &= ~LINEBREAK_OPTION_LEGACY_CM;
	    } else if (strcasecmp(key, "Newline") == 0) {
		if (obj->newline) free(obj->newline);
		if (!sv_isobject(val)) {
		    unistr_t unistr = {0, 0};
		    SVtounistr(&unistr, val);
		    obj->newline = unistr.str;
		    obj->newlinesiz = unistr.len;
		} else if (sv_derived_from(val, "Unicode::GCString")) {
	            gcstring_t *gcstr = PerltoC(gcstring_t *, val);
		    if ((obj->newline =
			malloc(sizeof(unichar_t) * gcstr->len)) == NULL)
			croak("_config: Can't allocate memory");
		    else {
			memcpy(obj->newline, gcstr->str,
			       sizeof(unichar_t) * gcstr->len);
			obj->newlinesiz = gcstr->len;
		    }
		} else
		    croak("Unknown object %s", HvNAME(SvSTASH(SvRV(val))));
	    }
	    else
		warn("_config: Setting unknown option %s", key);
	}
    OUTPUT:
	RETVAL

SV*
as_hashref(self, ...)
	SV *self;
    INIT:
	linebreak_t *obj;
    CODE:
	obj = PerltoC(linebreak_t *, self);
	if (obj->stash == NULL)
	    obj->stash = newRV_noinc((SV *)newHV());
	RETVAL = obj->stash;
	if (RETVAL == NULL)
	    XSRETURN_UNDEF;
	if (SvROK(RETVAL)) /* FIXME */
	    refcount((SV*)RETVAL, LINEBREAK_REF_STASH, +1);
    OUTPUT:
	RETVAL

SV*
as_scalarref(self, ...)
	SV *self;
    INIT:
	linebreak_t *obj;
	char buf[64];
    CODE:
	obj = PerltoC(linebreak_t *, self);
	buf[0] = '\0';
	snprintf(buf, 64, "%s(0x%lx)", HvNAME(SvSTASH(SvRV(self))),
		 (unsigned long)(void *)obj);
	RETVAL = newRV_noinc(newSVpv(buf, 0));
    OUTPUT:
	RETVAL

SV *
as_string(self, ...)
	SV *self;
    INIT:
	linebreak_t *obj;
	char buf[64];
    CODE:
	obj = PerltoC(linebreak_t *, self);
	buf[0] = '\0';
	snprintf(buf, 64, "%s(0x%lx)", HvNAME(SvSTASH(SvRV(self))),
		 (unsigned long)(void *)obj);
	RETVAL = newSVpv(buf, 0);
    OUTPUT:
	RETVAL

propval_t
eawidth(self, str)
	SV *self;
	SV *str;
    PROTOTYPE: $$
    INIT:
	linebreak_t *obj;
	unichar_t c;
	propval_t prop;
	gcstring_t *gcstr;
    CODE:
	obj = PerltoC(linebreak_t *, self);
	if (!sv_isobject(str)) {
	    if (!SvCUR(str))
		XSRETURN_UNDEF;
	    c = utf8_to_uvuni((U8 *)SvPV_nolen(str), NULL);
	}
	else if (sv_derived_from(str, "Unicode::GCString")) {
	    gcstr = PerltoC(gcstring_t *, str);
	    if (!gcstr->len)
		XSRETURN_UNDEF;
	    else
		c = gcstr->str[0];
	}
	else
	    croak("Unknown object %s", HvNAME(SvSTASH(SvRV(str))));
	prop = linebreak_eawidth(obj, c);
	if (prop == PROP_UNKNOWN)
	    XSRETURN_UNDEF;
	RETVAL = prop;	
    OUTPUT:
	RETVAL

propval_t
lbclass(self, str)
	SV *self;
	SV *str;
    PROTOTYPE: $$
    INIT:
	linebreak_t *obj;
	unichar_t c;
	propval_t prop;
	gcstring_t *gcstr;
    CODE:
	obj = PerltoC(linebreak_t *, self);
	if (!sv_isobject(str)) {
	    if (!SvCUR(str))
		XSRETURN_UNDEF;
	    c = utf8_to_uvuni((U8 *)SvPV_nolen(str), NULL);
	    prop = linebreak_lbclass(obj, c);
	}
	else if (sv_derived_from(str, "Unicode::GCString")) {
	    gcstr = PerltoC(gcstring_t *, str);
	    if (gcstr->gclen)
		prop = gcstr->gcstr[gcstr->pos].lbc;
	    else
		prop = PROP_UNKNOWN;
	}
	else
	    croak("Unknown object %s", HvNAME(SvSTASH(SvRV(str))));
	if (prop == PROP_UNKNOWN)
	    XSRETURN_UNDEF;
	RETVAL = prop;	
    OUTPUT:
	RETVAL

propval_t
lbrule(self, b_idx, a_idx)
	SV *self;
	propval_t b_idx;
	propval_t a_idx;
    PROTOTYPE: $$$
    INIT:
	linebreak_t *obj;
	propval_t prop;
    CODE:
	if (!SvOK(ST(1)) || !SvOK(ST(2)))
	    XSRETURN_UNDEF;
	obj = PerltoC(linebreak_t *, self);
	prop = linebreak_lbrule(b_idx, a_idx);

	if (prop == PROP_UNKNOWN)
	    XSRETURN_UNDEF;
	RETVAL = prop;
    OUTPUT:
	RETVAL

void
reset(self)
	SV *self;
    PROTOTYPE: $
    CODE:
	linebreak_reset(PerltoC(linebreak_t *, self));

double
strsize(self, len, pre, spc, str, ...)
	SV *self;
	double len;
	SV *pre;
	SV *spc;
	SV *str;
    PROTOTYPE: $$$$$;$
    INIT:
	linebreak_t *lbobj;
	gcstring_t /* *gcpre, */ *gcspc, *gcstr;
	size_t max;
    CODE:
	lbobj = PerltoC(linebreak_t *, self);
	/* gcpre = SVtogcstring(pre, lbobj); */
	gcspc = SVtogcstring(spc, lbobj);
	gcstr = SVtogcstring(str, lbobj);

	if (5 < items)
	    max = SvUV(ST(5));
	else
	    max = 0;

	RETVAL = linebreak_strsize(lbobj, len, /* gcpre */NULL, gcspc, gcstr,
				   max);

	/* if (!sv_isobject(pre))
	    gcstring_destroy(gcpre); */
	if (!sv_isobject(spc))
	    gcstring_destroy(gcspc);
	if (!sv_isobject(str))
	    gcstring_destroy(gcstr);
	if (RETVAL == -1)
	    croak("strsize: Can't allocate memory");
    OUTPUT:
	RETVAL

SV *
break_partial(self, input)
	SV *self;
	SV *input;
    PROTOTYPE: $$
    INIT:
	linebreak_t *lbobj;
	gcstring_t *gcstr, *ret;
	unistr_t unistr;
    CODE:
	lbobj = PerltoC(linebreak_t *, self);
	if (!SvOK(input))
	    gcstr = NULL;
	else {
	    if (!sv_isobject(input) && !SvUTF8(input)) {
		char *s;
		size_t len, i;
		len = SvCUR(input);
		s = SvPV(input, len);
		for (i = 0; i < len; i++)
		    if (127 < (unsigned char)s[i])
			croak("Unicode string must be given.");
	    }
	    gcstr = SVtogcstring(input, lbobj);
	}

	ret = linebreak_break_partial(lbobj, gcstr);
	if (!sv_isobject(input) && gcstr)
	    gcstring_destroy(gcstr);
	if (ret == NULL)
	    croak("%s", strerror(errno));

	unistr.str = ret->str;
	unistr.len = ret->len;
	RETVAL = unistrtoSV(&unistr, 0, ret->len);
	gcstring_destroy(ret);
    OUTPUT:
	RETVAL

const char *
UNICODE_VERSION()
    CODE:
	RETVAL = linebreak_unicode_version;
    OUTPUT:
	RETVAL


MODULE = Unicode::LineBreak	PACKAGE = Unicode::LineBreak::SouthEastAsian

const char *
supported()
    PROTOTYPE:
    CODE:
	RETVAL = linebreak_southeastasian_supported;
	if (RETVAL == NULL)
	    XSRETURN_UNDEF;
    OUTPUT:
	RETVAL

MODULE = Unicode::LineBreak	PACKAGE = Unicode::GCString	

SV *
new(klass, str, ...)
	char *klass;
	SV *str;
    PROTOTYPE: $$;$
    INIT:
	gcstring_t *gcstr;
	linebreak_t *lbobj;
	unistr_t unistr = {0, 0};
    CODE:
	if (!SvOK(str)) /* prevent segfault. */
	    XSRETURN_UNDEF;
	if (2 < items)
	    lbobj = PerltoC(linebreak_t *, ST(2));
	else
	    lbobj = NULL;
	SVtounistr(&unistr, str);
	if ((gcstr = gcstring_new(&unistr, lbobj)) == NULL)
	    croak("%s->new: Can't allocate memory", klass);
	RETVAL = CtoPerl(klass, gcstr);
    OUTPUT:
	RETVAL

void
DESTROY(self)
	SV *self;
    PROTOTYPE: $
    CODE:
	gcstring_destroy(PerltoC(gcstring_t *, self));

void
as_array(self)
	SV *self;
    PROTOTYPE: $
    INIT:
	gcstring_t *gcstr;
	size_t i;
    PPCODE:
	if (!sv_isobject(self))
	    return;
	gcstr = PerltoC(gcstring_t *, self);    
	if (gcstr != NULL)
	    for (i = 0; i < gcstr->gclen; i++)
		XPUSHs(sv_2mortal(
			   CtoPerl("Unicode::GCString", 
				   gctogcstring(gcstr, gcstr->gcstr + i))));

SV*
as_scalarref(self, ...)
	SV *self;
    INIT:
	linebreak_t *obj;
	char buf[64];
    CODE:
	obj = PerltoC(linebreak_t *, self);
	buf[0] = '\0';
	snprintf(buf, 64, "%s(0x%lx)", HvNAME(SvSTASH(SvRV(self))),
		 (unsigned long)(void *)obj);
	RETVAL = newRV_noinc(newSVpv(buf, 0));
    OUTPUT:
	RETVAL

SV *
as_string(self, ...)
	SV *self;
    PROTOTYPE: $;$;$
    INIT:
	gcstring_t *gcstr;
	unistr_t unistr = {0, 0};
    CODE:
	if (!sv_isobject(self))
	    XSRETURN_UNDEF;
	gcstr = PerltoC(gcstring_t *, self);    
	if (gcstr == NULL)
	    RETVAL = unistrtoSV(&unistr, 0, 0);
	else
	    RETVAL = unistrtoSV((unistr_t *)gcstr, 0, gcstr->len);
    OUTPUT:
	RETVAL

size_t
chars(self)
	SV *self;
    PROTOTYPE: $
    INIT:
	gcstring_t *gcstr;
    CODE:
	if (!sv_isobject(self))
	    XSRETURN_UNDEF;
	gcstr = PerltoC(gcstring_t *, self);    
	if (gcstr == NULL)
	    RETVAL = 0;
	else
	    RETVAL = gcstr->len;
    OUTPUT:
	RETVAL

int
cmp(self, str, ...)
	SV *self;
	SV *str;
    PROTOTYPE: $$;$
    INIT:
	gcstring_t *gcstr1, *gcstr2 = NULL;
	int ret;
    CODE:
	if (!sv_isobject(self))
	    XSRETURN_UNDEF;
	gcstr1 = PerltoC(gcstring_t *, self);    
	gcstr2 = SVtogcstring(str, gcstr1->lbobj);
	if (2 < items && SvOK(ST(2)) && SvIV(ST(2)))
	    ret = gcstring_cmp(gcstr2, gcstr1);
	else
	    ret = gcstring_cmp(gcstr1, gcstr2);
	if (!sv_isobject(str))
	    gcstring_destroy(gcstr2);
	RETVAL = ret;
    OUTPUT:
	RETVAL

size_t
columns(self)
	SV *self;
    INIT:
	gcstring_t *gcstr;
    CODE:
	if (!sv_isobject(self))
	    XSRETURN_UNDEF;
	gcstr = PerltoC(gcstring_t *, self);    
	if (gcstr == NULL)
	    RETVAL = 0;
	else
	    RETVAL = gcstring_columns(gcstr);
    OUTPUT:
	RETVAL

SV *
concat(self, str, ...)
	SV *self;
	SV *str;
    PROTOTYPE: $$;$
    INIT:
	gcstring_t *gcstr, *appe, *ret;
    CODE:
	if (!sv_isobject(self))
	    XSRETURN_UNDEF;
	gcstr = PerltoC(gcstring_t *, self);    
	appe = SVtogcstring(str, gcstr->lbobj);
	if (2 < items && SvOK(ST(2)) && SvIV(ST(2)))
	    ret = gcstring_concat(appe, gcstr);
	else
	    ret = gcstring_concat(gcstr, appe);
	if (!sv_isobject(str))
	    gcstring_destroy(appe);
	RETVAL = CtoPerl("Unicode::GCString", ret);
    OUTPUT:
	RETVAL

SV *
copy(self)
	SV *self;
    PROTOTYPE: $
    INIT:
	gcstring_t *gcstr, *ret;
    CODE:
	if (!sv_isobject(self))
	    XSRETURN_UNDEF;
	gcstr = PerltoC(gcstring_t *, self);    
	ret = gcstring_copy(gcstr);
	RETVAL = CtoPerl("Unicode::GCString", ret);
    OUTPUT:
	RETVAL

int
eos(self)
	SV *self;
    INIT:
	gcstring_t *gcstr;
    CODE:
	if (!sv_isobject(self))
	    XSRETURN_UNDEF;
	gcstr = PerltoC(gcstring_t *, self);    
	if (gcstr == NULL)
	    RETVAL = 0;
	else
	    RETVAL = gcstring_eos(gcstr);
    OUTPUT:
	RETVAL

unsigned int
flag(self, ...)
	SV *self;
    PROTOTYPE: $;$;$
    INIT:
	int i;
	unsigned int flag;
	gcstring_t *gcstr;
    CODE:
	if (!sv_isobject(self))
	    XSRETURN_UNDEF;
	gcstr = PerltoC(gcstring_t *, self);    
	if (1 < items)
	    i = SvIV(ST(1));
	else
	    i = gcstr->pos;
	if (i < 0 || gcstr == NULL || gcstr->gclen <= i)
	    XSRETURN_UNDEF;
	if (2 < items) {
	    flag = SvUV(ST(2));
	    if (flag == (flag & 255))
		gcstr->gcstr[i].flag = (unsigned char)flag;
	    else
		warn("flag: unknown flag(s)");
	}
	RETVAL = (unsigned int)gcstr->gcstr[i].flag;
    OUTPUT:
	RETVAL

SV *
item(self, ...)
	SV *self;
    PROTOTYPE: $;$
    INIT:
	int i;
	gcstring_t *gcstr;
    CODE:
	if (!sv_isobject(self))
	    XSRETURN_UNDEF;
	gcstr = PerltoC(gcstring_t *, self);    
	if (1 < items)
	    i = SvIV(ST(1));
	else
	    i = gcstr->pos;
	if (i < 0 || gcstr == NULL || gcstr->gclen <= i)
	    XSRETURN_UNDEF;

	RETVAL = CtoPerl("Unicode::GCString",
			 gctogcstring(gcstr, gcstr->gcstr + i));
    OUTPUT:
	RETVAL

propval_t
lbclass(self, ...)
	SV *self;
    PROTOTYPE: $;$
    INIT:
	int i;
	gcstring_t *gcstr;
    CODE:
	if (!sv_isobject(self))
	    XSRETURN_UNDEF;
	gcstr = PerltoC(gcstring_t *, self);    
	if (1 < items)
	    i = SvIV(ST(1));
	else
	    i = gcstr->pos;
	if (i < 0 || gcstr == NULL || gcstr->gclen <= i)
	    XSRETURN_UNDEF;
	RETVAL = (propval_t)gcstr->gcstr[i].lbc;
    OUTPUT:
	RETVAL

size_t
length(self)
	SV *self;
    PROTOTYPE: $
    INIT:
	gcstring_t *gcstr;
    CODE:
	if (!sv_isobject(self))
	    XSRETURN_UNDEF;
	gcstr = PerltoC(gcstring_t *, self);    
	if (gcstr == NULL)
	    RETVAL = 0;
	else
	    RETVAL = gcstr->gclen;
    OUTPUT:
	RETVAL

SV *
next(self, ...)
	SV *self;
    PROTOTYPE: $;$;$
    INIT:
	gcstring_t *gcstr;
	gcchar_t *gc;
    CODE:
	if (!sv_isobject(self))
	    XSRETURN_UNDEF;
	gcstr = PerltoC(gcstring_t *, self);    
	if (gcstring_eos(gcstr))
	    XSRETURN_UNDEF;
	gc = gcstring_next(gcstr);
	RETVAL = CtoPerl("Unicode::GCString", gctogcstring(gcstr, gc));
    OUTPUT:
	RETVAL

size_t
pos(self, ...)
	SV *self;
    PROTOTYPE: $;$
    INIT:
	gcstring_t *gcstr;
    CODE:
	if (!sv_isobject(self))
	    XSRETURN_UNDEF;
	gcstr = PerltoC(gcstring_t *, self);    
	
	if (gcstr == NULL)
	    RETVAL = 0;
	else {
	    if (1 < items)
		gcstring_setpos(gcstr, SvIV(ST(1)));
	    RETVAL = gcstr->pos;
	}
    OUTPUT:
	RETVAL

SV *
substr(self, offset, ...)
	SV *self;
	int offset;
    PROTOTYPE: $$;$;$
    INIT:
	int length;
	gcstring_t *gcstr, *replacement, *ret;
    CODE:
	if (!sv_isobject(self))
	    XSRETURN_UNDEF;
	gcstr = PerltoC(gcstring_t *, self);    
	if (2 < items)
	    length = SvIV(ST(2));
	else
	    length = gcstr->gclen;
        if (3 < items) {
	    replacement = SVtogcstring(ST(3), gcstr->lbobj);
        } else
            replacement = NULL;

	ret = gcstring_substr(gcstr, offset, length, replacement);
        if (3 < items && !sv_isobject(ST(3)))
            gcstring_destroy(replacement);
	if (ret == NULL)
	    croak("%s", strerror(errno));
	RETVAL = CtoPerl("Unicode::GCString", ret);
    OUTPUT:
	RETVAL
