/*
 * LineBreak.xs - Perl XS glue for Sombok package.
 * 
 * Copyright (C) 2009-2011 Hatuka*nezumi - IKEDA Soji <hatuka(at)nezumi.nu>.
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
#include "sombok.h"

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

    if (buf == NULL) {
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
	if (len < 0) {
	    free(buf->str);
	    buf->str = NULL;
	    buf->len = 0;
	    croak("SVtounistr: Not well-formed UTF-8");
	}
	if (len == 0) {
	    free(buf->str);
	    buf->str = NULL;
	    buf->len = 0;
	    croak("SVtounistr: Internal error");
	}
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
			      sizeof(U8) * (utf8len + UTF8_MAXLEN + 1)))
	    == NULL) {
	    free(buf);
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
 * Convert Perl utf8-flagged string (GCString) to grapheme cluster string.
 */
static
gcstring_t *SVtogcstring(SV *sv, linebreak_t *lbobj)
{
    unistr_t unistr = {NULL, 0};

    if (!sv_isobject(sv)) {
	SVtounistr(&unistr, sv);
	return gcstring_new(&unistr, lbobj);
    } else if (sv_derived_from(sv, "Unicode::GCString"))
	return PerltoC(gcstring_t *, sv);
    else
	croak("Unknown object %s", HvNAME(SvSTASH(SvRV(sv))));
}

/*
 * Convert Perl LineBreak object to C linebreak object.
 */
static
linebreak_t *SVtolinebreak(SV *sv)
{
    if (!sv_isobject(sv))
	croak("Not object");
    else if (sv_derived_from(sv, "Unicode::LineBreak"))
	return PerltoC(linebreak_t *, sv);
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
    return gcstring_substr(gcstr, offset, 1);
}

/***
 *** Other utilities
 ***/

/*
 * Do regex match once then returns offset and length.
 */
void do_pregexec_once(REGEXP *rx, unistr_t *str)
{
    SV *screamer;
    char *str_arg, *str_beg, *str_end;

    screamer = sv_2mortal(unistrtoSV(str, 0, str->len));
    str_beg = str_arg = SvPVX(screamer);
    str_end = SvEND(screamer);

    if (pregexec(rx, str_arg, str_end, str_beg, 0, screamer, 1)) {
	size_t offs_beg, offs_end;
#if PERL_VERSION >= 11
	offs_beg = ((regexp *)SvANY(rx))->offs[0].start;
	offs_end = ((regexp *)SvANY(rx))->offs[0].end;
#elif ((PERL_VERSION >= 10) || (PERL_VERSION == 9 && PERL_SUBVERSION >= 5))
	offs_beg = rx->offs[0].start;
	offs_end = rx->offs[0].end;
#else /* PERL_VERSION */
	offs_beg = rx->startp[0];
	offs_end = rx->endp[0];
#endif
	str->str += utf8_length(str_beg, str_beg + offs_beg);	
	str->len = utf8_length(str_beg + offs_beg, str_beg + offs_end);
    } else
	str->str = NULL;
}

/***
 *** Callbacks for Sombok library.
 ***/

/*
 * Increment/decrement reference count
 */
void ref_func(SV *sv, int datatype, int d)
{
    if (sv == NULL)
	return;
    if (0 < d)
	SvREFCNT_inc(sv);
    else if (d < 0)
	SvREFCNT_dec(sv);
}

/*
 * Call preprocessing function
 */
