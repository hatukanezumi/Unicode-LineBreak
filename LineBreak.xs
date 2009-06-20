#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#ifdef USE_LIBTHAI
#    include "thai/thwchar.h"
#    include "thai/thwbrk.h"
#endif /* USE_LIBTHAI */

#define PROP_UNKNOWN ((propval_t)~0)

typedef unsigned int unichar_t;
typedef size_t propval_t;

typedef struct {
    unichar_t *str;
    size_t len;
} unistr_t;

typedef struct {
    unichar_t beg;
    unichar_t end;
    propval_t prop;
} mapent_t;

typedef struct {
    mapent_t *lbmap;
    size_t lbmapsiz;
    mapent_t *eamap;
    size_t eamapsiz;
    unsigned int options;
} linebreakObj;
#define LINEBREAK_OPTION_EASTASIAN_CONTEXT (1)

static propval_t LB_BK, LB_CR, LB_LF, LB_NL, LB_SP, LB_ZW, LB_WJ,
    LB_AL, LB_CM, LB_ID,
    LB_H2, LB_H3, LB_JL, LB_JV, LB_JT,
    LB_AI, LB_SA, LB_SG, LB_XX,
    LB_SAprepend, LB_SAbase, LB_SAextend;
static propval_t EA_Z, EA_N, EA_A, EA_W, EA_F;
#ifdef USE_LIBTHAI
static propval_t SCRIPT_Thai;
#endif /* USE_LIBTHAI */
static propval_t DIRECT;

static mapent_t *lbmap = NULL;
static size_t lbmapsiz = 0;
static mapent_t *eamap = NULL;
static size_t eamapsiz = 0;
static mapent_t *scriptmap = NULL;
static size_t scriptmapsiz = 0;
static propval_t **rulemap = NULL;
static size_t rulemapsiz = 0;

/*
 * Utilities
 */

static
unistr_t *_unistr_concat(unistr_t *buf, unistr_t *a, unistr_t *b)
{
    if (!buf) {
	if ((buf = malloc(sizeof(unistr_t))) == NULL)
	    return NULL;
    } else if (buf->str)
	free(buf->str);
    buf->str = NULL;
    buf->len = 0;

    if ((!a || !a->str || !a->len) && (!b || !b->str || !b->len)) {
	;
    } else if (!b || !b->str || !b->len) {
	if ((buf->str = malloc(sizeof(unichar_t) * a->len)) == NULL)
	    return NULL;
	memcpy(buf->str, a->str, sizeof(unichar_t) * a->len);
	buf->len = a->len;
    } else if (!a || !a->str || !a->len) {
	if ((buf->str = malloc(sizeof(unichar_t) * b->len)) == NULL)
	    return NULL;
	memcpy(buf->str, b->str, sizeof(unichar_t) * b->len);
	buf->len = b->len;
    } else {
	if ((buf->str = malloc(sizeof(unichar_t) * (a->len + b->len))) == NULL)
	    return NULL;
	memcpy(buf->str, a->str, sizeof(unichar_t) * a->len);
	memcpy(buf->str + a->len, b->str, sizeof(unichar_t) * b->len);
	buf->len = a->len + b->len;
    }
    return buf;
}

/*
 * _bsearch (map, mapsize, c)
 * Examine binary search on property map table with following structure:
 * [
 *     [start, stop, property_value],
 *     ...
 * ]
 * where start and stop stands for a continuous range of UCS ordinal those
 * are assigned property_value.
 */
static
propval_t _bsearch(mapent_t* map, size_t mapsiz, unichar_t c)
{
    mapent_t *top, *bot, *cur;
    propval_t result;

    if (!map || !mapsiz)
	return PROP_UNKNOWN;
    top = map;
    bot = map + mapsiz - 1;
    result = PROP_UNKNOWN;
    while (top <= bot) {
	cur = top + (bot - top) / 2;
	if (c < cur->beg)
	    bot = cur - 1;
	else if (cur->end < c)
	    top = cur + 1;
	else {
	    result = cur->prop;
	    break;
	}
    }
    return result;
}

/*
 * Exports
 */

