#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

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

static propval_t LB_H2, LB_H3, LB_JL, LB_JV, LB_JT, LB_XX;
static propval_t EA_z, EA_A, EA_W, EA_F;
static propval_t DIRECT;

static mapent_t *propmaps[2] = { NULL, NULL };
static size_t propmapsizes[2] = { 0, 0 };
static propval_t **ruletable = NULL;
static size_t ruletablesiz = 0;

unistr_t *_unistr_concat(unistr_t *buf, unistr_t *a, unistr_t *b)
{
    if (!buf) {
	buf = malloc(sizeof(unistr_t));
	buf->str = NULL;
	buf->len = 0;
    } else if (buf->str)
	free(buf->str);

    if ((!a || !a->str || !a->len) && (!b || !b->str || !b->len)) {
	buf->str = NULL;
	buf->len = 0;
    } else if (!b || !b->str || !b->len) {
	buf->str = malloc(sizeof(unichar_t) * a->len);
	memcpy(buf->str, a->str, sizeof(unichar_t) * a->len);
	buf->len = a->len;
    } else if (!a || !a->str || !a->len) {
	buf->str = malloc(sizeof(unichar_t) * b->len);
	memcpy(buf->str, b->str, sizeof(unichar_t) * b->len);
	buf->len = b->len;
    } else {
	buf->str = malloc(sizeof(unichar_t) * (a->len + b->len));
	memcpy(buf->str, a->str, sizeof(unichar_t) * a->len);
	memcpy(buf->str + a->len, b->str, sizeof(unichar_t) * b->len);
	buf->len = a->len + b->len;
    }
    return buf;
}

/*
 * _bsearch( map, size, c, default, res, ressize)
 * Examine binary search on property map table with following structure:
 * [
 *     [start, stop, property_value],
 *     ...
 * ]
 * where start and stop stands for a continuous range of UCS ordinal those
 * are assigned property_value.
 */
propval_t _bsearch(mapent_t* map, size_t n, unichar_t c, propval_t def,
    unsigned int *res, size_t reslen)
{
    mapent_t *top = map;
    mapent_t *bot = map + n - 1;
    mapent_t *cur;
    propval_t result = -1;
    unsigned int *p = res;
    size_t i = 0;
	
    if (!map || !n)
	return -1;
    if (!res || !reslen)
	return -1;
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
    if (result == -1)
	result = def;
    while (i < reslen && *p != -1) {
	if (result == *p) {
	    result = p[1];
	    break;
	}
	p += 2;
	i++;
    }
    return result;
}

propval_t getlbclass(unichar_t c, unsigned int *res, size_t reslen)
{
    return _bsearch(propmaps[0], propmapsizes[0], c, LB_XX, res, reslen);
}

propval_t getlbrule(propval_t b_idx, propval_t a_idx,
    unsigned int *res, size_t reslen)
{
    propval_t result = 0;
    unsigned int *p = res;
    size_t i = 0;

    if (!ruletable || !ruletablesiz)
	return 0;
    if (!res || !reslen)
	return 0;
    if (b_idx < 0 || ruletablesiz <= b_idx ||
	a_idx < 0 || ruletablesiz <= a_idx)
	;
    else
	result = ruletable[b_idx][a_idx];
    if (result == 0)
	result = DIRECT;
    while (i < reslen && *p != -1) {
	if (result == *p) {
	    result = p[1];
	    break;
	}
	p += 2;
	i++;
    }
    return result;
}

