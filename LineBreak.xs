#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include "linebreak.h"

extern linebreak_t *linebreak_new();
extern void linebreak_destroy(linebreak_t *);
extern propval_t linebreak_eawidth(linebreak_t *, unichar_t);
extern propval_t linebreak_lbclass(linebreak_t *, unichar_t);
extern propval_t linebreak_lbrule(propval_t, propval_t);
extern size_t linebreak_strsize(linebreak_t *, size_t, unistr_t *,
				gcstring_t *, gcstring_t *, size_t);
extern char *linebreak_unicode_version;
extern gcstring_t *gcstring_new(unistr_t *, linebreak_t *);
extern gcstring_t *gcstring_copy(gcstring_t *);
extern void gcstring_destroy(gcstring_t *);
/* extern gcstring_t *gcstring_append(gcstring_t *, gcstring_t *); */
extern size_t gcstring_columns(gcstring_t *);
extern gcstring_t *gcstring_concat(gcstring_t *, gcstring_t *);
extern int gcstring_eot(gcstring_t *);
extern gcchar_t *gcstring_next(gcstring_t *);
extern void gcstring_prev(gcstring_t *);
extern void gcstring_reset(gcstring_t *);
extern gcstring_t *gcstring_substr(gcstring_t *, int, int);

/*
 * 
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

/*
 * Create Unicode string from Perl utf8-flagged string.
 */