propval_t eawidth(linebreakObj *obj, unichar_t c)
{
    propval_t ret;
    assert(eamap && eamapsiz);

    ret = _bsearch(obj->eamap, obj->eamapsiz, c);
    if (ret == PROP_UNKNOWN)
	ret = _bsearch(eamap, eamapsiz, c);
    if (ret == PROP_UNKNOWN)
	ret = EA_N;
    if (ret == EA_A) {
	if (obj->options & LINEBREAK_OPTION_EASTASIAN_CONTEXT)
	    return EA_F;
	return EA_N;
    }
    return ret;
}

propval_t _gbclass(linebreakObj *obj, unichar_t c)
{
    propval_t ret;
    assert(lbmap && lbmapsiz);

    ret = _bsearch(obj->lbmap, obj->lbmapsiz, c);
    if (ret == PROP_UNKNOWN)
	ret = _bsearch(lbmap, lbmapsiz, c);
    if (ret == PROP_UNKNOWN)
	ret = LB_XX;
    if (ret == LB_AI) {
	if (obj->options & LINEBREAK_OPTION_EASTASIAN_CONTEXT)
	    return LB_ID;
	else
	    return LB_AL;
    } else if (ret == LB_SG || ret == LB_XX)
	return LB_AL;
    return ret;
}
propval_t lbrule(linebreakObj *obj, propval_t b_idx, propval_t a_idx);

void gcinfo(linebreakObj *obj, unistr_t *str, size_t pos,
    propval_t *gclsptr, size_t *glenptr, size_t *elenptr)
{
    propval_t gcls = PROP_UNKNOWN;
    size_t glen, elen;
    unichar_t chr, nchr;
    propval_t cls, ncls;
    size_t str_len;

    if (!str || !str->str || !str->len) {
	*gclsptr = PROP_UNKNOWN;
	*glenptr = 0;
	*elenptr = 0;
	return;
    }

    chr = str->str[pos];
    cls = _gbclass(obj, chr);
    glen = 1;
    elen = 0;
    str_len = str->len;

    if (cls == LB_BK || cls == LB_LF || cls == LB_NL) {
	*gclsptr = cls;
	*glenptr = 1;
	*elenptr = 0;
	return;
    } else if (cls == LB_CR) {
	pos++;
	*gclsptr = cls;
	if (pos < str_len) {
	    chr = str->str[pos];
	    cls = _gbclass(obj, chr);
	    if (cls == LB_LF)
		glen++;
	}
	*glenptr = glen;
	*elenptr = 0;
	return;
    } else if (cls == LB_SP || cls == LB_ZW || cls == LB_WJ) {
        pos++;
        *gclsptr = cls;
        while (1) {
	    if (str_len <= pos)
		break;
	    chr = str->str[pos];
	    cls = _gbclass(obj, chr);
 	    if (cls != *gclsptr)
		break;
	    pos++;
	    glen++;
        }
	*glenptr = glen;
	*elenptr = 0;
	return;
    /* Hangul syllable block */
    } else if (cls == LB_H2 || cls == LB_H3 ||
	       cls == LB_JL || cls == LB_JV || cls == LB_JT) {
	pos++;
	gcls = cls;
	while (1) {
	    if (str_len <= pos)
		break;
	    nchr = str->str[pos];
	    ncls = _gbclass(obj, nchr);
	    if ((ncls == LB_H2 || ncls == LB_H3 ||
		 ncls == LB_JL || ncls == LB_JV || ncls == LB_JT) &&
		lbrule(obj, cls, ncls) != DIRECT) {
		pos++;
		glen++;
		cls = ncls;
		continue;
	    }
	    break;
	} 
    /* Extended grapheme base of South East Asian scripts */
    } else if (cls == LB_SAprepend || cls == LB_SAbase) {
#ifdef USE_LIBTHAI
	propval_t gscript ;
	gscript = _bsearch(scriptmap, scriptmapsiz, chr);
	if (gscript == 	SCRIPT_Thai) {
	    pos++;
	    *gclsptr = LB_SA;
	    while (1) {
		if (str_len <= pos)
		    break;
		chr = str->str[pos];
		gscript = _bsearch(scriptmap, scriptmapsiz, chr);
		if (gscript != SCRIPT_Thai)
		    break;
		pos++;
		glen++;
	    }
	    *glenptr = glen;
	    *elenptr = 0;
	    return;
	}
#endif /* USE_LIBTHAI */
	pos++;
	gcls = LB_AL;
	while (1) {
	    if (str_len <= pos)
		break;
	    if (cls == LB_SAbase)
		break;
	    nchr = str->str[pos];
	    ncls = _gbclass(obj, nchr);
	    if (ncls == LB_SAprepend || ncls == LB_SAbase) {
		pos++;
		glen++;
		cls = ncls;
		continue;
	    }
	    break;
	} 
    } else if (cls == LB_SAextend) {
	pos++;
	gcls = LB_CM;
    } else {
	pos++;
	gcls = cls;
    }

    while (1) {
	if (str_len <= pos)
	    break;
	chr = str->str[pos];
	cls = _gbclass(obj, chr);
	if (cls != LB_CM && cls != LB_SAextend)
	    break;
	pos++;
	elen++;
	if (gcls == PROP_UNKNOWN)
	    gcls = LB_CM;
    }
    *gclsptr = gcls;
    *glenptr = glen;
    *elenptr = elen;
    return;
}

