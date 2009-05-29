#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#define PROP_UNKNOWN ((propval_t)(-1))

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
    unsigned int *lb_tbl;
    unsigned int *ea_tbl;
    unsigned int *rule_tbl;
} linebreakObj;

static propval_t LB_H2, LB_H3, LB_JL, LB_JV, LB_JT, LB_XX;
static propval_t EA_Z, EA_A, EA_W, EA_F;
static propval_t DIRECT;

static mapent_t *lbmap = NULL;
static size_t lbmapsiz = 0;
static mapent_t *eamap = NULL;
static size_t eamapsiz = 0;
static propval_t **rulemap = NULL;
static size_t rulemapsiz = 0;

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

propval_t _search_packed_table(unsigned int *tbl, propval_t val)
{
    size_t tbllen, i;
    unsigned int *p;

    if (!tbl)
	return PROP_UNKNOWN;
    if (!(tbllen = (size_t)tbl[0]))
	return PROP_UNKNOWN;

    for (i = 0, p = tbl + 1; i < tbllen && *p != -1; i++, p += 2)
	if (val == *p) {
	    val = p[1];
	    break;
	}
    return val;
}

/*
 * _bsearch (map, mapsize, c, default, tbl)
 * Examine binary search on property map table with following structure:
 * [
 *     [start, stop, property_value],
 *     ...
 * ]
 * where start and stop stands for a continuous range of UCS ordinal those
 * are assigned property_value.
 */
propval_t _bsearch(mapent_t* map, size_t mapsiz, unichar_t c, propval_t def,
    unsigned int *tbl)
{
    mapent_t *top, *bot, *cur;
    propval_t result;
	
    assert(map && mapsiz);
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
    if (result == PROP_UNKNOWN)
	result = def;
    return _search_packed_table(tbl, result);
}

propval_t eawidth(linebreakObj *obj, unichar_t c)
{
    return _bsearch(eamap, eamapsiz, c, EA_A, obj->ea_tbl);
}

propval_t lbclass(linebreakObj *obj, unichar_t c)
{
    return _bsearch(lbmap, lbmapsiz, c, LB_XX, obj->lb_tbl);
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
	result = DIRECT;
    return _search_packed_table(obj->rule_tbl, result);
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
	return PROP_UNKNOWN;
    length = spcstr.len;
    idx = 0;
    pos = 0;
    while (1) {
	size_t clen, w;
	unichar_t c, nc;
	propval_t cls, ncls, width;

	if (length <= pos)
	    break;
	c = spcstr.str[pos];
	cls = lbclass(obj, c);
	clen = 1;

	/* Hangul syllable block */
	if (cls == LB_H2 || cls == LB_H3 ||
	    cls == LB_JL || cls == LB_JV || cls == LB_JT) {
	    while (1) {
		pos++;
		if (length <= pos)
		    break;
		nc = spcstr.str[pos];
		ncls = lbclass(obj, nc);
		if ((ncls == LB_H2 || ncls == LB_H3 ||
		    ncls == LB_JL || ncls == LB_JV || ncls == LB_JT) &&
		    lbrule(obj, cls, ncls) != DIRECT) {
		    cls = ncls;
		    clen++;
		    continue;
		}
		break;
	    } 
	    width = EA_W;
	} else {
	    pos++;
	    width = eawidth(obj, c);
	}
	/*
	 * After all, possible widths are non-spacing (z), wide (F/W) or
	 * narrow (H/N/Na).
	 */

	if (width == EA_Z) {
	    w = 0;
	} else if (width == EA_F || width == EA_W) {
	    w = 2;
	} else {
	    w = 1;
	}
	if (max && max < len + w) {
	    idx -= spc->len;
	    if (idx < 0)
		idx = 0;
	    break;
	}
	idx += clen;
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
constent_t _constent[] = {
    { "EA_Z", &EA_Z }, 
    { "EA_A", &EA_A }, 
    { "EA_W", &EA_W }, 
    { "EA_F", &EA_F }, 
    { "LB_H2", &LB_H2 },
    { "LB_H3", &LB_H3 },
    { "LB_JL", &LB_JL },
    { "LB_JV", &LB_JV },
    { "LB_JT", &LB_JT },
    { "LB_XX", &LB_XX },
    { "DIRECT", &DIRECT },
    { NULL, NULL },
};

mapent_t *_loadmap(mapent_t *propmap, SV *mapref, size_t *mapsiz)
{
    size_t n;
    unichar_t beg, end;
    AV * map;
    AV * ent;
    propval_t prop;

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
	    beg = SvUV(*av_fetch(ent, 0, 0));
	    end = SvUV(*av_fetch(ent, 1, 0));
	    prop = SvIV(*av_fetch(ent, 2, 0));
	    propmap[n].beg = beg;
	    propmap[n].end = end;
	    propmap[n].prop = prop;
	}
    }
    return propmap;
}