static
gcstring_t *prep_func(linebreak_t *lbobj, void *dataref, unistr_t *str,
		      unistr_t *text)
{
    AV *data;
    SV *sv, **pp, *func = NULL;
    REGEXP *rx = NULL;
    int count, i, j;
    gcstring_t *gcstr, *ret;

    if (dataref == NULL ||
	(data = (AV *)SvRV((SV *)dataref)) == NULL)
	return (lbobj->errnum = EINVAL), NULL;

    /* Pass I */

    if ((pp = av_fetch(data, 0, 0)) == NULL ||
	! SvROK(*pp) || ! SvMAGICAL(sv = SvRV(*pp)) ||
	(rx = (REGEXP *)(mg_find(sv, PERL_MAGIC_qr))->mg_obj) == NULL)
	return (lbobj->errnum = EINVAL), NULL;

    if (text != NULL) {
	do_pregexec_once(rx, str);
	return NULL;
    }

    /* Pass II */

    if ((pp = av_fetch(data, 1, 0)) == NULL)
        func = NULL;
    else if (SvOK(*pp))
        func = *pp;
    else
        func = NULL;

    if (func == NULL) {
	if ((ret = gcstring_newcopy(str, lbobj)) == NULL)
	    return (lbobj->errnum = errno ? errno : ENOMEM), NULL;
    } else {
	dSP;
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	/* FIXME:sync refcount between C & Perl */
	XPUSHs(sv_2mortal(CtoPerl("Unicode::LineBreak",
				  linebreak_copy(lbobj))));
	XPUSHs(sv_2mortal(unistrtoSV(str, 0, str->len)));
	PUTBACK;
	count = call_sv(func, G_ARRAY | G_EVAL);

	SPAGAIN;
	if (SvTRUE(ERRSV)) {
	    if (!lbobj->errnum)
		 lbobj->errnum = LINEBREAK_EEXTN;
	    return NULL;
	}

	if ((ret = gcstring_new(NULL, lbobj)) == NULL)
	    return (lbobj->errnum = errno ? errno : ENOMEM), NULL;

	for (i = 0; i < count; i++) {
	    sv = POPs;
	    if (!SvOK(sv))
		continue;
	    gcstr = SVtogcstring(sv, lbobj);

	    for (j = 0; j < gcstr->gclen; j++) {
		if (gcstr->gcstr[j].flag &
		    (LINEBREAK_FLAG_ALLOW_BEFORE |
		     LINEBREAK_FLAG_PROHIBIT_BEFORE))
		    continue;
		if (i < count - 1 && j == 0)
		    gcstr->gcstr[j].flag |= LINEBREAK_FLAG_ALLOW_BEFORE;
		else if (0 < j)
		    gcstr->gcstr[j].flag |= LINEBREAK_FLAG_PROHIBIT_BEFORE;
	    }

	    gcstring_replace(ret, 0, 0, gcstr);
	    if (!sv_isobject(sv))
		gcstring_destroy(gcstr);
	}

	PUTBACK;
	FREETMPS;
	LEAVE;
    }

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
	if (!lbobj->errnum)
	    lbobj->errnum = LINEBREAK_EEXTN;
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
		   gcstring_t *pre, gcstring_t *spc, gcstring_t *str)
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
    PUTBACK;
    count = call_sv(lbobj->sizing_data, G_SCALAR | G_EVAL);

    SPAGAIN;
    if (SvTRUE(ERRSV)) {
	if (!lbobj->errnum)
	    lbobj->errnum = LINEBREAK_EEXTN;
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
gcstring_t *urgent_func(linebreak_t *lbobj, gcstring_t *str)
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
    XPUSHs(sv_2mortal(CtoPerl("Unicode::GCString", gcstring_copy(str))));
    PUTBACK;
    count = call_sv(lbobj->urgent_data, G_ARRAY | G_EVAL);

    SPAGAIN;
    if (SvTRUE(ERRSV)) {
	if (!lbobj->errnum)
	    lbobj->errnum = LINEBREAK_EEXTN;
	return NULL;
    } if (count == 0)
	return NULL;

    ret = gcstring_new(NULL, lbobj);
    for (i = count; i; i--) {
	sv = POPs;
	if (SvOK(sv)) {
	    gcstr = SVtogcstring(sv, lbobj);
	    if (gcstr->gclen)
		gcstr->gcstr[0].flag = LINEBREAK_FLAG_ALLOW_BEFORE;
	    gcstring_replace(ret, 0, 0, gcstr);
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

void
_propvals(prop)
	char *prop;
    PROTOTYPE: $
    INIT:
	char **p;
	extern char *linebreak_propvals_EA[], *linebreak_propvals_GB[],
	    *linebreak_propvals_LB[], *linebreak_propvals_SC[];
    PPCODE:
	if (strcasecmp(prop, "EA") == 0)
	    for (p = linebreak_propvals_EA; *p; p++)
		XPUSHs(sv_2mortal(newSVpv(*p, 0)));
	else if (strcasecmp(prop, "GB") == 0)
	    for (p = linebreak_propvals_GB; *p; p++)
		XPUSHs(sv_2mortal(newSVpv(*p, 0)));
	else if (strcasecmp(prop, "LB") == 0)
	    for (p = linebreak_propvals_LB; *p; p++)
		XPUSHs(sv_2mortal(newSVpv(*p, 0)));
	else if (strcasecmp(prop, "SC") == 0)
	    for (p = linebreak_propvals_SC; *p; p++)
		XPUSHs(sv_2mortal(newSVpv(*p, 0)));
	else
	    croak("_propvals: Unknown property name: %s", prop);

SV *
_new(klass)
	char *klass;
    PROTOTYPE: $
    INIT:
	linebreak_t *lbobj;
    CODE:
	if ((lbobj = linebreak_new(ref_func)) == NULL)
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
	lbobj = SVtolinebreak(self);    
	ret = linebreak_copy(lbobj);
	RETVAL = CtoPerl("Unicode::LineBreak", ret);
    OUTPUT:
	RETVAL

void
DESTROY(self)
	SV *self;
    PROTOTYPE: $
    CODE:
	linebreak_destroy(SVtolinebreak(self));

SV *
_config(self, ...)
	SV *self;
    INIT:
	linebreak_t *lbobj;
	size_t i;
	char *key;
	SV *val;
	size_t mapsiz;
	char *opt;
    CODE:
	if ((lbobj = SVtolinebreak(self)) == NULL)
	    if ((lbobj = linebreak_new()) == NULL)
		croak("_config: Can't allocate memory");

	RETVAL = NULL;
	if (items < 2)
	    croak("_config: Too few arguments");
	else if (items < 3) {
	    key = (char *)SvPV_nolen(ST(1));

	    if (strcasecmp(key, "BreakIndent") == 0)
		RETVAL = newSVuv(lbobj->options &
				 LINEBREAK_OPTION_BREAK_INDENT); 
	    else if (strcasecmp(key, "CharactersMax") == 0)
		RETVAL = newSVuv(lbobj->charmax);
	    else if (strcasecmp(key, "ColumnsMax") == 0)
		RETVAL = newSVnv((NV)lbobj->colmax);
	    else if (strcasecmp(key, "ColumnsMin") == 0)
		RETVAL = newSVnv((NV)lbobj->colmin);
	    else if (strcasecmp(key, "ComplexBreaking") == 0)
		RETVAL = newSVuv(lbobj->options &
				 LINEBREAK_OPTION_COMPLEX_BREAKING);
	    else if (strcasecmp(key, "Context") == 0) {
		if (lbobj->options & LINEBREAK_OPTION_EASTASIAN_CONTEXT)
		    RETVAL = newSVpvn("EASTASIAN", 9);
		else
		    RETVAL = newSVpvn("NONEASTASIAN", 12);
	    } else if (strcasecmp(key, "HangulAsAL") == 0)
		RETVAL = newSVuv(lbobj->options &
				 LINEBREAK_OPTION_HANGUL_AS_AL);
	    else if (strcasecmp(key, "LegacyCM") == 0)
		RETVAL = newSVuv(lbobj->options & LINEBREAK_OPTION_LEGACY_CM);
	    else if (strcasecmp(key, "Newline") == 0) {
		unistr_t unistr = {lbobj->newline.str, lbobj->newline.len};
		if (lbobj->newline.str == NULL || lbobj->newline.len == 0)
		    RETVAL = unistrtoSV(&unistr, 0, 0);
		else
		    RETVAL = unistrtoSV(&unistr, 0, lbobj->newline.len);
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

	    if (strcmp(key, "Prep") == 0) {
		SV *sv, *pattern, *func;
		AV *av;
		PMOP *pm;
		REGEXP *rx;

		if (SvROK(val) && 0 < av_len(av = (AV *)SvRV(val)) + 1) {
		    pattern = *av_fetch(av, 0, 0);
		    if (av_fetch(av, 1, 0) == NULL)
			func = &PL_sv_undef;
		    else
			func = *av_fetch(av, 1, 0);

		    if (SvROK(pattern) && SvMAGICAL(sv = SvRV(pattern)))
			rx = (REGEXP*)((mg_find(sv, PERL_MAGIC_qr))->mg_obj);
		    else {
			if (! SvUTF8(pattern)) {
			    char *s;
			    size_t len, i;

			    len = SvCUR(pattern);
			    s = SvPV(pattern, len);
			    for (i = 0; i < len; i++)
			    if (127 < (unsigned char)s[i])
				croak("Unicode string must be given.");
			}
#if ((PERL_VERSION >= 10) || (PERL_VERSION == 9 && PERL_SUBVERSION >= 5))
			rx = pregcomp(pattern, 0);
#else /* PERL_VERSION */
			New(1, pm, 1, PMOP);
			rx = pregcomp(SvPVX(pattern), SvEND(pattern), pm);
#endif
			if (rx != NULL) {
			    sv_magic(pattern, (SV *)rx, PERL_MAGIC_qr, NULL, 0);
			    pattern = newRV_noinc(pattern);
			}
		    }

		    if (rx == NULL)
			croak("not a regexp");

		    av = newAV();
		    av_push(av, pattern);
		    av_push(av, func);
		    sv = newRV_noinc((SV *)av);
		    linebreak_add_prep(lbobj, prep_func, (void *)sv);
		} else if (SvOK(val)) {
		    char *s = SvPV_nolen(val);

		    if (strcasecmp(s, "BREAKURI") == 0)
			linebreak_add_prep(lbobj, linebreak_prep_URIBREAK, val);
		    else if (strcasecmp(s, "NONBREAKURI") == 0)
			linebreak_add_prep(lbobj, linebreak_prep_URIBREAK,
					   NULL);
		    else
			croak("Unknown preprocess option: %s", s);
		} else
		    linebreak_add_prep(lbobj, NULL, NULL);
	    } else if (strcmp(key, "Format") == 0) {
		if (sv_derived_from(val, "CODE"))
		    linebreak_set_format(lbobj, format_func, (void *)val);
		else if (SvOK(val)) {
		    char *s = SvPV_nolen(val);

		    if (strcasecmp(s, "DEFAULT") == 0) {
			warn("Method name \"DEFAULT\" for Format option was "
			     "obsoleted. Use \"SIMPLE\"");
			linebreak_set_format(lbobj, linebreak_format_SIMPLE,
					     NULL);
		    } else if (strcasecmp(s, "SIMPLE") == 0)
			linebreak_set_format(lbobj, linebreak_format_SIMPLE,
					     NULL);
		    else if (strcasecmp(s, "NEWLINE") == 0)
			linebreak_set_format(lbobj, linebreak_format_NEWLINE,
					     NULL);
		    else if (strcasecmp(s, "TRIM") == 0)
			linebreak_set_format(lbobj, linebreak_format_TRIM,
					     NULL);
		    else
			croak("Unknown Format option: %s", s);
		} else
		    linebreak_set_format(lbobj, NULL, NULL);
	    } else if (strcmp(key, "SizingMethod") == 0) {
		if (sv_derived_from(val, "CODE"))
		    linebreak_set_sizing(lbobj, sizing_func, (void *)val);
		else if (SvOK(val)) {
		    char *s = SvPV_nolen(val);

		    if (strcasecmp(s, "DEFAULT") == 0) {
			warn("Method name \"DEFAULT\" for SizingMethod option "
			     "was obsoleted. Use \"UAX11\"");
			linebreak_set_sizing(lbobj, linebreak_sizing_UAX11,
					     NULL);
		    } else if (strcasecmp(s, "UAX11") == 0)
			linebreak_set_sizing(lbobj, linebreak_sizing_UAX11,
					     NULL);
		    else
			croak("Unknown SizingMethod option: %s", s);
		} else
		    linebreak_set_sizing(lbobj, NULL, NULL);
	    } else if (strcmp(key, "UrgentBreaking") == 0) {
		if (sv_derived_from(val, "CODE"))
		    linebreak_set_urgent(lbobj, urgent_func, (void *)val);
		else if (SvOK(val)) {
		    char *s = SvPV_nolen(val);

		    if (strcasecmp(s, "NONBREAK") == 0) {
			warn("Method name \"NONBREAK\" for UrgentBreaking "
			     " option was obsoleted. Use undef");
			linebreak_set_urgent(lbobj, NULL, NULL);
		    } else if (strcasecmp(s, "CROAK") == 0)
			linebreak_set_urgent(lbobj, linebreak_urgent_ABORT,
					     NULL);
		    else if (strcasecmp(s, "FORCE") == 0)
			linebreak_set_urgent(lbobj, linebreak_urgent_FORCE,
					     NULL);
		    else
			croak("Unknown UrgentBreaking option: %s", s);
		} else
		    linebreak_set_urgent(lbobj, NULL, NULL);
	    } else if (strcmp(key, "_map") == 0) {
		if (lbobj->map) {
		    free(lbobj->map);
		    lbobj->map = NULL;
		    lbobj->mapsiz = 0;
		}
		if (SvOK(val)) {
		    lbobj->map = _loadmap(lbobj->map, val, &mapsiz);
		    lbobj->mapsiz = mapsiz;
		}
	    } else if (strcasecmp(key, "BreakIndent") == 0) {
		if (SVtoboolean(val))
		    lbobj->options |= LINEBREAK_OPTION_BREAK_INDENT;
		else
		    lbobj->options &= ~LINEBREAK_OPTION_BREAK_INDENT;
	    } else if (strcasecmp(key, "CharactersMax") == 0)
		lbobj->charmax = SvUV(val);
	    else if (strcasecmp(key, "ColumnsMax") == 0)
		lbobj->colmax = (double)SvNV(val);
	    else if (strcasecmp(key, "ColumnsMin") == 0)
		lbobj->colmin = (double)SvNV(val);
	    else if (strcasecmp(key, "ComplexBreaking") == 0) {
		if (SVtoboolean(val))
		    lbobj->options |= LINEBREAK_OPTION_COMPLEX_BREAKING;
		else
		    lbobj->options &= ~LINEBREAK_OPTION_COMPLEX_BREAKING;
	    } else if (strcasecmp(key, "Context") == 0) {
		if (SvOK(val))
		    opt = (char *)SvPV_nolen(val);
		else
		    opt = NULL;
		if (opt && strcasecmp(opt, "EASTASIAN") == 0)
		    lbobj->options |= LINEBREAK_OPTION_EASTASIAN_CONTEXT;
		else
		    lbobj->options &= ~LINEBREAK_OPTION_EASTASIAN_CONTEXT;
	    } else if (strcasecmp(key, "HangulAsAL") == 0) {
		if (SVtoboolean(val))
		    lbobj->options |= LINEBREAK_OPTION_HANGUL_AS_AL;
		else
		    lbobj->options &= ~LINEBREAK_OPTION_HANGUL_AS_AL;
	    } else if (strcasecmp(key, "LegacyCM") == 0) {
		if (SVtoboolean(val))
		    lbobj->options |= LINEBREAK_OPTION_LEGACY_CM;
		else
		    lbobj->options &= ~LINEBREAK_OPTION_LEGACY_CM;
	    } else if (strcasecmp(key, "Newline") == 0) {
		if (!sv_isobject(val)) {
		    unistr_t unistr = {NULL, 0};
		    SVtounistr(&unistr, val);
		    linebreak_set_newline(lbobj, &unistr);	
		    free(unistr.str);
		} else if (sv_derived_from(val, "Unicode::GCString")) {
		    gcstring_t *gcstr;
		    gcstr = PerltoC(gcstring_t *, val);
		    linebreak_set_newline(lbobj, (unistr_t *)gcstr);
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
	linebreak_t *lbobj;
    CODE:
	lbobj = SVtolinebreak(self);
	if (lbobj->stash == NULL)
	    lbobj->stash = newRV_noinc((SV *)newHV());
	RETVAL = lbobj->stash;
	if (RETVAL == NULL)
	    XSRETURN_UNDEF;
	if (SvROK(RETVAL)) /* FIXME */
	    SvREFCNT_inc((SV*)RETVAL);
    OUTPUT:
	RETVAL

SV*
as_scalarref(self, ...)
	SV *self;
    INIT:
	linebreak_t *lbobj;
	char buf[64];
    CODE:
	lbobj = SVtolinebreak(self);
	buf[0] = '\0';
	snprintf(buf, 64, "%s(0x%lx)", HvNAME(SvSTASH(SvRV(self))),
		 (unsigned long)(void *)lbobj);
	RETVAL = newRV_noinc(newSVpv(buf, 0));
    OUTPUT:
	RETVAL

SV *
as_string(self, ...)
	SV *self;
    INIT:
	linebreak_t *lbobj;
	char buf[64];
    CODE:
	lbobj = SVtolinebreak(self);
	buf[0] = '\0';
	snprintf(buf, 64, "%s(0x%lx)", HvNAME(SvSTASH(SvRV(self))),
		 (unsigned long)(void *)lbobj);
	RETVAL = newSVpv(buf, 0);
    OUTPUT:
	RETVAL

propval_t
eawidth(self, str)
	SV *self;
	SV *str;
    PROTOTYPE: $$
    INIT:
	linebreak_t *lbobj;
	unichar_t c;
	propval_t prop;
	gcstring_t *gcstr;
    CODE:
	lbobj = SVtolinebreak(self);
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
	prop = linebreak_eawidth(lbobj, c);
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
	linebreak_t *lbobj;
	unichar_t c;
	propval_t prop;
	gcstring_t *gcstr;
    CODE:
	lbobj = SVtolinebreak(self);
	if (!sv_isobject(str)) {
	    if (!SvCUR(str))
		XSRETURN_UNDEF;
	    c = utf8_to_uvuni((U8 *)SvPV_nolen(str), NULL);
	    prop = linebreak_lbclass(lbobj, c);
	}
	else if (sv_derived_from(str, "Unicode::GCString")) {
	    gcstr = PerltoC(gcstring_t *, str);
	    if (gcstr->gclen)
		prop = gcstr->gcstr[0].lbc;
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
	linebreak_t *lbobj;
	propval_t prop;
    CODE:
	if (!SvOK(ST(1)) || !SvOK(ST(2)))
	    XSRETURN_UNDEF;
	lbobj = SVtolinebreak(self);
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
	linebreak_reset(SVtolinebreak(self));

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
    CODE:
	lbobj = SVtolinebreak(self);
	/* gcpre = SVtogcstring(pre, lbobj); */
	gcspc = SVtogcstring(spc, lbobj);
	gcstr = SVtogcstring(str, lbobj);

	if (5 < items)
	     warn("``max'' argument of strsize was obsoleted");

	RETVAL = linebreak_sizing_UAX11(lbobj, len, NULL, gcspc, gcstr);

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

void
break(self, input)
	SV *self;
	SV *input;
    PROTOTYPE: $$
    INIT:
	linebreak_t *lbobj;
	unistr_t unistr = {NULL, 0}, *str;
	gcstring_t **ret, *r;
	size_t i;
    PPCODE:
	lbobj = SVtolinebreak(self);
	if (!SvOK(input))
	    XSRETURN_UNDEF;
	else {
	    if (!sv_isobject(input)) {
		if (!SvUTF8(input)) {
		    char *s;
		    size_t len, i;

		    len = SvCUR(input);
		    s = SvPV(input, len);
		    for (i = 0; i < len; i++)
			if (127 < (unsigned char)s[i])
			    croak("Unicode string must be given.");
		}
		SVtounistr(&unistr, input);
		str = &unistr;
	    } else if (sv_derived_from(input, "Unicode::GCString"))
		str = (unistr_t *)SVtogcstring(input, lbobj);
	    else
		croak("Unknown object %s", HvNAME(SvSTASH(SvRV(input))));

	    ret = linebreak_break(lbobj, str);
	    if (!sv_isobject(input))
		free(unistr.str);
	}

	if (ret == NULL) {
	    if (lbobj->errnum == LINEBREAK_EEXTN)
		croak("%s", SvPV_nolen(ERRSV));
	    else if (lbobj->errnum == LINEBREAK_ELONG)
		croak("%s", "Excessive line was found");
	    else if (lbobj->errnum)
		croak("%s", strerror(lbobj->errnum));
	    else
		croak("%s", "Unknown error");
	}

	switch (GIMME_V) {
	case G_SCALAR:
	    r = gcstring_new(NULL, lbobj);
	    for (i = 0; ret[i] != NULL; i++) {
		gcstring_append(r, ret[i]);
		gcstring_destroy(ret[i]);
	    }
	    free(ret);
	    XPUSHs(sv_2mortal(unistrtoSV((unistr_t *)r, 0, r->len)));
	    gcstring_destroy(r);
	    XSRETURN(1);

	case G_ARRAY:
	    for (i = 0; ret[i] != NULL; i++)
		XPUSHs(sv_2mortal(CtoPerl("Unicode::GCString", ret[i])));
	    free(ret);
	    XSRETURN(i);

	default:
	    for (i = 0; ret[i] != NULL; i++)
		gcstring_destroy(ret[i]);
	    free(ret);
	    XSRETURN_EMPTY;
	}

void
break_partial(self, input)
	SV *self;
	SV *input;
    PROTOTYPE: $$
    INIT:
	linebreak_t *lbobj;
	unistr_t unistr = {NULL, 0}, *str;
	gcstring_t **ret, *r;
	size_t i;
    PPCODE:
	lbobj = SVtolinebreak(self);
	if (!SvOK(input))
	    ret = linebreak_break_partial(lbobj, NULL);
	else {
	    if (!sv_isobject(input)) {
		if (!SvUTF8(input)) {
		    char *s;
		    size_t len, i;

		    len = SvCUR(input);
		    s = SvPV(input, len);
		    for (i = 0; i < len; i++)
			if (127 < (unsigned char)s[i])
			    croak("Unicode string must be given.");
		}
		SVtounistr(&unistr, input);
		str = &unistr;
	    } else
		str = (unistr_t *)SVtogcstring(input, lbobj);

	    ret = linebreak_break_partial(lbobj, str);
	    if (!sv_isobject(input))
		if (str->str != NULL)
		    free(str->str);
	}

	if (ret == NULL) {
	    if (lbobj->errnum == LINEBREAK_EEXTN)
		croak("%s", SvPV_nolen(ERRSV));
	    else if (lbobj->errnum == LINEBREAK_ELONG)
		croak("%s", "Excessive line was found");
	    else if (lbobj->errnum)
		croak("%s", strerror(lbobj->errnum));
	    else
		croak("%s", "Unknown error");
	}

	switch (GIMME_V) {
	case G_SCALAR:
	    r = gcstring_new(NULL, lbobj);
	    for (i = 0; ret[i] != NULL; i++) {
		gcstring_append(r, ret[i]);
		gcstring_destroy(ret[i]);
	    }
	    free(ret);
	    XPUSHs(sv_2mortal(unistrtoSV((unistr_t *)r, 0, r->len)));
	    gcstring_destroy(r);
	    XSRETURN(1);

	case G_ARRAY:
	    for (i = 0; ret[i] != NULL; i++)
		XPUSHs(sv_2mortal(CtoPerl("Unicode::GCString", ret[i])));
	    free(ret);
	    XSRETURN(i);

	default:
	    for (i = 0; ret[i] != NULL; i++)
		gcstring_destroy(ret[i]);
	    free(ret);
	    XSRETURN_EMPTY;
	}

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
	unistr_t unistr = {NULL, 0};
    CODE:
	if (!SvOK(str)) /* prevent segfault. */
	    XSRETURN_UNDEF;
	if (2 < items)
	    lbobj = SVtolinebreak(ST(2));
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
	if (!sv_isobject(self))
	    croak("Not object");
	gcstring_destroy(SVtogcstring(self, NULL));

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
	gcstr = SVtogcstring(self, NULL);    
	if (gcstr != NULL)
	    for (i = 0; i < gcstr->gclen; i++)
		XPUSHs(sv_2mortal(
			   CtoPerl("Unicode::GCString", 
				   gctogcstring(gcstr, gcstr->gcstr + i))));

SV*
as_scalarref(self, ...)
	SV *self;
    INIT:
	linebreak_t *lbobj;
	char buf[64];
    CODE:
	lbobj = SVtolinebreak(self);
	buf[0] = '\0';
	snprintf(buf, 64, "%s(0x%lx)", HvNAME(SvSTASH(SvRV(self))),
		 (unsigned long)(void *)lbobj);
	RETVAL = newRV_noinc(newSVpv(buf, 0));
    OUTPUT:
	RETVAL

SV *
as_string(self, ...)
	SV *self;
    PROTOTYPE: $;$;$
    INIT:
	gcstring_t *gcstr;
	unistr_t unistr = {NULL, 0};
    CODE:
	if (!sv_isobject(self))
	    XSRETURN_UNDEF;
	gcstr = SVtogcstring(self, NULL);    
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
	gcstr = SVtogcstring(self, NULL);    
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
	gcstr1 = SVtogcstring(self, NULL);    
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
	gcstr = SVtogcstring(self, NULL);    
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
	gcstr = SVtogcstring(self, NULL);    
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
	gcstr = SVtogcstring(self, NULL);    
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
	gcstr = SVtogcstring(self, NULL);    
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
	gcstr = SVtogcstring(self, NULL);    
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
	gcstr = SVtogcstring(self, NULL);    
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

SV *
join(self, ...)
	SV *self;
    INIT:
	size_t i;
	gcstring_t *gcstr, *str, *ret;
    CODE:
	if (!sv_isobject(self))
	    croak("Not object");
	gcstr = SVtogcstring(self, NULL);

	switch (items) {
	case 0:
	    croak("Too few arguments");
	case 1:
	    ret = gcstring_new(NULL, gcstr->lbobj);
	    break;
	case 2:
	    ret = SVtogcstring(ST(1), gcstr->lbobj);
	    if (sv_isobject(ST(1)))
		ret = gcstring_copy(ret);
	    break;
	default:
	    ret = SVtogcstring(ST(1), gcstr->lbobj);
	    if (sv_isobject(ST(1)))
		ret = gcstring_copy(ret);
	    for (i = 2; i < items; i++) {
		gcstring_append(ret, gcstr);
		str = SVtogcstring(ST(i), gcstr->lbobj);
		gcstring_append(ret, str);
		if (!sv_isobject(ST(i)))
		    gcstring_destroy(str);
	    }
	    break;
	}
	RETVAL = CtoPerl("Unicode::GCString", ret);
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
	gcstr = SVtogcstring(self, NULL);    
	if (1 < items) {
	    i = SvIV(ST(1));
	    if (i < 0)
		i += gcstr->gclen;
	} else
	    i = gcstr->pos;
	if (i < 0 || gcstr == NULL || gcstr->gclen <= i)
	    XSRETURN_UNDEF;
	RETVAL = (propval_t)gcstr->gcstr[i].lbc;
    OUTPUT:
	RETVAL

propval_t
lbclass_ext(self, ...)
	SV *self;
    PROTOTYPE: $;$
    INIT:
	int i;
	gcstring_t *gcstr;
    CODE:
	if (!sv_isobject(self))
	    XSRETURN_UNDEF;
	gcstr = SVtogcstring(self, NULL);    
	if (1 < items) {
	    i = SvIV(ST(1));
	    if (i < 0)
		i += gcstr->gclen;
	} else
	    i = gcstr->pos;
	if (i < 0 || gcstr == NULL || gcstr->gclen <= i)
	    XSRETURN_UNDEF;
	if ((RETVAL = (propval_t)gcstr->gcstr[i].elbc) == PROP_UNKNOWN)
	    RETVAL = (propval_t)gcstr->gcstr[i].lbc;
	if (RETVAL == PROP_UNKNOWN)
	    XSRETURN_UNDEF;
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
	gcstr = SVtogcstring(self, NULL);    
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
	gcstr = SVtogcstring(self, NULL);    
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
	gcstr = SVtogcstring(self, NULL);    
	
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
	gcstr = SVtogcstring(self, NULL);    
	if (2 < items)
	    length = SvIV(ST(2));
	else
	    length = gcstr->gclen;
        if (3 < items) {
	    replacement = SVtogcstring(ST(3), gcstr->lbobj);
        } else
            replacement = NULL;

	ret = gcstring_substr(gcstr, offset, length);
	if (replacement != NULL)
	    if (gcstring_replace(gcstr, offset, length, replacement) == NULL)
		croak("%s", strerror(errno));

	if (3 < items && !sv_isobject(ST(3)))
	    gcstring_destroy(replacement);
	if (ret == NULL) {
	    gcstring_destroy(ret);
	    croak("%s", strerror(errno));
	} else
	    RETVAL = CtoPerl("Unicode::GCString", ret);
    OUTPUT:
	RETVAL
