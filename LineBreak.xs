#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include "linebreak.h"

extern char *linebreak_unicode_version;
extern mapent_t linebreak_lbmap[];
extern size_t linebreak_lbmapsiz;
extern const unsigned short linebreak_lbhash[];
extern const unsigned short linebreak_lbhashidx[];
extern size_t linebreak_lbhashsiz;
extern mapent_t linebreak_eamap[];
extern size_t linebreak_eamapsiz;
extern const unsigned short linebreak_eahash[];
extern const unsigned short linebreak_eahashidx[];
extern size_t linebreak_eahashsiz;
extern mapent_t linebreak_scriptmap[];
extern size_t linebreak_scriptmapsiz;
extern propval_t linebreak_rulemap[32][32];
extern size_t linebreak_rulemapsiz;

#define HASH_MODULUS (1U << 11)
#define isCJKIdeograph(c) \
	( (0x3400 <= (c) && (c) <= 0x4DBF) ||	\
	  (0x4E00 <= (c) && (c) <= 0x9FFF) ||	\
	  (0xF900 <= (c) && (c) <= 0xFAFF) ||	\
	  (0x20000 <= (c) && (c) <= 0x2FFFD) ||	\
	  (0x30000 <= (c) && (c) <= 0x3FFFD) )
#define isHangulSyllable(c) \
	(0xAC00 <= (c) && (c) <= 0xD7A3)
#define isPrivateUse(c) \
	( (0xE000 <= (c) && (c) <= 0xF8FF) ||	\
	  (0xF0000 <= (c) && (c) <= 0xFFFFD) ||	\
	  (0x100000 <= (c) && (c) <= 0x10FFFD) )
#define isTag(c) \
	(0xE0000 <= (c) && (c) <= 0xE0FFF)
#define isDefaultIgnorable(c) \
	( (0x2060 <= (c) && (c) <= 0x206F) ||	\
	  (0xFFF0 <= (c) && (c) <= 0xFFFB) ||	\
	  isTag(c) )
#define isYiSyllable(c) \
	(0xA000 <= (c) && (c) <= 0xA48C && (c) != 0xA015)

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

    if (!map || !mapsiz)
	return PROP_UNKNOWN;
    top = map;
    bot = map + mapsiz - 1;
    while (top <= bot) {
	cur = top + (bot - top) / 2;
	if (c < cur->beg)
	    bot = cur - 1;
	else if (cur->end < c)
	    top = cur + 1;
	else
	    return cur->prop;
    }
    return PROP_UNKNOWN;
}

/*
 * _hsearch (map, hash, hashidx, hashsiz, c)
 * Examine hash table search.
 */
static
propval_t _hsearch(mapent_t *map,
		   const unsigned short* hash, const unsigned short* hashidx,
		   size_t hashsiz, unichar_t c)
{
    size_t key, idx, end;
    mapent_t *cur;

    key = c % HASH_MODULUS;
    idx = hashidx[key];
    if (hashsiz <= idx)
	return PROP_UNKNOWN;
    end = hashidx[key + 1];

    for ( ; idx < end; idx++) {
	cur = map + (size_t)(hash[idx]);
	if (c < cur->beg)
	    break;
	else if (c <= cur->end)
	    return cur->prop;
    }
    return PROP_UNKNOWN;
}

/*
 * Exports
 */