size_t getstrsize(size_t len, unistr_t *pre, unistr_t *spc, unistr_t *str,
    unsigned int *lb_res, size_t lb_reslen,
    unsigned int *ea_res, size_t ea_reslen,
    unsigned int *rule_res, size_t rule_reslen,
    size_t max)
{
    unistr_t spcstr = { 0, 0 };
    size_t length, idx, pos;

    if (max < 0)
	max = 0;
    if ((!spc || !spc->str || !spc->len) && (!str || !str->str || !str->len))
	return max? 0: len;

    _unistr_concat(&spcstr, spc, str);
    length = spcstr.len;
    idx = 0;
    pos = 0;
    while (1) {
	size_t clen, width;
	unichar_t c, nc;
	propval_t cls, ncls;

	if (length <= pos)
	    break;
	c = spcstr.str[pos];
	cls = getlbclass(c, lb_res, lb_reslen);
	clen = 1;

	/* Hangul syllable block */
	if (cls == LB_H2 || cls == LB_H3 ||
	    cls == LB_JL || cls == LB_JV || cls == LB_JT) {
	    while (1) {
		pos++;
		if (length <= pos)
		    break;
		nc = spcstr.str[pos];
		ncls = getlbclass(nc, lb_res, lb_reslen);
		if ((ncls == LB_H2 || ncls == LB_H3 ||
		    ncls == LB_JL || ncls == LB_JV || ncls == LB_JT) &&
		    getlbrule(cls, ncls, rule_res, rule_reslen) != DIRECT) {
		    cls = ncls;
		    clen++;
		    continue;
		}
		break;
	    } 
	    width = EA_W;
	} else {
	    pos++;
	    width = _bsearch(propmaps[1], propmapsizes[1], c, EA_A,
			     ea_res, ea_reslen);
	}
	/*
	 * After all, possible widths are non-spacing (z), wide (F/W) or
	 * narrow (H/N/Na).
	 */

	if (width == EA_z) {
	    width = 0;
	} else if (width == EA_F || width == EA_W) {
	    width = 2;
	} else {
	    width = 1;
	}
	if (max && max < len + width) {
	    idx -= spc->len;
	    if (idx < 0)
		idx = 0;
	    break;
	}
	idx += clen;
	len += width;
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
    propval_t def;
} constent_t;
constent_t _constent[] = {
    {"EA_z", &EA_z, -1}, 
    {"EA_A", &EA_A, -1}, 
    {"EA_W", &EA_W, -1}, 
    {"EA_F", &EA_F, -1}, 
    {"LB_H2", &LB_H2, -1},
    {"LB_H3", &LB_H3, -1},
    {"LB_JL", &LB_JL, -1},
    {"LB_JV", &LB_JV, -1},
    {"LB_JT", &LB_JT, -1},
    {"LB_XX", &LB_XX, -1},
    {"DIRECT", &DIRECT, 0},
    {NULL, NULL, 0},
};

#define _hash_res(name) \
{ \
    hash = (HV *)SvRV(obj); \
    sv = *hv_fetch(hash, name, strlen(name), 0); \
    l = SvCUR(sv); \
    res = (unsigned int *)SvPV(sv, l); \
}

unistr_t *_utf8touni(unistr_t *buf, SV *str)
{
    U8 *utf8, *utf8ptr;
    STRLEN utf8len, unilen, len;
    unichar_t *uniptr;

    if (buf->str)
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
	*(uniptr++) = (unichar_t)utf8_to_uvuni(utf8ptr, &len);
	if (len < 0)
	    croak("_utf8touni: Not well-formed UTF-8");
	if (len == 0)
	    croak("_utf8touni: Internal error");
	utf8ptr += len;
    }
    buf->len = unilen;
    return buf;
}

MODULE = Unicode::LineBreak	PACKAGE = Unicode::LineBreak	