propval_t lbclass(linebreakObj *obj, unichar_t c)
{
    propval_t ret;
    ret = _gbclass(obj, c);
#ifdef USE_LIBTHAI
    if ((ret == LB_SAprepend || ret == LB_SAbase || ret == LB_SAextend) &&
	_bsearch(scriptmap, scriptmapsiz, c) == SCRIPT_Thai)
	return LB_SA;
#endif /* USE_LIBTHAI */
    if (ret == LB_SAprepend || ret == LB_SAbase)
	return LB_AL;
    if (ret == LB_SAextend)
	return LB_CM;
    return ret;
}

propval_t lbrule(linebreakObj *obj, propval_t b_idx, propval_t a_idx)
{
    propval_t result = PROP_UNKNOWN;

    assert(rulemap && rulemapsiz);
    if (b_idx < 0 || rulemapsiz <= b_idx ||
	a_idx < 0 || rulemapsiz <= a_idx)
	;
    else
	result = rulemap[b_idx][a_idx];
    if (result == PROP_UNKNOWN)
	return DIRECT;
    return result;
}

size_t strsize(linebreakObj *obj,
    size_t len, unistr_t *pre, unistr_t *spc, unistr_t *str, size_t max)
{
    unistr_t spcstr = { 0, 0 };
    size_t length, idx, pos;

    if (max < 0)
	max = 0;
    if ((!spc || !spc->str || !spc->len) && (!str || !str->str || !str->len))
	return max? 0: len;

    if (_unistr_concat(&spcstr, spc, str) == NULL)
	return -1;
    length = spcstr.len;
    idx = 0;
    pos = 0;
    while (1) {
	size_t glen, elen, w, npos;
	unichar_t c;
	propval_t gcls, width;

	if (length <= pos)
	    break;
	gcinfo(obj, &spcstr, pos, &gcls, &glen, &elen);
	npos = pos + glen + elen;
	w = 0;

	/* Hangul syllable block */
	if (gcls == LB_H2 || gcls == LB_H3 ||
	    gcls == LB_JL || gcls == LB_JV || gcls == LB_JT) {
	    w = 2;
	    pos += glen;
	}
	while (pos < npos) {
	    c = spcstr.str[pos];
	    width = eawidth(obj, c);
	    if (width == EA_F || width == EA_W)
		w += 2;
	    else if (width != EA_Z)
		w += 1;
	    pos++;
	}

	if (max && max < len + w) {
	    idx -= spc->len;
	    if (idx < 0)
		idx = 0;
	    break;
	}
	idx += glen + elen;
	len += w;
    }

    if (spcstr.str)
	free(spcstr.str);
    return max? idx: len;
}

/*
 * Codes below belong to Perl layer...
 */

typedef struct {
    char *name;
    propval_t *ptr;
} constent_t;
static
constent_t _constent[] = {
    { "EA_Z", &EA_Z }, 
    { "EA_N", &EA_N }, 
    { "EA_A", &EA_A }, 
    { "EA_W", &EA_W }, 
    { "EA_F", &EA_F }, 
    { "LB_BK", &LB_BK },
    { "LB_CR", &LB_CR },
    { "LB_LF", &LB_LF },
    { "LB_NL", &LB_NL },
    { "LB_SP", &LB_SP },
    { "LB_ZW", &LB_ZW },
    { "LB_WJ", &LB_WJ },
    { "LB_AL", &LB_AL },
    { "LB_CM", &LB_CM },
    { "LB_ID", &LB_ID },
    { "LB_H2", &LB_H2 },
    { "LB_H3", &LB_H3 },
    { "LB_JL", &LB_JL },
    { "LB_JV", &LB_JV },
    { "LB_JT", &LB_JT },
    { "LB_AI", &LB_AI },
    { "LB_SA", &LB_SA },
    { "LB_SG", &LB_SG },
    { "LB_XX", &LB_XX },
    { "LB_SAprepend", &LB_SAprepend },
    { "LB_SAbase", &LB_SAbase },
    { "LB_SAextend", &LB_SAextend },
#ifdef USE_LIBTHAI
    { "SCRIPT_Thai", &SCRIPT_Thai },
#endif /* USE_LIBTHAI */
    { "DIRECT", &DIRECT },
    { NULL, NULL },
};