static
unistr_t *_utf8touni(unistr_t *buf, SV *str)
{
    U8 *utf8, *utf8ptr;
    STRLEN utf8len, unilen, len;
    unichar_t *uniptr;

    if (!buf) {
	if ((buf = malloc(sizeof(unistr_t))) == NULL)
	    croak("_utf8touni: Memory exausted");
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
	croak("_utf8touni: Memory exausted");

    utf8ptr = utf8;
    uniptr = buf->str;
    while (utf8ptr < utf8 + utf8len) {
	*uniptr = (unichar_t)utf8_to_uvuni(utf8ptr, &len);
	if (len < 0)
	    croak("_utf8touni: Not well-formed UTF-8");
	if (len == 0)
	    croak("_utf8touni: Internal error");
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
SV *_unitoutf8(unistr_t *unistr, size_t uniidx, size_t unilen)
{
    U8 *buf = NULL, *newbuf;
    STRLEN utf8len;
    unichar_t *uniptr;
    SV *utf8;

    utf8len = 0;
    uniptr = unistr->str + uniidx;
    while (uniptr < unistr->str + uniidx + unilen &&
	   uniptr < unistr->str + unistr->len) {
        if ((newbuf = realloc(buf,
                              sizeof(U8) * (utf8len + UTF8_MAXBYTES + 1)))
            == NULL) {
            croak("_unitoutf8: Cannot allocate memory");
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


#ifdef USE_LIBTHAI

static
wchar_t *_utf8towstr(SV *str)
{
    unistr_t unistr = {0, 0};
    wchar_t *wstr, *p;
    size_t i;

    _utf8touni(&unistr, str);
    if ((wstr = malloc(sizeof(wchar_t) * (unistr.len + 1))) == NULL)
	croak("_utf8towstr: Cannot allocate memory");
    if (sizeof(wchar_t) == sizeof(unichar_t)) {
	memcpy(wstr, unistr.str, sizeof(wchar_t) * unistr.len);
	wstr[unistr.len] = 0;
    } else {
	for (p = wstr, i = 0; unistr.str && i < unistr.len; i++)
	    *(p++) = (unistr.str)[i];
	*p = 0;
    }
    if (unistr.str) free(unistr.str);
    return wstr;
}

static
SV *_wstrtoutf8(wchar_t *unistr, size_t unilen)
{
    U8 *buf = NULL, *newbuf;
    STRLEN utf8len;
    wchar_t *uniptr;
    SV *utf8;

    utf8len = 0;
    uniptr = unistr;
    while (uniptr < unistr + unilen && *uniptr) {
	if ((newbuf = realloc(buf,
			      sizeof(U8) * (utf8len + UTF8_MAXBYTES + 1)))
	    == NULL) {
	    croak("_wstrtoutf8: Cannot allocate memory");
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

#endif /* USE_LIBTHAI */

static
linebreak_t *_selftoobj(SV *self)
{
    SV **svp;
    if ((svp = hv_fetch((HV *)SvRV(self), "_obj", 4, 0)) == NULL)
	return NULL;
    return INT2PTR(linebreak_t *, SvUV(*svp));
}

MODULE = Unicode::LineBreak	PACKAGE = Unicode::LineBreak	

void
_config(self)
	SV *self;
    PROTOTYPE: $
    INIT:
	SV **svp;
	char *opt;
	size_t mapsiz;
	linebreak_t *obj;
    CODE:
	if ((obj = _selftoobj(self)) == NULL) {
	    if ((obj = linebreak_new()) == NULL)
		croak("_config: Cannot allocate memory");
	    else
		obj->map = NULL;
	    if (hv_store((HV *)SvRV(self), "_obj", 4,
			 newSVuv(PTR2UV(obj)), 0) == NULL)
		croak("_config: Internal error");
	}

	if ((svp = hv_fetch((HV *)SvRV(self), "_map", 4, 0)) == NULL) {
	    if (obj->map) {
		free(obj->map);
		obj->map = NULL;
		obj->mapsiz = 0;
	    }
	} else {
	    obj->map = _loadmap(obj->map, *svp, &mapsiz);
	    obj->mapsiz = mapsiz;
	}

	obj->options = 0;
	if ((svp = hv_fetch((HV *)SvRV(self), "Context", 7, 0)) != NULL)
	    opt = (char *)SvPV_nolen(*svp);
	else
	    opt = NULL;
	if (opt && strcmp(opt, "EASTASIAN") == 0)
	    obj->options |= LINEBREAK_OPTION_EASTASIAN_CONTEXT;

void
DESTROY(self)
	SV *self;
    PROTOTYPE: $
    INIT:
	linebreak_t *obj;
    CODE:
	obj = _selftoobj(self);
	linebreak_destroy(obj);

propval_t
eawidth(self, str)
	SV *self;
	SV *str;
    PROTOTYPE: $$
    INIT:
	linebreak_t *obj;
	unichar_t c;
	propval_t prop;
    CODE:
	/* FIXME: return undef unless (defined $str and length $str); */
	if (!SvCUR(str))
	    XSRETURN_UNDEF;
	obj = _selftoobj(self);
	c = utf8_to_uvuni((U8 *)SvPV_nolen(str), NULL);
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
	/* FIXME: return undef unless (defined $str and length $str); */
	obj = _selftoobj(self);
	if (sv_isobject(str)) {
	    gcstr = (gcstring_t *)SvIV(SvRV(str));
	    if (!gcstring_eot(gcstr))
		prop = gcstr->gcstr[gcstr->pos].lbc;
	    else
		prop = PROP_UNKNOWN;
	} else {
	    if (!SvCUR(str))
		XSRETURN_UNDEF;
	    c = utf8_to_uvuni((U8 *)SvPV_nolen(str), NULL);
	    prop = linebreak_lbclass(obj, c);
	}
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
	obj = _selftoobj(self);
	prop = linebreak_lbrule(b_idx, a_idx);

	if (prop == PROP_UNKNOWN)
	    XSRETURN_UNDEF;
	RETVAL = prop;
    OUTPUT:
	RETVAL

size_t
strsize(self, len, pre, spc, str, ...)
	SV *self;
	size_t len;
	SV *pre;
	SV *spc;
	SV *str;
    PROTOTYPE: $$$$$;$
    INIT:
	linebreak_t *lbobj;
	/* unistr_t unipre = {0, 0}; */
	unistr_t unispc = {0, 0}, unistr = {0, 0};
	/* gcstring_t *gcpre; */
	gcstring_t *gcspc, *gcstr;
	size_t max;
    CODE:
	lbobj = _selftoobj(self);
	/*
	if (!sv_isobject(pre)) {
	    _utf8touni(&unipre, pre);
	    gcpre = gcstring_new(&unipre, lbobj);
	} else
	    gcpre = (gcstring_t *)SvIV(SvRV(pre));
	 */
	if (!sv_isobject(spc)) {
	    _utf8touni(&unispc, spc);
	    gcspc = gcstring_new(&unispc, lbobj);
	} else
	    gcspc = (gcstring_t *)SvIV(SvRV(spc));
	if (!sv_isobject(str)) {
	    _utf8touni(&unistr, str);
	    gcstr = gcstring_new(&unistr, lbobj);
	} else
	    gcstr = (gcstring_t *)SvIV(SvRV(str));

	if (5 < items)
	    max = SvUV(ST(5));
	else
	    max = 0;

	RETVAL = linebreak_strsize(lbobj, len, /* gcpre */NULL, gcspc, gcstr,
				   max);

	/* gcstring_destroy(gcpre); */
	gcstring_destroy(gcspc);
	gcstring_destroy(gcstr);
	if (RETVAL == -1)
	    croak("strsize: Can't allocate memory");
    OUTPUT:
	RETVAL

char *
UNICODE_VERSION()
    CODE:
	RETVAL = linebreak_unicode_version;
    OUTPUT:
	RETVAL

MODULE = Unicode::LineBreak	PACKAGE = Unicode::LineBreak::SouthEastAsian

void
break(str)
	SV *str;
    PROTOTYPE: $
    INIT:
#ifdef USE_LIBTHAI
	SV *utf8;
	int pos;
	wchar_t *line = NULL, *p;
#endif /* USE_LIBTHAI */
    PPCODE:
	if (!SvOK(str))
	    return;
#ifdef USE_LIBTHAI
	line = _utf8towstr(str);
	p = line;
	while (*p && th_wbrk(p, &pos, 1)) {
	    utf8 = _wstrtoutf8(p, pos);
	    XPUSHs(sv_2mortal(utf8));
	    p += pos;
	}
	if (*p) {
	    for (pos = 0; p[pos]; pos++) ;
	    utf8 = _wstrtoutf8(p, pos);
	    XPUSHs(sv_2mortal(utf8));
	}

	free(line);
#else
	XPUSHs(sv_2mortal(str));
#endif /* USE_LIBTHAI */

void
break_indexes(str)
	SV *str;
    PROTOTYPE: $
    INIT:
#ifdef USE_LIBTHAI
	int pos;
	wchar_t *line = NULL, *p;
#endif /* USE_LIBTHAI */
    PPCODE:
	if (!SvOK(str))
	    return;
#ifdef USE_LIBTHAI
	line = _utf8towstr(str);
	p = line;
	while (*p && th_wbrk(p, &pos, 1)) {
	    XPUSHs(sv_2mortal(newSViv(p-line+pos)));
	    p += pos;
	}

	free(line);
#endif /* USE_LIBTHAI */

char *
supported()
    PROTOTYPE:
    CODE:
#ifdef USE_LIBTHAI
	RETVAL = "Thai:" USE_LIBTHAI;
#else
	XSRETURN_UNDEF;
#endif /* USE_LIBTHAI */
    OUTPUT:
	RETVAL

MODULE = Unicode::LineBreak	PACKAGE = Unicode::GCString	

SV *
new(self, str, ...)
	SV *self;
	SV *str;
    PROTOTYPE: $$;$
    INIT:
	gcstring_t *gcstr;
	linebreak_t *lb;
	unistr_t unistr = {0, 0};
	SV *ref, *obj;
    CODE:
	if (!SvOK(str) || !SvCUR(str)) /* prevent segfault. */
	    XSRETURN_UNDEF;
	if (2 < items)
	    lb = _selftoobj(ST(2));
	else
	    lb = NULL;
	_utf8touni(&unistr, str);
	gcstr = gcstring_new(&unistr, lb);
	ref = newSViv(0);
	obj = newSVrv(ref, "Unicode::GCString");
	sv_setiv(obj, (IV)gcstr);
	SvREADONLY_on(obj);
	RETVAL = ref;
    OUTPUT:
	RETVAL

void
DESTROY(self)
	SV *self;
    PROTOTYPE: $
    INIT:
	gcstring_t *gcstr;
    CODE:
	if (!sv_isobject(self))
	    return;
	gcstr = (gcstring_t *)SvIV(SvRV(self));    
	if (gcstr == NULL)
	    return;
	gcstring_destroy(gcstr);

void
as_array(self)
	SV *self;
    PROTOTYPE: $
    INIT:
	gcstring_t *gcstr;
	size_t i;
	SV *s;
    PPCODE:
	if (!sv_isobject(self))
	   return;
	gcstr = (gcstring_t *)SvIV(SvRV(self));    
	if (gcstr != NULL)
	    for (i = 0; i < gcstr->gclen; i++) {
		AV* a;
		a = newAV();
		s = _unitoutf8((unistr_t *)gcstr,
			       gcstr->gcstr[i].idx, gcstr->gcstr[i].len);
		av_push(a, s);
		av_push(a, newSViv(gcstr->gcstr[i].col));
		av_push(a, newSViv(gcstr->gcstr[i].lbc));
		if (gcstr->gcstr[i].flag)
		    av_push(a, newSVuv((unsigned int)gcstr->gcstr[i].flag));
		XPUSHs(sv_2mortal(newRV_inc((SV *)a)));
	    }		

SV *
as_string(self)
	SV *self;
    PROTOTYPE: $;$;$
    INIT:
	gcstring_t *gcstr;
    CODE:
	if (!sv_isobject(self))
	   return;
	gcstr = (gcstring_t *)SvIV(SvRV(self));    
	RETVAL = _unitoutf8((unistr_t *)gcstr, 0, gcstr->len);
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
	gcstr = (gcstring_t *)SvIV(SvRV(self));    
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
	SV *ref, *obj;
	unistr_t unistr = {0, 0};
    CODE:
	if (!sv_isobject(self))
	   return;
	gcstr = (gcstring_t *)SvIV(SvRV(self));    
	if (!sv_isobject(str)) {
	    _utf8touni(&unistr, str);
	    appe = gcstring_new(&unistr, gcstr->lbobj);
	} else
	    appe = (gcstring_t *)SvIV(SvRV(str));    
	if (2 < items && SvOK(ST(2)) && SvIV(ST(2)))
	    ret = gcstring_concat(appe, gcstr);
	else
	    ret = gcstring_concat(gcstr, appe);
	if (!sv_isobject(str))
	    gcstring_destroy(appe);
	ref = newSViv(0);
	obj = newSVrv(ref, "Unicode::GCString");
	sv_setiv(obj, (IV)ret);
	SvREADONLY_on(obj);
	RETVAL = ref;
    OUTPUT:
	RETVAL

SV *
copy(self)
	SV *self;
    PROTOTYPE: $
    INIT:
	gcstring_t *gcstr, *ret;
	SV *ref, *obj;
    CODE:
	if (!sv_isobject(self))
	   return;
	gcstr = (gcstring_t *)SvIV(SvRV(self));    
	ret = gcstring_copy(gcstr);
	ref = newSViv(0);
	obj = newSVrv(ref, "Unicode::GCString");
	sv_setiv(obj, (IV)ret);
	SvREADONLY_on(obj);
	RETVAL = ref;
    OUTPUT:
	RETVAL

int
eot(self)
	SV *self;
    INIT:
	gcstring_t *gcstr;
    CODE:
	if (!sv_isobject(self))
	   XSRETURN_UNDEF;
	gcstr = (gcstring_t *)SvIV(SvRV(self));    
	if (gcstr == NULL)
	    RETVAL = 0;
	else
	    RETVAL = gcstring_eot(gcstr);
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
	   return;
	gcstr = (gcstring_t *)SvIV(SvRV(self));    
	if (1 < items)
	    i = SvIV(ST(1));
	else
	    i = gcstr->pos;
	if (i < 0 || gcstr == NULL || gcstr->gclen <= i)
	    XSRETURN_UNDEF;
	if (2 < items) {
	    flag = SvUV(ST(2));
	    if (flag == (flag & LINEBREAK_FLAGS))
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
	AV* a;
	SV *s;
    CODE:
	if (!sv_isobject(self))
	   return;
	gcstr = (gcstring_t *)SvIV(SvRV(self));    
	if (1 < items)
	    i = SvIV(ST(1));
	else
	    i = gcstr->pos;
	if (i < 0 || gcstr == NULL || gcstr->gclen <= i)
	    XSRETURN_UNDEF;

	a = newAV();
	s = _unitoutf8((unistr_t *)gcstr,
		       gcstr->gcstr[i].idx, gcstr->gcstr[i].len);
	av_push(a, s);
	av_push(a, newSViv(gcstr->gcstr[i].col));
	av_push(a, newSViv(gcstr->gcstr[i].lbc));
	if (gcstr->gcstr[i].flag)
	    av_push(a, newSVuv((unsigned int)gcstr->gcstr[i].flag));
	RETVAL = newRV_inc((SV *)a);
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
	gcstr = (gcstring_t *)SvIV(SvRV(self));    
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
	AV *a;
	SV *s;
    CODE:
	if (!sv_isobject(self))
	    XSRETURN_UNDEF;
	gcstr = (gcstring_t *)SvIV(SvRV(self));    
	if (gcstring_eot(gcstr))
	    XSRETURN_UNDEF;
	gc = gcstring_next(gcstr);
	a = newAV();
	s = _unitoutf8((unistr_t *)gcstr, gc->idx, gc->len);
	av_push(a, s);
	av_push(a, newSViv(gc->col));
	av_push(a, newSViv(gc->lbc));
	if (gc->flag)
	    av_push(a, newSVuv((unsigned int)gc->flag));
	RETVAL = newRV_inc((SV *)a);
    OUTPUT:
	RETVAL

void
prev(self)
	SV *self;
    PROTOTYPE: $
    INIT:
	gcstring_t *gcstr;
    CODE:
	if (!sv_isobject(self))
	   return;
	gcstr = (gcstring_t *)SvIV(SvRV(self));    
	if (gcstr == NULL)
	    return;
	else
	    gcstring_prev(gcstr);

void
reset(self)
	SV *self;
    PROTOTYPE: $
    INIT:
	gcstring_t *gcstr;
    CODE:
	if (!sv_isobject(self))
	   return;
	gcstr = (gcstring_t *)SvIV(SvRV(self));    
	if (gcstr == NULL)
	    return;
	else
	    gcstring_reset(gcstr);

SV *
substr(self, offset, ...)
	SV *self;
	int offset;
    PROTOTYPE: $$;$
    INIT:
	int length;
	gcstring_t *gcstr, *ret;
	SV *obj, *ref;
    CODE:
	if (!sv_isobject(self))
	   return;
	gcstr = (gcstring_t *)SvIV(SvRV(self));    
	if (2 < items)
	    length = SvIV(ST(2));
	else
	    length = gcstr->gclen;

	ret = gcstring_substr(gcstr, offset, length);
	ref = newSViv(0);
	obj = newSVrv(ref, "Unicode::GCString");
	sv_setiv(obj, (IV)ret);
	SvREADONLY_on(obj);
	RETVAL = ref;
    OUTPUT:
	RETVAL
