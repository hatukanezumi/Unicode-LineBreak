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
#define NEED_newRV_noinc
#define NEED_sv_2pv_flags
#define NEED_sv_2pv_nolen
#include "ppport.h"
#include "sombok.h"

/* Type synonyms for typemap. */
typedef IV swapspec_t;
typedef gcstring_t *generic_string;

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

    if (SvOK(str))
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
    ((type)SvIV((SV *)SvRV(self)))

/*
 * Create Perl object from C object
 */
static
SV *CtoPerl(char *klass, void *obj)
{
    SV *sv, *rv;

    sv = newSViv(0);
    rv = sv_setref_iv(sv, klass, (IV)obj);  
#if 0
    SvREADONLY_on(rv); /* FIXME:Can't bless derived class */
#endif /* 0 */
    return sv;
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

#if 0
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
#endif /* 0 */

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
    SvREADONLY_on(screamer);
    str_beg = str_arg = SvPVX(screamer);
    str_end = SvEND(screamer);

    if (pregexec(rx, str_arg, str_end, str_beg, 0, screamer, 1)) {
	size_t offs_beg, offs_end;
#if PERL_VERSION >= 11
	offs_beg = ((regexp *)SvANY(rx))->offs[0].start;
	offs_end = ((regexp *)SvANY(rx))->offs[0].end;
#elif ((PERL_VERSION == 10) || (PERL_VERSION == 9 && PERL_SUBVERSION >= 5))
	offs_beg = rx->offs[0].start;
	offs_end = rx->offs[0].end;
#else /* PERL_VERSION */
	offs_beg = rx->startp[0];
	offs_end = rx->endp[0];
#endif
	str->str += utf8_length((U8 *)str_beg, (U8 *)(str_beg + offs_beg));	
	str->len = utf8_length((U8 *)(str_beg + offs_beg),
			       (U8 *)(str_beg + offs_end));
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

    if (text != NULL) {
	if ((pp = av_fetch(data, 0, 0)) == NULL)
	    return (lbobj->errnum = EINVAL), NULL;

#if ((PERL_VERSION >= 10) || (PERL_VERSION >= 9 && PERL_SUBVERSION >= 5))
	if (SvRXOK(*pp))
	    rx = SvRX(*pp);
#else /* PERL_VERSION */
	if (SvROK(*pp) && SvMAGICAL(sv = SvRV(*pp))) {
	    MAGIC *mg;
	    if ((mg = mg_find(sv, PERL_MAGIC_qr)) != NULL)
		rx = (REGEXP *)mg->mg_obj;
	}
#endif /* PERL_VERSION */
	if (rx == NULL)
	    return (lbobj->errnum = EINVAL), NULL;

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
EAWidths()
    INIT:
	char **p;
    PPCODE:
	for (p = (char **)linebreak_propvals_EA; *p != NULL; p++)
	    XPUSHs(sv_2mortal(newSVpv(*p, 0)));

void
LBClasses()
    INIT:
	char **p;
    PPCODE:
	for (p = (char **)linebreak_propvals_LB; *p != NULL; p++)
	    XPUSHs(sv_2mortal(newSVpv(*p, 0)));

linebreak_t *
_new(klass)
	char *klass;
    PROTOTYPE: $
    CODE:
	if ((RETVAL = linebreak_new(ref_func)) == NULL)
	    croak("%s->_new: Can't allocate memory", klass);
	linebreak_set_stash(RETVAL, newRV_noinc((SV *)newHV()));
	SvREFCNT_dec(RETVAL->stash); /* fixup */
    OUTPUT:
	RETVAL

linebreak_t *
copy(self)
	linebreak_t *self;
    PROTOTYPE: $
    CODE:
	RETVAL = linebreak_copy(self);
    OUTPUT:
	RETVAL

void
DESTROY(self)
	linebreak_t *self;
    PROTOTYPE: $
    CODE:
	linebreak_destroy(self);

SV *
_config(self, ...)
	linebreak_t *self;
    PREINIT:
	size_t i;
	char *key;
	void *func;
	SV *val;
	char *opt;
    CODE:
	if (self == NULL)
	    if ((self = linebreak_new()) == NULL)
		croak("_config: Can't allocate memory");

	RETVAL = NULL;
	if (items < 2)
	    croak("_config: Too few arguments");
	else if (items < 3) {
	    key = (char *)SvPV_nolen(ST(1));

	    if (strcasecmp(key, "BreakIndent") == 0)
		RETVAL = newSVuv(self->options &
				 LINEBREAK_OPTION_BREAK_INDENT); 
	    else if (strcasecmp(key, "CharactersMax") == 0)
		RETVAL = newSVuv(self->charmax);
	    else if (strcasecmp(key, "ColumnsMax") == 0)
		RETVAL = newSVnv((NV)self->colmax);
	    else if (strcasecmp(key, "ColumnsMin") == 0)
		RETVAL = newSVnv((NV)self->colmin);
	    else if (strcasecmp(key, "ComplexBreaking") == 0)
		RETVAL = newSVuv(self->options &
				 LINEBREAK_OPTION_COMPLEX_BREAKING);
	    else if (strcasecmp(key, "Context") == 0) {
		if (self->options & LINEBREAK_OPTION_EASTASIAN_CONTEXT)
		    RETVAL = newSVpvn("EASTASIAN", 9);
		else
		    RETVAL = newSVpvn("NONEASTASIAN", 12);
	    } else if (strcasecmp(key, "EAWidth") == 0) {
		AV *ret, *av, *codes;
		propval_t p;
		unichar_t c;
		size_t i;

		if (self->map == NULL || self->mapsiz == 0)
		    XSRETURN_UNDEF;

		ret = NULL;
		for (i = 0; i < self->mapsiz; i++)
		    if ((p = self->map[i].eaw) != PROP_UNKNOWN) {
			codes = newAV();
			for (c = self->map[i].beg; c <= self->map[i].end;
			     c++)
			    av_push(codes, newSVuv(c));
			av = newAV();
			av_push(av, newRV_noinc((SV *)codes));
			av_push(av, newSViv((IV)p));
			if (ret == NULL)
			    ret = newAV();
			av_push(ret, newRV_noinc((SV *)av));
		    }

		if (ret == NULL)
		    XSRETURN_UNDEF;
		RETVAL = newRV_noinc((SV *)ret);
	    } else if (strcasecmp(key, "Format") == 0) {
		func = self->format_func;
		if (func == NULL)
		    XSRETURN_UNDEF;
		else if (func == linebreak_format_NEWLINE)
		    RETVAL = newSVpvn("NEWLINE", 7);
		else if (func == linebreak_format_SIMPLE)
		    RETVAL = newSVpvn("SIMPLE", 6);
		else if (func == linebreak_format_TRIM)
		    RETVAL = newSVpvn("TRIM", 4);
		else if (func == format_func) {
		    if ((val = (SV *)self->format_data) == NULL)
			XSRETURN_UNDEF;
		    ST(0) = val; /* should not be mortal. */
		    XSRETURN(1);
		} else
		    croak("config: internal error");
	    } else if (strcasecmp(key, "HangulAsAL") == 0)
		RETVAL = newSVuv(self->options &
				 LINEBREAK_OPTION_HANGUL_AS_AL);
	    else if (strcasecmp(key, "LBClass") == 0) {
		AV *ret, *av, *codes;
		propval_t p;
		unichar_t c;
		size_t i;

		if (self->map == NULL || self->mapsiz == 0)
		    XSRETURN_UNDEF;

		ret = NULL;
		for (i = 0; i < self->mapsiz; i++)
		    if ((p = self->map[i].lbc) != PROP_UNKNOWN) {
			codes = newAV();
			for (c = self->map[i].beg; c <= self->map[i].end;
			     c++)
			    av_push(codes, newSVuv(c));
			av = newAV();
			av_push(av, newRV_noinc((SV *)codes));
			av_push(av, newSViv((IV)p));
			if (ret == NULL)
			    ret = newAV();
			av_push(ret, newRV_noinc((SV *)av));
		    }

		if (ret == NULL)
		    XSRETURN_UNDEF;
		RETVAL = newRV_noinc((SV *)ret);
	    } else if (strcasecmp(key, "LegacyCM") == 0)
		RETVAL = newSVuv(self->options & LINEBREAK_OPTION_LEGACY_CM);
	    else if (strcasecmp(key, "Newline") == 0) {
		unistr_t unistr = {self->newline.str, self->newline.len};
		if (self->newline.str == NULL || self->newline.len == 0)
		    RETVAL = unistrtoSV(&unistr, 0, 0);
		else
		    RETVAL = unistrtoSV(&unistr, 0, self->newline.len);
	    } else if (strcasecmp(key, "Prep") == 0) {
		AV *av;
		if (self->prep_func == NULL || self->prep_func[0] == NULL)
		    XSRETURN_UNDEF;
		av = newAV();
		for (i = 0; (func = self->prep_func[i]) != NULL; i++)
		    if (func == linebreak_prep_URIBREAK) {
			if (self->prep_data == NULL ||
			    self->prep_data[i] == NULL)
			    av_push(av, newSVpvn("NONBREAKURI", 11));
			else
			    av_push(av, newSVpvn("BREAKURI", 8));
		    } else if (func == prep_func) {
			if (self->prep_data == NULL ||
			    self->prep_data[i] == NULL)
			    croak("_config: internal error");
			SvREFCNT_inc(self->prep_data[i]); /* avoid freed */
			av_push(av, self->prep_data[i]);
		    } else
			croak("_config: internal error");
		RETVAL = newRV_noinc((SV *)av);
	    } else if (strcasecmp(key, "SizingMethod") == 0) {
		func = self->sizing_func;
		if (func == NULL)
		    XSRETURN_UNDEF;
		else if (func == linebreak_sizing_UAX11)
		    RETVAL = newSVpvn("UAX11", 5);
		else if (func == sizing_func) {
		    if ((val = (SV *)self->sizing_data) == NULL)
			XSRETURN_UNDEF;
		    ST(0) = val; /* should not be mortal. */
		    XSRETURN(1);
		} else
		    croak("config: internal error");
	    } else if (strcasecmp(key, "UrgentBreaking") == 0) {
		func = self->urgent_func;
		if (func == NULL)
		    XSRETURN_UNDEF;
		else if (func == linebreak_urgent_ABORT)
		    RETVAL = newSVpvn("CROAK", 5);
		else if (func == linebreak_urgent_FORCE)
		    RETVAL = newSVpvn("FORCE", 5);
		else if (func == urgent_func) {
		    if ((val = (SV *)self->urgent_data) == NULL)
			XSRETURN_UNDEF;
		    ST(0) = val; /* should not be mortal. */
		    XSRETURN(1);
		} else
		    croak("config: internal error");
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

	    if (strcasecmp(key, "Prep") == 0) {
		SV *sv, *pattern, *func;
		AV *av;
		REGEXP *rx = NULL;

		if (SvROK(val) &&
		    SvTYPE(av = (AV *)SvRV(val)) == SVt_PVAV &&
		    0 < av_len(av) + 1) {
		    pattern = *av_fetch(av, 0, 0);
#if ((PERL_VERSION >= 10) || (PERL_VERSION >= 9 && PERL_SUBVERSION >= 5))
		    if (SvRXOK(pattern))
			rx = SvRX(pattern);
#else /* PERL_VERSION */
		    if (SvROK(pattern) && SvMAGICAL(sv = SvRV(pattern))) {
			MAGIC *mg;
			if ((mg = mg_find(sv, PERL_MAGIC_qr)) != NULL)
			    rx = (REGEXP *)mg->mg_obj;
		    }
#endif
		    if (rx != NULL)
			SvREFCNT_inc(pattern); /* avoid freed */
		    else if (SvOK(pattern)) {
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
			{
			    PMOP *pm;
			    New(1, pm, 1, PMOP);
			    rx = pregcomp(SvPVX(pattern), SvEND(pattern), pm);
			}
#endif
			if (rx != NULL) {
#if PERL_VERSION >= 11
			    pattern = newRV_noinc((SV *)rx);
			    sv_bless(pattern, gv_stashpv("Regexp", 0));
#else /* PERL_VERSION */
			    sv = newSV(0);
			    sv_magic(sv, (SV *)rx, PERL_MAGIC_qr, NULL, 0);
			    pattern = newRV_noinc(sv);
			    sv_bless(pattern, gv_stashpv("Regexp", 0));
#endif
			}
		    } else
			rx = NULL;

		    if (rx == NULL)
			croak("not a regex");

		    if (av_fetch(av, 1, 0) == NULL)
			func = NULL;
		    else if (SvOK(func = *av_fetch(av, 1, 0)))
			SvREFCNT_inc(func); /* avoid freed */
		    else
			func = NULL;

		    av = newAV();
		    av_push(av, pattern);
		    if (func != NULL)
			av_push(av, func);
		    sv = newRV_noinc((SV *)av);
		    linebreak_add_prep(self, prep_func, (void *)sv);
		    SvREFCNT_dec(sv); /* fixup */
		} else if (SvOK(val)) {
		    char *s = SvPV_nolen(val);

		    if (strcasecmp(s, "BREAKURI") == 0)
			linebreak_add_prep(self, linebreak_prep_URIBREAK, val);
		    else if (strcasecmp(s, "NONBREAKURI") == 0)
			linebreak_add_prep(self, linebreak_prep_URIBREAK,
					   NULL);
		    else
			croak("Unknown preprocess option: %s", s);
		} else
		    linebreak_add_prep(self, NULL, NULL);
	    } else if (strcasecmp(key, "Format") == 0) {
		if (sv_derived_from(val, "CODE"))
		    linebreak_set_format(self, format_func, (void *)val);
		else if (SvOK(val)) {
		    char *s = SvPV_nolen(val);

		    if (strcasecmp(s, "DEFAULT") == 0) {
			warn("Method name \"DEFAULT\" for Format option was "
			     "obsoleted. Use \"SIMPLE\"");
			linebreak_set_format(self, linebreak_format_SIMPLE,
					     NULL);
		    } else if (strcasecmp(s, "SIMPLE") == 0)
			linebreak_set_format(self, linebreak_format_SIMPLE,
					     NULL);
		    else if (strcasecmp(s, "NEWLINE") == 0)
			linebreak_set_format(self, linebreak_format_NEWLINE,
					     NULL);
		    else if (strcasecmp(s, "TRIM") == 0)
			linebreak_set_format(self, linebreak_format_TRIM,
					     NULL);
		    else
			croak("Unknown Format option: %s", s);
		} else
		    linebreak_set_format(self, NULL, NULL);
	    } else if (strcasecmp(key, "SizingMethod") == 0) {
		if (sv_derived_from(val, "CODE"))
		    linebreak_set_sizing(self, sizing_func, (void *)val);
		else if (SvOK(val)) {
		    char *s = SvPV_nolen(val);

		    if (strcasecmp(s, "DEFAULT") == 0) {
			warn("Method name \"DEFAULT\" for SizingMethod option "
			     "was obsoleted. Use \"UAX11\"");
			linebreak_set_sizing(self, linebreak_sizing_UAX11,
					     NULL);
		    } else if (strcasecmp(s, "UAX11") == 0)
			linebreak_set_sizing(self, linebreak_sizing_UAX11,
					     NULL);
		    else
			croak("Unknown SizingMethod option: %s", s);
		} else
		    linebreak_set_sizing(self, NULL, NULL);
	    } else if (strcasecmp(key, "UrgentBreaking") == 0) {
		if (sv_derived_from(val, "CODE"))
		    linebreak_set_urgent(self, urgent_func, (void *)val);
		else if (SvOK(val)) {
		    char *s = SvPV_nolen(val);

		    if (strcasecmp(s, "NONBREAK") == 0) {
			warn("Method name \"NONBREAK\" for UrgentBreaking "
			     " option was obsoleted. Use undef");
			linebreak_set_urgent(self, NULL, NULL);
		    } else if (strcasecmp(s, "CROAK") == 0)
			linebreak_set_urgent(self, linebreak_urgent_ABORT,
					     NULL);
		    else if (strcasecmp(s, "FORCE") == 0)
			linebreak_set_urgent(self, linebreak_urgent_FORCE,
					     NULL);
		    else
			croak("Unknown UrgentBreaking option: %s", s);
		} else
		    linebreak_set_urgent(self, NULL, NULL);
	    } else if (strcasecmp(key, "BreakIndent") == 0) {
		if (SVtoboolean(val))
		    self->options |= LINEBREAK_OPTION_BREAK_INDENT;
		else
		    self->options &= ~LINEBREAK_OPTION_BREAK_INDENT;
	    } else if (strcasecmp(key, "CharactersMax") == 0)
		self->charmax = SvUV(val);
	    else if (strcasecmp(key, "ColumnsMax") == 0)
		self->colmax = (double)SvNV(val);
	    else if (strcasecmp(key, "ColumnsMin") == 0)
		self->colmin = (double)SvNV(val);
	    else if (strcasecmp(key, "ComplexBreaking") == 0) {
		if (SVtoboolean(val))
		    self->options |= LINEBREAK_OPTION_COMPLEX_BREAKING;
		else
		    self->options &= ~LINEBREAK_OPTION_COMPLEX_BREAKING;
	    } else if (strcasecmp(key, "Context") == 0) {
		if (SvOK(val))
		    opt = (char *)SvPV_nolen(val);
		else
		    opt = NULL;
		if (opt && strcasecmp(opt, "EASTASIAN") == 0)
		    self->options |= LINEBREAK_OPTION_EASTASIAN_CONTEXT;
		else
		    self->options &= ~LINEBREAK_OPTION_EASTASIAN_CONTEXT;
	    } else if (strcasecmp(key, "EAWidth") == 0) {
		AV *av, *codes;
		SV *sv;
		propval_t p;
		size_t i;

		if (! SvOK(val))
		    linebreak_clear_eawidth(self);
		else if (SvROK(val) &&
		    SvTYPE(av = (AV *)SvRV(val)) == SVt_PVAV &&
		    av_len(av) + 1 == 2 &&
		    av_fetch(av, 0, 0) != NULL && av_fetch(av, 1, 0) != NULL) {
		    sv = *av_fetch(av, 1, 0);
		    if (SvIOK(sv))
			p = SvIV(sv);
		    else
			croak("_config: Invalid argument");

		    sv = *av_fetch(av, 0, 0);
		    if (SvROK(sv) &&
			SvTYPE(codes = (AV *)SvRV(sv)) == SVt_PVAV) {
			for (i = 0; i < av_len(codes) + 1; i++) {
			    if (av_fetch(codes, i, 0) == NULL)
				continue;
			    if (! SvIOK(sv = *av_fetch(codes, i, 0)))
				croak("_config: Invalid argument");
			    linebreak_update_eawidth(self, SvUV(sv), p);
			}
		    } else if (SvIOK(sv)) {
			linebreak_update_eawidth(self, SvUV(sv), p);
		    } else
			croak("_config: Invalid argument");
		} else
		    croak("_config: Invalid argument");
	    } else if (strcasecmp(key, "HangulAsAL") == 0) {
		if (SVtoboolean(val))
		    self->options |= LINEBREAK_OPTION_HANGUL_AS_AL;
		else
		    self->options &= ~LINEBREAK_OPTION_HANGUL_AS_AL;
	    } else if (strcasecmp(key, "LBClass") == 0) {
		AV *av, *codes;
		SV *sv;
		propval_t p;
		size_t i;

		if (! SvOK(val))
		    linebreak_clear_lbclass(self);
		else if (SvROK(val) &&
		    SvTYPE(av = (AV *)SvRV(val)) == SVt_PVAV &&
		    av_len(av) + 1 == 2 &&
		    av_fetch(av, 0, 0) != NULL && av_fetch(av, 1, 0) != NULL) {
		    sv = *av_fetch(av, 1, 0);
		    if (SvIOK(sv))
			p = SvIV(sv);
		    else
			croak("_config: Invalid argument");

		    sv = *av_fetch(av, 0, 0);
		    if (SvROK(sv) &&
			SvTYPE(codes = (AV *)SvRV(sv)) == SVt_PVAV) {
			for (i = 0; i < av_len(codes) + 1; i++) {
			    if (av_fetch(codes, i, 0) == NULL)
				continue;
			    if (! SvIOK(sv = *av_fetch(codes, i, 0)))
				croak("_config: Invalid argument");
			    linebreak_update_lbclass(self, SvUV(sv), p);
			}
		    } else if (SvIOK(sv)) {
			linebreak_update_lbclass(self, SvUV(sv), p);
		    } else
			croak("_config: Invalid argument");
		} else
		    croak("_config: Invalid argument");
	    } else if (strcasecmp(key, "LegacyCM") == 0) {
		if (SVtoboolean(val))
		    self->options |= LINEBREAK_OPTION_LEGACY_CM;
		else
		    self->options &= ~LINEBREAK_OPTION_LEGACY_CM;
	    } else if (strcasecmp(key, "Newline") == 0) {
		if (!sv_isobject(val)) {
		    unistr_t unistr = {NULL, 0};
		    SVtounistr(&unistr, val);
		    linebreak_set_newline(self, &unistr);	
		    free(unistr.str);
		} else if (sv_derived_from(val, "Unicode::GCString")) {
		    gcstring_t *gcstr;
		    gcstr = PerltoC(gcstring_t *, val);
		    linebreak_set_newline(self, (unistr_t *)gcstr);
		} else
		    croak("Unknown object %s", HvNAME(SvSTASH(SvRV(val))));
	    }
	    else
		warn("_config: Setting unknown option %s", key);
	}
    OUTPUT:
	RETVAL

void
as_hashref(self, ...)
	linebreak_t *self;
    CODE:
	if (self->stash == NULL)
	    XSRETURN_UNDEF;
	ST(0) = self->stash; /* should not be mortal */
	XSRETURN(1);

SV*
as_scalarref(self, ...)
	linebreak_t *self;
    PREINIT:
	char buf[64];
    CODE:
	buf[0] = '\0';
	snprintf(buf, 64, "%s(0x%lx)", HvNAME(SvSTASH(SvRV(ST(0)))),
		 (unsigned long)(void *)self);
	RETVAL = newRV_noinc(newSVpv(buf, 0));
    OUTPUT:
	RETVAL

SV *
as_string(self, ...)
	linebreak_t *self;
    PREINIT:
	char buf[64];
    CODE:
	buf[0] = '\0';
	snprintf(buf, 64, "%s(0x%lx)", HvNAME(SvSTASH(SvRV(ST(0)))),
		 (unsigned long)(void *)self);
	RETVAL = newSVpv(buf, 0);
    OUTPUT:
	RETVAL

propval_t
eawidth(self, str)
	linebreak_t *self;
	SV *str;
    PROTOTYPE: $$
    PREINIT:
	unichar_t c;
	gcstring_t *gcstr;
    CODE:
	if (! SvOK(str))
	    XSRETURN_UNDEF;
	else if (!sv_isobject(str)) {
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
	RETVAL = linebreak_eawidth(self, c);
	if (RETVAL == PROP_UNKNOWN)
	    XSRETURN_UNDEF;
    OUTPUT:
	RETVAL

propval_t
lbclass(self, str)
	linebreak_t *self;
	SV *str;
    PROTOTYPE: $$
    PREINIT:
	unichar_t c;
	gcstring_t *gcstr;
    CODE:
	if (! SvOK(str))
	    XSRETURN_UNDEF;
	else if (!sv_isobject(str)) {
	    if (!SvCUR(str))
		XSRETURN_UNDEF;
	    c = utf8_to_uvuni((U8 *)SvPV_nolen(str), NULL);
	    RETVAL = linebreak_lbclass(self, c);
	}
	else if (sv_derived_from(str, "Unicode::GCString")) {
	    gcstr = PerltoC(gcstring_t *, str);
	    if (gcstr->gclen)
		RETVAL = gcstr->gcstr[0].lbc;
	    else
		RETVAL = PROP_UNKNOWN;
	}
	else
	    croak("Unknown object %s", HvNAME(SvSTASH(SvRV(str))));
	if (RETVAL == PROP_UNKNOWN)
	    XSRETURN_UNDEF;
    OUTPUT:
	RETVAL

propval_t
lbrule(self, b_idx, a_idx)
	linebreak_t *self;
	propval_t b_idx;
	propval_t a_idx;
    PROTOTYPE: $$$
    CODE:
	if (!SvOK(ST(1)) || !SvOK(ST(2)))
	    XSRETURN_UNDEF;
	RETVAL = linebreak_lbrule(b_idx, a_idx);
	if (RETVAL == PROP_UNKNOWN)
	    XSRETURN_UNDEF;
    OUTPUT:
	RETVAL

void
reset(self)
	linebreak_t *self;
    PROTOTYPE: $
    CODE:
	linebreak_reset(self);

double
strsize(lbobj, len, pre, spc, str, ...)
	linebreak_t *lbobj;
	double len;
	SV *pre;
	generic_string spc;
	generic_string str;
    PROTOTYPE: $$$$$;$
    CODE:
	if (5 < items)
	     warn("``max'' argument of strsize was obsoleted");

	RETVAL = linebreak_sizing_UAX11(lbobj, len, NULL, spc, str);
	if (RETVAL == -1.0)
	    croak("strsize: Can't allocate memory");
    OUTPUT:
	RETVAL

void
break(self, input)
	linebreak_t *self;
	unistr_t *input;
    PROTOTYPE: $$
    PREINIT:
	gcstring_t **ret, *r;
	size_t i;
    PPCODE:
	if (input == NULL)
	    XSRETURN_UNDEF;
	ret = linebreak_break(self, input);

	if (ret == NULL) {
	    if (self->errnum == LINEBREAK_EEXTN)
		croak("%s", SvPV_nolen(ERRSV));
	    else if (self->errnum == LINEBREAK_ELONG)
		croak("%s", "Excessive line was found");
	    else if (self->errnum)
		croak("%s", strerror(self->errnum));
	    else
		croak("%s", "Unknown error");
	}

	switch (GIMME_V) {
	case G_SCALAR:
	    r = gcstring_new(NULL, self);
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
	linebreak_t *self;
	unistr_t *input;
    PROTOTYPE: $$
    PREINIT:
	gcstring_t **ret, *r;
	size_t i;
    PPCODE:
	ret = linebreak_break_partial(self, input);

	if (ret == NULL) {
	    if (self->errnum == LINEBREAK_EEXTN)
		croak("%s", SvPV_nolen(ERRSV));
	    else if (self->errnum == LINEBREAK_ELONG)
		croak("%s", "Excessive line was found");
	    else if (self->errnum)
		croak("%s", strerror(self->errnum));
	    else
		croak("%s", "Unknown error");
	}

	switch (GIMME_V) {
	case G_SCALAR:
	    r = gcstring_new(NULL, self);
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

gcstring_t *
new(klass, str, lbobj=NULL)
	char *klass;
	unistr_t *str;
	linebreak_t *lbobj;
    PROTOTYPE: $$;$
    CODE:
	if (str == NULL)
	    XSRETURN_UNDEF;
	/* FIXME:buffer is copied twice. */
	if ((RETVAL = gcstring_newcopy(str, lbobj)) == NULL)
	    croak("%s->new: Can't allocate memory", klass);
    OUTPUT:
	RETVAL

void
DESTROY(self)
	gcstring_t *self;
    PROTOTYPE: $
    CODE:
	gcstring_destroy(self);

void
as_array(self)
	gcstring_t *self;
    PROTOTYPE: $
    PREINIT:
	size_t i;
    PPCODE:
	if (self != NULL)
	    for (i = 0; i < self->gclen; i++)
		XPUSHs(sv_2mortal(
			   CtoPerl("Unicode::GCString", 
				   gctogcstring(self, self->gcstr + i))));

SV*
as_scalarref(self, ...)
	gcstring_t *self;
    PREINIT:
	char buf[64];
    CODE:
	buf[0] = '\0';
	snprintf(buf, 64, "%s(0x%lx)", HvNAME(SvSTASH(SvRV(ST(0)))),
		 (unsigned long)(void *)self);
	RETVAL = newRV_noinc(newSVpv(buf, 0));
    OUTPUT:
	RETVAL

SV *
as_string(self, ...)
	gcstring_t *self;
    PROTOTYPE: $;$;$
    CODE:
	RETVAL = unistrtoSV((unistr_t *)self, 0, self->len);
    OUTPUT:
	RETVAL

size_t
chars(self)
	gcstring_t *self;
    PROTOTYPE: $
    CODE:
	RETVAL = self->len;
    OUTPUT:
	RETVAL

#define lbobj self->lbobj
int
cmp(self, str, swap=FALSE)
	gcstring_t *self;
	generic_string str;
	swapspec_t swap;
    PROTOTYPE: $$;$
    CODE:
	if (swap == TRUE)
	    RETVAL = gcstring_cmp(str, self);
	else
	    RETVAL = gcstring_cmp(self, str);
    OUTPUT:
	RETVAL

size_t
columns(self)
	gcstring_t *self;
    CODE:
	RETVAL = gcstring_columns(self);
    OUTPUT:
	RETVAL

#define lbobj self->lbobj
gcstring_t *
concat(self, str, swap=FALSE)
	gcstring_t *self;
	generic_string str;
	swapspec_t swap;
    PROTOTYPE: $$;$
    CODE:
	if (swap == TRUE)
	    RETVAL = gcstring_concat(str, self);
	else
	    RETVAL = gcstring_concat(self, str);
    OUTPUT:
	RETVAL

gcstring_t *
copy(self)
	gcstring_t *self;
    PROTOTYPE: $
    CODE:
	RETVAL = gcstring_copy(self);
    OUTPUT:
	RETVAL

int
eos(self)
	gcstring_t *self;
    CODE:
	RETVAL = gcstring_eos(self);
    OUTPUT:
	RETVAL

unsigned int
flag(self, ...)
	gcstring_t *self;
    PROTOTYPE: $;$;$
    PREINIT:
	int i;
	unsigned int flag;
    CODE:
	if (1 < items)
	    i = SvIV(ST(1));
	else
	    i = self->pos;
	if (i < 0 || self == NULL || self->gclen <= i)
	    XSRETURN_UNDEF;
	if (2 < items) {
	    flag = SvUV(ST(2));
	    if (flag == (flag & 255))
		self->gcstr[i].flag = (unsigned char)flag;
	    else
		warn("flag: unknown flag(s)");
	}
	RETVAL = (unsigned int)self->gcstr[i].flag;
    OUTPUT:
	RETVAL

gcstring_t *
item(self, ...)
	gcstring_t *self;
    PROTOTYPE: $;$
    PREINIT:
	int i;
    CODE:
	if (1 < items)
	    i = SvIV(ST(1));
	else
	    i = self->pos;
	if (i < 0 || self == NULL || self->gclen <= i)
	    XSRETURN_UNDEF;

	RETVAL = gctogcstring(self, self->gcstr + i);
    OUTPUT:
	RETVAL

gcstring_t *
join(self, ...)
	gcstring_t *self;
    PREINIT:
	size_t i;
	gcstring_t *str;
    CODE:
	switch (items) {
	case 0:
	    croak("Too few arguments");
	case 1:
	    RETVAL = gcstring_new(NULL, self->lbobj);
	    break;
	case 2:
	    RETVAL = SVtogcstring(ST(1), self->lbobj);
	    if (sv_isobject(ST(1)))
		RETVAL = gcstring_copy(RETVAL);
	    break;
	default:
	    RETVAL = SVtogcstring(ST(1), self->lbobj);
	    if (sv_isobject(ST(1)))
		RETVAL = gcstring_copy(RETVAL);
	    for (i = 2; i < items; i++) {
		gcstring_append(RETVAL, self);
		str = SVtogcstring(ST(i), self->lbobj);
		gcstring_append(RETVAL, str);
		if (!sv_isobject(ST(i)))
		    gcstring_destroy(str);
	    }
	    break;
	}
    OUTPUT:
	RETVAL

propval_t
lbclass(self, ...)
	gcstring_t *self;
    PROTOTYPE: $;$
    PREINIT:
	int i;
    CODE:
	if (1 < items) {
	    i = SvIV(ST(1));
	    if (i < 0)
		i += self->gclen;
	} else
	    i = self->pos;
	if (i < 0 || self == NULL || self->gclen <= i)
	    XSRETURN_UNDEF;
	RETVAL = (propval_t)self->gcstr[i].lbc;
    OUTPUT:
	RETVAL

propval_t
lbclass_ext(self, ...)
	gcstring_t *self;
    PROTOTYPE: $;$
    PREINIT:
	int i;
    CODE:
	if (1 < items) {
	    i = SvIV(ST(1));
	    if (i < 0)
		i += self->gclen;
	} else
	    i = self->pos;
	if (i < 0 || self == NULL || self->gclen <= i)
	    XSRETURN_UNDEF;
	if ((RETVAL = (propval_t)self->gcstr[i].elbc) == PROP_UNKNOWN)
	    RETVAL = (propval_t)self->gcstr[i].lbc;
	if (RETVAL == PROP_UNKNOWN)
	    XSRETURN_UNDEF;
    OUTPUT:
	RETVAL

size_t
length(self)
	gcstring_t *self;
    PROTOTYPE: $
    CODE:
	RETVAL = self->gclen;
    OUTPUT:
	RETVAL

gcstring_t *
next(self, ...)
	gcstring_t *self;
    PROTOTYPE: $;$;$
    PREINIT:
	gcchar_t *gc;
    CODE:
	if (gcstring_eos(self))
	    XSRETURN_UNDEF;
	gc = gcstring_next(self);
	RETVAL = gctogcstring(self, gc);
    OUTPUT:
	RETVAL

size_t
pos(self, ...)
	gcstring_t *self;
    PROTOTYPE: $;$
    CODE:
	if (1 < items)
	    gcstring_setpos(self, SvIV(ST(1)));
	RETVAL = self->pos;
    OUTPUT:
	RETVAL

#define lbobj self->lbobj
gcstring_t *
substr(self, offset, length=self->gclen, replacement=NULL)
	gcstring_t *self;
	int offset;
	int length;
	generic_string replacement;
    PROTOTYPE: $$;$;$
    CODE:
	RETVAL = gcstring_substr(self, offset, length);
	if (replacement != NULL)
	    if (gcstring_replace(self, offset, length, replacement) == NULL)
		croak("substr: %s", strerror(errno));
	if (RETVAL == NULL)
	    croak("substr: %s", strerror(errno));
    OUTPUT:
	RETVAL
