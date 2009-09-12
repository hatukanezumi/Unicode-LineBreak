#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include "linebreak.h"

extern char *linebreak_unicode_version;
extern mapent_t linebreak_map[];
extern const unsigned short linebreak_hash[];
extern const unsigned short linebreak_index[];
extern size_t linebreak_hashsiz;
extern propval_t *linebreak_rules[];
extern size_t linebreak_rulessiz;
extern propval_t *gcstring_rules[];
extern size_t gcstring_rulessiz;

#define HASH_MODULUS (1U << 13)

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
 * _charprop (obj, c, *lbcptr, *eawptr, *gbcptr, *scrptr)
 * Examine hash table search.
 */
static mapent_t
PROPENT_HAN =        {0, 0, LB_ID, EA_W, GB_Other, SC_Han},
PROPENT_HANGUL_LV =  {0, 0, LB_H2, EA_W, GB_LV, SC_Hangul},
PROPENT_HANGUL_LVT = {0, 0, LB_H3, EA_W, GB_LVT, SC_Hangul},
PROPENT_PRIVATE =    {0, 0, LB_AL, EA_A, GB_Other, SC_Unknown}, /* XX */
PROPENT_UNKNOWN =    {0, 0, LB_AL, EA_N, GB_Other, SC_Unknown}; /* XX/SG */

static
void _charprop(linebreak_t *obj, unichar_t c,
	       propval_t *lbcptr, propval_t *eawptr, propval_t *gbcptr,
	       propval_t *scrptr)
{
    size_t key, idx, end;
    mapent_t *top, *bot, *cur, *ent;
    propval_t lbc = PROP_UNKNOWN, eaw = PROP_UNKNOWN, gbc = PROP_UNKNOWN,
	scr = PROP_UNKNOWN;

    /* First, search custom map. */
    if (obj->map && obj->mapsiz) {
	top = obj->map;
	bot = obj->map + obj->mapsiz - 1;
	while (top <= bot) {
	    cur = top + (bot - top) / 2;
	    if (c < cur->beg)
		bot = cur - 1;
	    else if (cur->end < c)
		top = cur + 1;
	    else {
		if (lbcptr) lbc = cur->lbc;
		if (eawptr) eaw = cur->eaw;
		if (gbcptr) gbc = cur->gbc;
		break;
	    }
	}
    }

    /* Otherwise, search built-in map. */
    if ((lbcptr && lbc == PROP_UNKNOWN) ||
	(eawptr && eaw == PROP_UNKNOWN) ||
	(gbcptr && gbc == PROP_UNKNOWN)) {
	ent = NULL;
	key = c % HASH_MODULUS;
	idx = linebreak_index[key];
	if (idx < linebreak_hashsiz) {
	    end = linebreak_index[key + 1];
	    for ( ; idx < end; idx++) {
		cur = linebreak_map + (size_t)(linebreak_hash[idx]);
		if (c < cur->beg)
		    break;
		else if (c <= cur->end) {
		    ent = cur;
		    break;
		}
	    }
	}
	if (ent == NULL) {
	    if ((0x3400 <= c && c <= 0x4DBF) ||
		(0x4E00 <= c && c <= 0x9FFF) ||
		(0xF900 <= c && c <= 0xFAFF) ||
		(0x20000 <= c && c <= 0x2FFFD) ||
		(0x30000 <= c && c <= 0x3FFFD)) {
		ent = &PROPENT_HAN;
	    } else if (0xAC00 <= c && c <= 0xD7A3) {
		if (c % 28 == 16)
		    ent = &PROPENT_HANGUL_LV;
		else
		    ent = &PROPENT_HANGUL_LVT;
	    } else if ((0xE000 <= c && c <= 0xF8FF) ||
		       (0xF0000 <= c && c <= 0xFFFFD) ||
		       (0x100000 <= c && c <= 0x10FFFD)) {
		ent = &PROPENT_PRIVATE;
	    }
	}
	if (ent == NULL)
	    ent = &PROPENT_UNKNOWN;

	if (lbcptr && lbc == PROP_UNKNOWN)
	    lbc = ent->lbc;
	if (eawptr && eaw == PROP_UNKNOWN)
	    eaw = ent->eaw;
	if (gbcptr && gbc == PROP_UNKNOWN)
	    gbc = ent->gbc;
	if (scrptr)
	    scr = ent->scr;
    }

    /* Resolve context-dependent property values. */
    if (lbcptr && lbc == LB_AI)
	lbc = (obj->options & LINEBREAK_OPTION_EASTASIAN_CONTEXT)?
	    LB_ID: LB_AL;
    if (eawptr && eaw == EA_A)
	eaw = (obj->options & LINEBREAK_OPTION_EASTASIAN_CONTEXT)?
	    EA_F: EA_N;

    if (lbcptr) *lbcptr = lbc;
    if (eawptr) *eawptr = eaw;
    if (gbcptr) *gbcptr = gbc;
    if (scrptr) *scrptr = scr;
}