void
_loadconst(...)
    PREINIT:
	size_t i;
	constent_t *p;
	char *name;
	int r;
    CODE:
	p = _constent;
	while (p->name) {
	    *(p->ptr) = p->def;
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
_loadmap(idx, mapref)
	size_t	idx;
	SV *	mapref;
    INIT:
	size_t n, propmapsiz;
	unichar_t beg, end;
	AV * map;
	AV * ent;
	propval_t prop;
	mapent_t * propmap;
    CODE:
	propmap = propmaps[idx];
	if (propmap)
	    free(propmap);
	map = (AV *)SvRV(mapref);
	propmapsiz = av_len(map) + 1;
	if (propmapsiz <= 0) {
	    propmapsiz = 0;
	    propmap = NULL;
	} else if ((propmap = malloc(sizeof(mapent_t) * propmapsiz)) == NULL) {
	    propmapsiz = 0;
	    propmap = NULL;
	    croak("_loadmap: Can't allocate memory");
	} else {
	    for (n = 0; n < propmapsiz; n++) {
		ent = (AV *)SvRV(*av_fetch(map, n, 0));
		beg = SvUV(*av_fetch(ent, 0, 0));
		end = SvUV(*av_fetch(ent, 1, 0));
		prop = SvIV(*av_fetch(ent, 2, 0));
		propmap[n].beg = beg;
		propmap[n].end = end;
		propmap[n].prop = prop;
	    }
	}
	propmapsizes[idx] = propmapsiz;
	propmaps[idx] = propmap;

void
_loadrule(tableref)
	SV *	tableref;
    INIT:
	size_t n, m;
	AV * rule;
	AV * ent;
	propval_t prop;
    CODE:
	if (ruletable && ruletablesiz) {
	    for (n = 0; n < ruletablesiz; n++)
		free(ruletable[n]);
	    free(ruletable);
	}
	rule = (AV *)SvRV(tableref);
	ruletablesiz = av_len(rule) + 1;
	if (ruletablesiz <= 0) {
	    ruletablesiz = 0;
	    ruletable = NULL;
	} else if ((ruletable = malloc(sizeof(propval_t **) * ruletablesiz))
		   == NULL) {
	    ruletablesiz = 0;
	    ruletable = NULL;
	    croak("_loadrule: Can't allocate memory");
	} else {
	    for (n = 0; n < ruletablesiz; n++) {
		if ((ruletable[n] = malloc(sizeof(propval_t) * ruletablesiz))
		    == NULL) {
		    ruletablesiz = 0;
		    ruletable = NULL;
		    croak("_loadrule: Can't allocate memory");
		} else {
		    ent = (AV *)SvRV(*av_fetch(rule, n, 0));
		    for (m = 0; m < ruletablesiz; m++) {
			prop = SvIV(*av_fetch(ent, m, 1));
			ruletable[n][m] = prop;
		    }
		}		    
	    }
	}

SV *
_packed_hash(...)
    PREINIT:
	unsigned int *packed = NULL;
	size_t i;
    CODE:
	if ((packed = malloc(sizeof(unsigned int) * (items + 2))) == NULL)
	    croak("_packed_hash: Memory exausted");
	for (i = 0; i < items; i++)
	    packed[i] = (unsigned int)SvIV(ST(i));
	packed[i++] = (unsigned int)(-1);
	packed[i++] = (unsigned int)(-1);
	RETVAL = newSVpvn((char *)(void *)packed, sizeof(unsigned int) * i);
	free(packed);
    OUTPUT:
	RETVAL

propval_t
getlbclass(obj, str)
	SV *obj;
	unsigned char *str;
    INIT:
	unichar_t c;
	HV *hash;
	SV *sv;
	unsigned int *res;
	size_t l;
	propval_t prop;

	/* FIXME: return undef unless defined $str and length $str; */
	if (!str)
	    XSRETURN_UNDEF;
	c = utf8_to_uvuni(str, NULL);
	_hash_res("_lb_hash");
	prop = getlbclass(c, res, l / sizeof(unsigned int) / 2);
	if (prop == -1)
	    XSRETURN_UNDEF;
    CODE:
	RETVAL = prop;	
    OUTPUT:
	RETVAL

int
getlbrule(obj, b_idx, a_idx)
	SV * obj;	
	propval_t b_idx;
	propval_t a_idx;
    INIT:
	HV *hash;
	SV *sv;
	unsigned int *res;
	size_t l;
	propval_t prop;

	if (!SvOK(ST(1)) || !SvOK(ST(2)))
	    XSRETURN_UNDEF;
    CODE:
	_hash_res("_rule_hash");
	prop = getlbrule(b_idx, a_idx, res, l / sizeof(unsigned int) / 2);
	if (!prop)
	    XSRETURN_UNDEF;
	RETVAL = prop;
    OUTPUT:
	RETVAL

size_t
getstrsize(obj, len, pre, spc, str, ...)
	SV *obj;
	size_t len;
	SV *pre;
	SV* spc;
	SV* str;
    INIT:
	size_t max;
	HV *hash;
	SV *sv;
	unsigned int *res, *lb_res, *ea_res, *rule_res;
	size_t l, lb_reslen, ea_reslen, rule_reslen;
	unistr_t unipre = { 0, 0 }, unispc = { 0, 0 }, unistr = { 0, 0 };
    CODE:
	_utf8touni(&unipre, pre);	
	_utf8touni(&unispc, spc);	
	_utf8touni(&unistr, str);	
	_hash_res("_lb_hash");
	lb_res = res;
	lb_reslen = l / sizeof(unsigned int) / 2;
	_hash_res("_ea_hash");
	ea_res = res;
	ea_reslen = l / sizeof(unsigned int) / 2;
	_hash_res("_rule_hash");
	rule_res = res;
	rule_reslen = l / sizeof(unsigned int) / 2;
	if (5 < items)
	    max = SvUV(ST(5));
	else
	    max = 0;

	RETVAL = getstrsize(len, &unipre, &unispc, &unistr,
			    lb_res, lb_reslen, ea_res, ea_reslen,
			    rule_res, rule_reslen, max);
	if (unipre.str) free(unipre.str);
	if (unispc.str) free(unispc.str);
	if (unistr.str) free(unistr.str);
    OUTPUT:
	RETVAL