unsigned int *_get_packed_table(SV *obj, char *name)
{
    SV *sv;
    STRLEN l;
    unsigned int *tbl;

    sv = *hv_fetch((HV *)SvRV(obj), name, strlen(name), 0);
    l = SvCUR(sv);
    if (l) {
	tbl = (unsigned int *)SvPV(sv, l);
	if (l < tbl[0] * sizeof(unsigned int) * 2 + sizeof(unsigned int))
	    croak("_get_packed_table: Actual len %d; reported %d", l, tbl[0]);
    } else {
	tbl = NULL;
    }
    return tbl;
}

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

linebreakObj *_selftoobj(linebreakObj *obj, SV *self)
{
    if (!obj && (obj = malloc(sizeof(linebreakObj))) == NULL)
	croak("_selftoobj: Cannot allocate memory");
    obj->lb_tbl = _get_packed_table(self, "_lb_hash");
    obj->ea_tbl = _get_packed_table(self, "_ea_hash");
    obj->rule_tbl = _get_packed_table(self, "_rule_hash");
    return obj;
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
	    *(p->ptr) = -1;
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

# _packed_table (ITEM...)
#     Equvalent to
#     pack('I*', (scalar(@_) + 2) / 2, @_, -1, -1);
SV *
_packed_table(...)
    PROTOTYPE: @
    PREINIT:
	unsigned int *packed = NULL;
	size_t i;
    CODE:
	if ((packed = malloc(sizeof(unsigned int) * (items + 3))) == NULL)
	    croak("_packed_table: Memory exausted");
	packed[0] = (unsigned int)((items + 2) / 2);
	for (i = 1; i < items + 1; i++)
	    packed[i] = (unsigned int)SvIV(ST(i-1));
	packed[i++] = -1;
	packed[i++] = -1;
	RETVAL = newSVpvn((char *)(void *)packed, sizeof(unsigned int) * i);
	free(packed);
    OUTPUT:
	RETVAL

propval_t
eawidth(self, str)
	SV *self;
	SV *str;
    PROTOTYPE: $$
    INIT:
	linebreakObj obj;
	unichar_t c;
	propval_t prop;
    CODE:
	/* FIXME: return undef unless (defined $str and length $str); */
	if (!SvCUR(str))
	    XSRETURN_UNDEF;
	_selftoobj(&obj, self);
	c = utf8_to_uvuni((U8 *)SvPV_nolen(str), NULL);
	prop = eawidth(&obj, c);
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
	linebreakObj obj;
	unichar_t c;
	propval_t prop;
    CODE:
	/* FIXME: return undef unless (defined $str and length $str); */
	if (!SvCUR(str))
	    XSRETURN_UNDEF;
	_selftoobj(&obj, self);
	c = utf8_to_uvuni((U8 *)SvPV_nolen(str), NULL);
	prop = lbclass(&obj, c);
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
	linebreakObj obj;
	propval_t prop;
    CODE:
	if (!SvOK(ST(1)) || !SvOK(ST(2)))
	    XSRETURN_UNDEF;
	_selftoobj(&obj, self);
	prop = lbrule(&obj, b_idx, a_idx);
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
	linebreakObj obj;
	unistr_t unipre = {0, 0}, unispc = {0, 0}, unistr = {0, 0};
	size_t max;
    CODE:
	_selftoobj(&obj, self);
	_utf8touni(&unipre, pre);
	_utf8touni(&unispc, spc);
	_utf8touni(&unistr, str);
	if (5 < items)
	    max = SvUV(ST(5));
	else
	    max = 0;

	RETVAL = strsize(&obj, len, &unipre, &unispc, &unistr, max);
	if (unipre.str) free(unipre.str);
	if (unispc.str) free(unispc.str);
	if (unistr.str) free(unistr.str);
	if (RETVAL == PROP_UNKNOWN)
	    croak("strsize: Can't allocate memory");
    OUTPUT:
	RETVAL