static
propval_t _gbrule(propval_t b_idx, propval_t a_idx)
{
    propval_t result = PROP_UNKNOWN;

    if (b_idx < 0 || gcstring_rulessiz <= b_idx ||
	a_idx < 0 || gcstring_rulessiz <= a_idx)
	;
    else
	result = gcstring_rules[b_idx][a_idx];
    if (result == PROP_UNKNOWN)
	return DIRECT;
    return result;
}

#define eaw2col(e) (((e) == EA_F || (e) == EA_W)? 2: (((e) == EA_Z)? 0: 1))

static
void _gcinfo(linebreak_t *obj, unistr_t *str, size_t pos,
	     size_t *glenptr, size_t *gcolptr, propval_t *glbcptr)
{
    propval_t glbc = PROP_UNKNOWN, ggbc, gscr;
    size_t glen, gcol;
    propval_t lbc, eaw, gbc, ngbc, scr;

    if (!str || !str->str || !str->len) {
	if (glbcptr) *glbcptr = PROP_UNKNOWN;
	if (glenptr) *glenptr = 0;
	if (gcolptr) *gcolptr = 0;
	return;
    }

    _charprop(obj, str->str[pos], &lbc, &eaw, &gbc, &scr);
    pos++;
    glen = 1;
    gcol = eaw2col(eaw);

    glbc = lbc;
    ggbc = gbc;
    gscr = scr;

    if (lbc == LB_BK || lbc == LB_NL || gbc == GB_LF) {
	;
    } else if (gbc == GB_CR) {
	if (pos < str->len) {
	    _charprop(obj, str->str[pos], NULL, NULL, &gbc, NULL);
	    if (gbc == GB_LF) {
		pos++;
		glen++;
	    }
	}
    } else if (lbc == LB_SP || lbc == LB_ZW || lbc == LB_WJ) {
	while (1) {
	    if (str->len <= pos)
		break;
	    _charprop(obj, str->str[pos], &lbc, &eaw, NULL, NULL);
 	    if (lbc != glbc)
		break;
	    pos++;
	    glen++;
	    gcol += eaw2col(eaw);
        }
    }
    else {
	size_t pcol = 0, ecol = 0;
	while (1) {
	    if (str->len <= pos)
		break;
	    _charprop(obj, str->str[pos], &lbc, &eaw, &ngbc, &scr);
	    if (_gbrule(gbc, ngbc) != DIRECT) {
		pos++;
		glen++;

		if (gbc == GB_Prepend) {
		    glbc = lbc;
		    ggbc = ngbc;
		    gscr = scr;

		    pcol += gcol;
		    gcol = eaw2col(eaw);
		}
		/*
		 * Assume hangul syllable block is always wide, while most of
		 * isolated junseong (V) and jongseong (T) are narrow.
		 */
		else if ((ngbc == GB_L || ngbc == GB_V || ngbc == GB_T ||
			   ngbc == GB_LV || ngbc == GB_LVT) &&
			   (gbc == GB_L || gbc == GB_V || gbc == GB_T ||
			    gbc == GB_LV || gbc == GB_LVT))
		    gcol = 2;
		/*
		 * Some morbid sequences such as <L Extend V T> are allowed.
		 */
		else if (ngbc == GB_Extend || ngbc == GB_SpacingMark) {
		    ecol += eaw2col(eaw);
		    continue;
		}
		else
		    gcol += eaw2col(eaw);

		gbc = ngbc;
	    } else
		break;
	}
	gcol += pcol + ecol;
    }

    if (glbc == LB_SA) {
#ifdef USE_LIBTHAI
	if (gscr != SC_Thai)
#endif
	    glbc = (ggbc == GB_Extend || ggbc == GB_SpacingMark)? LB_CM: LB_AL;
    }
    if (glenptr) *glenptr = glen;
    if (gcolptr) *gcolptr = gcol;
    if (glbcptr) *glbcptr = glbc;
}