static
mapent_t *_loadmap(mapent_t *propmap, SV *mapref, size_t *mapsiz)
{
    size_t n;
    AV * map;
    AV * ent;

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
	    propmap[n].prop = SvIV(*av_fetch(ent, 2, 0));
	}
    }
    return propmap;
}

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

    utf8len = SvCUR(str);
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
    for (p = wstr, i = 0; unistr.str && i < unistr.len; i++)
	*(p++) = (unistr.str)[i];
    *p = 0;
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
linebreakObj *_selftoobj(SV *self)
{
    SV **svp;
    if ((svp = hv_fetch((HV *)SvRV(self), "_obj", 4, 0)) == NULL)
	return NULL;
    return INT2PTR(linebreakObj *, SvUV(*svp));
}

MODULE = Unicode::LineBreak	PACKAGE = Unicode::LineBreak	

void
_loadconst(...)
    PROTOTYPE: @
    PREINIT:
	size_t i;
	constent_t *p;
	char *name;
	int r;
    CODE:
	p = _constent;
	while (p->name) {
	    *(p->ptr) = PROP_UNKNOWN;
	    for (i = 0; i < items; i++) {
		name = (char *)SvPV_nolen(ST(i));
		if (strcmp(name, p->name) == 0) {
		    dSP;
		    ENTER; SAVETMPS; PUSHMARK(SP);
		    XPUSHs(sv_2mortal(newSViv(0)));
		    PUTBACK;
		    r = call_pv(name, G_SCALAR | G_NOARGS);
		    SPAGAIN;
		    if (r != 1)
			croak("_loadconst: Internal error");
		    *(p->ptr) = POPi;
		    PUTBACK; FREETMPS; LEAVE;
		    break;
		}
	    }
	    p++;		
	}

void
_loadlb(mapref)
	SV *mapref;
    CODE:
	lbmap = _loadmap(lbmap, mapref, &lbmapsiz);

void
_loadea(mapref)
	SV *mapref;
    CODE:
	eamap = _loadmap(eamap, mapref, &eamapsiz);

void
_loadscript(mapref)
	SV *mapref;
    CODE:
	scriptmap = _loadmap(scriptmap, mapref, &scriptmapsiz);

void
_loadrule(mapref)
	SV *	mapref;
    PROTOTYPE: $
    INIT:
	size_t n, m;
	AV * rule;
	AV * ent;
	propval_t prop;
    CODE:
	if (rulemap && rulemapsiz) {
	    for (n = 0; n < rulemapsiz; n++)
		free(rulemap[n]);
	    free(rulemap);
	}
	rule = (AV *)SvRV(mapref);
	rulemapsiz = av_len(rule) + 1;
	if (rulemapsiz <= 0) {
	    rulemapsiz = 0;
	    rulemap = NULL;
	} else if ((rulemap = malloc(sizeof(propval_t **) * rulemapsiz))
		   == NULL) {
	    rulemapsiz = 0;
	    rulemap = NULL;
	    croak("_loadrule: Can't allocate memory");
	} else {
	    for (n = 0; n < rulemapsiz; n++) {
		if ((rulemap[n] = malloc(sizeof(propval_t) * rulemapsiz))
		    == NULL) {
		    rulemapsiz = 0;
		    rulemap = NULL;
		    croak("_loadrule: Can't allocate memory");
		} else {
		    ent = (AV *)SvRV(*av_fetch(rule, n, 0));
		    for (m = 0; m < rulemapsiz; m++) {
			prop = SvIV(*av_fetch(ent, m, 1));
			rulemap[n][m] = prop;
		    }
		}		    
	    }
	}