propval_t linebreak_eawidth(linebreakObj *obj, unichar_t c)
{
    propval_t ret;

    if (isCJKIdeograph(c) || isHangulSyllable(c) || isYiSyllable(c))
	return EA_W;
    if (isDefaultIgnorable(c))
	return EA_Z;

    if (isPrivateUse(c))
	ret = EA_A;
    else {
	assert(linebreak_eamap && linebreak_eamapsiz);
	ret = _bsearch(obj->eamap, obj->eamapsiz, c);
	if (ret == PROP_UNKNOWN)
	    ret = _hsearch(linebreak_eamap, linebreak_eahash, linebreak_eahashidx, linebreak_eahashsiz, c);
	if (ret == PROP_UNKNOWN)
	    ret = EA_N;
    }
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

    if (isCJKIdeograph(c) || isYiSyllable(c))
	return LB_ID;
    if (isHangulSyllable(c)) {
	if (c % 28 == 16)
	    return LB_H2;
	else
	    return LB_H3;
    }
    if (isTag(c))
	return LB_CM;

    if (isPrivateUse(c))
	ret = LB_XX;
    else {
	assert(linebreak_lbmap && linebreak_lbmapsiz);
	ret = _bsearch(obj->lbmap, obj->lbmapsiz, c);
	if (ret == PROP_UNKNOWN)
	    ret = _hsearch(linebreak_lbmap, linebreak_lbhash, linebreak_lbhashidx, linebreak_lbhashsiz, c);
	if (ret == PROP_UNKNOWN)
	    ret = LB_XX;
    }
    if (ret == LB_AI) {
	if (obj->options & LINEBREAK_OPTION_EASTASIAN_CONTEXT)
	    return LB_ID;
	else
	    return LB_AL;
    } else if (ret == LB_SG || ret == LB_XX)
	return LB_AL;
    return ret;
}
propval_t linebreak_lbrule(linebreakObj *obj, propval_t b_idx, propval_t a_idx);

void linebreak_gcinfo(linebreakObj *obj, unistr_t *str, size_t pos,
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
		linebreak_lbrule(obj, cls, ncls) != DIRECT) {
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
	gscript = _bsearch(linebreak_scriptmap, linebreak_scriptmapsiz, chr);
	if (gscript == 	SCRIPT_Thai) {
	    pos++;
	    *gclsptr = LB_SA;
	    while (1) {
		if (str_len <= pos)
		    break;
		chr = str->str[pos];
		gscript = _bsearch(linebreak_scriptmap, linebreak_scriptmapsiz, chr);
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

propval_t linebreak_lbclass(linebreakObj *obj, unichar_t c)
{
    propval_t ret;
    ret = _gbclass(obj, c);
#ifdef USE_LIBTHAI
    if ((ret == LB_SAprepend || ret == LB_SAbase || ret == LB_SAextend) &&
	_bsearch(linebreak_scriptmap, linebreak_scriptmapsiz, c) == SCRIPT_Thai)
	return LB_SA;
#endif /* USE_LIBTHAI */
    if (ret == LB_SAprepend || ret == LB_SAbase)
	return LB_AL;
    if (ret == LB_SAextend)
	return LB_CM;
    return ret;
}

propval_t linebreak_lbrule(linebreakObj *obj, propval_t b_idx, propval_t a_idx)
{
    propval_t result = PROP_UNKNOWN;

    assert(linebreak_rulemap && linebreak_rulemapsiz);
    if (b_idx < 0 || linebreak_rulemapsiz <= b_idx ||
	a_idx < 0 || linebreak_rulemapsiz <= a_idx)
	;
    else
	result = linebreak_rulemap[b_idx][a_idx];
    if (result == PROP_UNKNOWN)
	return DIRECT;
    return result;
}

size_t linebreak_strsize(linebreakObj *obj,
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
	linebreak_gcinfo(obj, &spcstr, pos, &gcls, &glen, &elen);
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
	    width = linebreak_eawidth(obj, c);
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
	linebreakObj *obj;
	unichar_t c;
	propval_t prop;
    CODE:
	/* FIXME: return undef unless (defined $str and length $str); */
	if (!SvCUR(str))
	    XSRETURN_UNDEF;
	obj = _selftoobj(self);
	c = utf8_to_uvuni((U8 *)SvPV_nolen(str), NULL);
	prop = linebreak_lbclass(obj, c);

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
	prop = linebreak_lbrule(obj, b_idx, a_idx);

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

	RETVAL = linebreak_strsize(obj, len, &unipre, &unispc, &unistr, max);

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
	linebreak_gcinfo(obj, &unistr, pos, &gcls, &glen, &elen);
	XPUSHs(sv_2mortal(newSViv(gcls)));
	XPUSHs(sv_2mortal(newSViv(glen)));
	XPUSHs(sv_2mortal(newSViv(elen)));

	if (unistr.str) free(unistr.str);
	return;

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