/*
 * Exports
 */

/*
 *
 */
linebreak_t *linebreak_new();
linebreak_t *linebreak_copy(linebreak_t *);
gcstring_t *gcstring_new(unistr_t *unistr, linebreak_t *lbobj)
{
    gcstring_t *gcstr;
    size_t pos, len;
    size_t glen, gcol;
    propval_t glbc;
    gcchar_t gc = {0, 0, 0, PROP_UNKNOWN, 0};

    if ((gcstr = malloc(sizeof(gcstring_t))) == NULL)
	return NULL;
    memset(gcstr, 0, sizeof(gcstring_t));

    if (unistr == NULL || unistr->str == NULL || unistr->len == 0)
	return gcstr;
    gcstr->str = unistr->str;
    gcstr->len = len = unistr->len;
    if (lbobj == NULL)
	gcstr->lbobj = linebreak_new();
    else
	gcstr->lbobj = linebreak_copy(lbobj);

    for (pos = 0; pos < len; pos += glen) {
	if ((gcstr->gcstr =
	     realloc(gcstr->gcstr, sizeof(gcchar_t) * (pos + 1))) == NULL)
	    return NULL;
	_gcinfo(gcstr->lbobj, unistr, pos, &glen, &gcol, &glbc);
	gc.idx = pos;
	gc.len = glen;
	gc.col = gcol;
	gc.lbc = glbc;
	memcpy(gcstr->gcstr + gcstr->gclen, &gc, sizeof(gcchar_t));
	gcstr->gclen++;
    }

    return gcstr;
}

gcstring_t *gcstring_copy(gcstring_t *obj)
{
    gcstring_t *newobj;
    unichar_t *newstr;
    gcchar_t *newgcstr;

    if ((newobj = malloc(sizeof(gcstring_t))) == NULL)
	return NULL;
    memcpy(newobj, obj, sizeof(gcstring_t));

    if (obj->str && obj->len) {
	if ((newstr = malloc(sizeof(unichar_t) * obj->len)) == NULL) {
	    free(newobj);
	    return NULL;
	}
	memcpy(newstr, obj->str, sizeof(unichar_t) * obj->len);
	newobj->str = newstr;
    }
    if (obj->gcstr && obj->gclen) {
	if ((newgcstr = malloc(sizeof(gcchar_t) * obj->gclen)) == NULL) {
	    if (newobj->str) free(newobj->str);
	    free(newobj);
	    return NULL;
	}
	memcpy(newgcstr, obj->gcstr, sizeof(gcchar_t) * obj->gclen);
	newobj->gcstr = newgcstr;
    }
    if (obj->lbobj != NULL)
	newobj->lbobj = linebreak_copy(obj->lbobj);
    else
	newobj->lbobj = linebreak_new();

    return newobj;
}