void
_config(self)
	SV *self;
    PROTOTYPE: $
    INIT:
	SV **svp;
	char *opt;
	size_t mapsiz;
	linebreakObj *obj;
    CODE:
	if ((obj = _selftoobj(self)) == NULL) {
	    if ((obj = malloc(sizeof(linebreakObj))) == NULL)
		croak("_config: Cannot allocate memory");
	    else
		obj->lbmap = obj->eamap = NULL;
	    if (hv_store((HV *)SvRV(self), "_obj", 4,
			 newSVuv(PTR2UV(obj)), 0) == NULL)
		croak("_config: Internal error");
	}

	if ((svp = hv_fetch((HV *)SvRV(self), "_lbmap", 6, 0)) == NULL) {
	    if (obj->lbmap) {
		free(obj->lbmap);
		obj->lbmap = NULL;
		obj->lbmapsiz = 0;
	    }
	} else {
	    obj->lbmap = _loadmap(obj->lbmap, *svp, &mapsiz);
	    obj->lbmapsiz = mapsiz;
	}
	if ((svp = hv_fetch((HV *)SvRV(self), "_eamap", 6, 0)) == NULL) {
	    if (obj->eamap) {
		free(obj->eamap);
		obj->eamap = NULL;
		obj->eamapsiz = 0;
	    }
	} else {
	    obj->eamap = _loadmap(obj->eamap, *svp, &mapsiz);
	    obj->eamapsiz = mapsiz;
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
	linebreakObj *obj;
    CODE:
	obj = _selftoobj(self);
	if (!obj)
	    return;
	if (obj->eamap) free(obj->eamap);
	if (obj->lbmap) free(obj->lbmap);
	free(obj);
	return;

propval_t
eawidth(self, str)
	SV *self;
	SV *str;
    PROTOTYPE: $$
    INIT:
	linebreakObj *obj;
	unichar_t c;
	propval_t prop;
    CODE:
	/* FIXME: return undef unless (defined $str and length $str); */
	if (!SvCUR(str))
	    XSRETURN_UNDEF;
	obj = _selftoobj(self);
	c = utf8_to_uvuni((U8 *)SvPV_nolen(str), NULL);
	prop = eawidth(obj, c);

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
	linebreakObj *obj;
	unichar_t c;
	propval_t prop;
    CODE:
	/* FIXME: return undef unless (defined $str and length $str); */
	if (!SvCUR(str))
	    XSRETURN_UNDEF;
	obj = _selftoobj(self);
	c = utf8_to_uvuni((U8 *)SvPV_nolen(str), NULL);
	prop = lbclass(obj, c);

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
	linebreakObj *obj;
	propval_t prop;
    CODE:
	if (!SvOK(ST(1)) || !SvOK(ST(2)))
	    XSRETURN_UNDEF;
	obj = _selftoobj(self);
	prop = lbrule(obj, b_idx, a_idx);

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
	linebreakObj *obj;
	unistr_t unipre = {0, 0}, unispc = {0, 0}, unistr = {0, 0};
	size_t max;
    CODE:
	obj = _selftoobj(self);
	_utf8touni(&unipre, pre);
	_utf8touni(&unispc, spc);
	_utf8touni(&unistr, str);
	if (5 < items)
	    max = SvUV(ST(5));
	else
	    max = 0;

	RETVAL = strsize(obj, len, &unipre, &unispc, &unistr, max);

	if (unipre.str) free(unipre.str);
	if (unispc.str) free(unispc.str);
	if (unistr.str) free(unistr.str);
	if (RETVAL == -1)
	    croak("strsize: Can't allocate memory");
    OUTPUT:
	RETVAL

void
gcinfo(self, str, pos)
	SV *self;
	SV *str;
	size_t pos;
    INIT:
	linebreakObj *obj;
	unistr_t unistr = {0, 0};
	propval_t gcls;
	size_t glen, elen;
    PPCODE:
	if (!SvCUR(str))
	    XSRETURN_UNDEF;
	obj = _selftoobj(self);
	_utf8touni(&unistr, str);
	gcinfo(obj, &unistr, pos, &gcls, &glen, &elen);
	XPUSHs(sv_2mortal(newSViv(gcls)));
	XPUSHs(sv_2mortal(newSViv(glen)));
	XPUSHs(sv_2mortal(newSViv(elen)));

	if (unistr.str) free(unistr.str);
	return;

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
