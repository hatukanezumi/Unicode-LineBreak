#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

typedef unsigned int unichar_t;
typedef size_t propval_t;
typedef struct {
    unichar_t beg;
    unichar_t end;
    propval_t prop;
} mapent_t;

static propval_t LB_XX;
static int DIRECT;

static mapent_t *propmaps[2] = { NULL, NULL };
static size_t propmapsizes[2] = { 0, 0 };
static int **ruletable = NULL;
static size_t ruletablesiz = 0;

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

int getlbrule(propval_t b_idx, propval_t a_idx,
    unsigned int *res, size_t reslen)
{
    int result = 0;
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

MODULE = Unicode::LineBreak	PACKAGE = Unicode::LineBreak	

void
_loadconst(lb_xx, direct)
	propval_t lb_xx;
	int direct;
    CODE:
	LB_XX = lb_xx;
	DIRECT = direct;

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
	    croak("Can't allocate memory");
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
	int prop;
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
	} else if ((ruletable = malloc(sizeof(int **) * ruletablesiz))
		   == NULL) {
	    ruletablesiz = 0;
	    ruletable = NULL;
	    croak("Can't allocate memory");
	} else {
	    for (n = 0; n < ruletablesiz; n++) {
		if ((ruletable[n] = malloc(sizeof(int) * ruletablesiz))
		    == NULL) {
		    ruletablesiz = 0;
		    ruletable = NULL;
		    croak("Can't allocate memory");
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
	    croak("Memory exausted");
	for (i = 0; i < items; i++)
	    packed[i] = (unsigned int)SvIV(ST(i));
	packed[i++] = (unsigned int)(-1);
	packed[i++] = (unsigned int)(-1);
	RETVAL = newSVpvn((char *)(void *)packed, sizeof(unsigned int) * i);
	free(packed);
    OUTPUT:
	RETVAL

propval_t
_bsearch(idx, c, def, sv)
	size_t idx;
	unichar_t c;
	propval_t def;
	SV *sv;
    INIT:
	unsigned int *res;
	size_t l;
	propval_t prop;

	l = (size_t)SvCUR(sv);
	res = (unsigned int *)SvPV(sv, l);
	prop = _bsearch(propmaps[idx], propmapsizes[idx], c,
			def, res, l / sizeof(unsigned int) / 2);
	if (prop == -1)
	    XSRETURN_UNDEF;
    CODE:
	RETVAL = prop;
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
	hash = (HV *)SvRV(obj);
	sv = *hv_fetch(hash, "_lb_hash", 8, 0);
	res = (unsigned int *)SvPV(sv, l);
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
	int prop;

	if (!SvOK(ST(1)) || !SvOK(ST(2)))
	    XSRETURN_UNDEF;
    CODE:
	hash = (HV *)SvRV(obj);
	sv = *hv_fetch(hash, "_rule_hash", 10, 0);
	l = SvCUR(sv);
	res = (unsigned int *)SvPV(sv, l);
	prop = getlbrule(b_idx, a_idx, res, l / sizeof(unsigned int) / 2);
	if (!prop)
	    XSRETURN_UNDEF;
	RETVAL = prop;
    OUTPUT:
	RETVAL