void linebreak_destroy(linebreak_t *);
void gcstring_destroy(gcstring_t *gcstr)
{
    if (gcstr == NULL)
	return;
    if (gcstr->str) free(gcstr->str);
    if (gcstr->gcstr) free(gcstr->gcstr);
    if (gcstr->lbobj) linebreak_destroy(gcstr->lbobj);
    free(gcstr);
}

gcstring_t *gcstring_append(gcstring_t *gcstr, gcstring_t *appe)
{
    unistr_t ustr = {0, 0};

    if (gcstr == NULL)
	return NULL;
    if (appe == NULL || appe->str == NULL || appe->len == 0)
	return gcstr;
    if (gcstr->gclen && appe->gclen) {
	size_t aidx, alen, blen, newlen, newgclen, i;
	unsigned char bflag;
	gcstring_t *cstr;

	aidx = gcstr->gcstr[gcstr->gclen - 1].idx;
	alen = gcstr->gcstr[gcstr->gclen - 1].len;
	blen = appe->gcstr[0].len;
	bflag = appe->gcstr[0].flag;

	if ((ustr.str = malloc(sizeof(unichar_t) * (alen + blen))) == NULL)
	    return NULL;
	memcpy(ustr.str, gcstr->str + aidx, sizeof(unichar_t) * alen);
	memcpy(ustr.str + alen, appe->str, sizeof(unichar_t) * blen);
	ustr.len = alen + blen;
	cstr = gcstring_new(&ustr, gcstr->lbobj);

	newlen = gcstr->len + appe->len;
	newgclen = gcstr->gclen - 1 + cstr->gclen + appe->gclen - 1;
	if ((gcstr->str = realloc(gcstr->str,
				  sizeof(unichar_t) * newlen)) == NULL ||
	    (gcstr->gcstr = realloc(gcstr->gcstr,
				    sizeof(gcchar_t) * newgclen)) == NULL) {
	    gcstring_destroy(cstr);
	    return NULL;
	}
	memcpy(gcstr->str + gcstr->len, appe->str,
	       sizeof(unichar_t) * appe->len);
	for (i = 0; i < cstr->gclen; i++) {
	    gcchar_t *gc = gcstr->gcstr + gcstr->gclen - 1 + i;

	    gc->idx = cstr->gcstr[i].idx + aidx;
	    gc->len = cstr->gcstr[i].len;
	    gc->col = cstr->gcstr[i].col;
	    gc->lbc = cstr->gcstr[i].lbc;
	    if (aidx + alen == gc->idx) /* Restore flag if possible */
		gc->flag = bflag;
	}
	for (i = 1; i < appe->gclen; i++) {
	    gcchar_t *gc =
		gcstr->gcstr + gcstr->gclen - 1 + cstr->gclen + i - 1;
	    gc->idx = appe->gcstr[i].idx - blen + aidx + cstr->len;
	    gc->len = appe->gcstr[i].len;
	    gc->col = appe->gcstr[i].col;
	    gc->lbc = appe->gcstr[i].lbc;
	    gc->flag = appe->gcstr[i].flag;
	}

	gcstr->len = newlen;
	gcstr->gclen = newgclen;
	gcstring_destroy(cstr);
    } else if (appe->gclen) {
	if ((gcstr->str = malloc(sizeof(unichar_t) * appe->len)) == NULL)
	    return NULL;
	if ((gcstr->gcstr = malloc(sizeof(gcchar_t) * appe->gclen)) == NULL) {
	    free(gcstr->str);
	    return NULL;
	}
	memcpy(gcstr->str, appe->str, sizeof(unichar_t) * appe->len);
	gcstr->len = appe->len;
	memcpy(gcstr->gcstr, appe->gcstr, sizeof(gcchar_t) * appe->gclen);
	gcstr->gclen = appe->gclen;
    }

    return gcstr;
}

size_t gcstring_columns(gcstring_t *gcstr)
{
    size_t col, i;

    if (gcstr == NULL)
	return 0;
    for (col = 0, i = 0; i < gcstr->gclen; i++)
	col += gcstr->gcstr[i].col;
    return col;
}

gcstring_t *gcstring_concat(gcstring_t *gcstr, gcstring_t *appe)
{
    gcstring_t *new;

    if (gcstr == NULL)
	return NULL;
    if ((new = gcstring_copy(gcstr)) == NULL)
	return NULL;
    return gcstring_append(new, appe);
}

/*
 *
 */
linebreak_t *linebreak_new()
{
    linebreak_t *obj;
    if ((obj = malloc(sizeof(linebreak_t)))== NULL)
	return NULL;
    memset(obj, 0, sizeof(linebreak_t));
    return obj;
}

linebreak_t *linebreak_copy(linebreak_t *obj)
{
    linebreak_t *newobj;
    mapent_t *newmap;

    if ((newobj = malloc(sizeof(linebreak_t)))== NULL)
	return NULL;
    memcpy(newobj, obj, sizeof(linebreak_t));

    if (obj->map && obj->mapsiz) {
	if ((newmap = malloc(sizeof(mapent_t) * obj->mapsiz))== NULL) {
	    free(newobj);
	    return NULL;
	}
	memcpy(newmap, obj->map, sizeof(mapent_t) * obj->mapsiz);
	newobj->map = newmap;
    }
    else
	newobj->map = NULL;
    return newobj;
}

void linebreak_destroy(linebreak_t *obj)
{
    if (obj == NULL)
	return;
    if (obj->map) free(obj->map);
    free(obj);
}

/*
 *
 */
propval_t linebreak_lbrule(propval_t b_idx, propval_t a_idx)
{
    propval_t result = PROP_UNKNOWN;

    if (b_idx < 0 || linebreak_rulessiz <= b_idx ||
	a_idx < 0 || linebreak_rulessiz <= a_idx)
	;
    else
	result = linebreak_rules[b_idx][a_idx];
    if (result == PROP_UNKNOWN)
	return DIRECT;
    return result;
}

propval_t linebreak_lbclass(linebreak_t *obj, unichar_t c)
{
    propval_t lbc, gbc, scr;

    _charprop(obj, c, &lbc, NULL, &gbc, &scr);
    if (lbc == LB_SA) {
#ifdef USE_LIBTHAI
	if (scr != SC_Thai)
#endif
	    lbc = (gbc == GB_Extend || gbc == GB_SpacingMark)? LB_CM: LB_AL;
    }
    return lbc;
}

propval_t linebreak_eawidth(linebreak_t *obj, unichar_t c)
{
    propval_t eaw;
    
    _charprop(obj, c, NULL, &eaw, NULL, NULL);
    return eaw;
}

size_t linebreak_strsize(linebreak_t *obj,
    size_t len, unistr_t *pre, unistr_t *spc, unistr_t *str, size_t max)
{
    unistr_t spcstr = { 0, 0 };
    size_t idx, pos;

    if (max < 0)
	max = 0;
    if ((!spc || !spc->str || !spc->len) && (!str || !str->str || !str->len))
	return max? 0: len;

    if (_unistr_concat(&spcstr, spc, str) == NULL)
	return -1;
    idx = 0;
    pos = 0;
    while (1) {
	size_t glen, gcol;
	propval_t gcls;

	if (spcstr.len <= pos)
	    break;
	_gcinfo(obj, &spcstr, pos, &glen, &gcol, &gcls);
	pos += glen;

	if (max && max < len + gcol) {
	    idx -= spc->len;
	    if (idx < 0)
		idx = 0;
	    break;
	}
	idx += glen ;
	len += gcol;
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
	linebreak_t *obj;
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
_new(self, str, ...)
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
	_utf8touni(&unistr, str);
	if (2 < items)
	    lb = _selftoobj(ST(2));
	else
	    lb = NULL;
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
    PROTOTYPE: $
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
	    i = 0;
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
	    i = 0;
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

