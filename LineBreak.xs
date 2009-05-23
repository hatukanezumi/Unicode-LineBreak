#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

typedef struct {
    unsigned int beg;
    unsigned int end;
    size_t prop;
} mapent_t;

static size_t LB_XX;
static int DIRECT;

static mapent_t *propmaps[2] = { NULL, NULL };
static size_t propmapsizes[2] = { 0, 0 };
static int **ruletable = NULL;
static size_t ruletablesiz = 0;

size_t _bsearch(mapent_t* map, size_t n, unsigned int c,
	size_t def, unsigned int *res)
{
    mapent_t *top = map;
    mapent_t *bot = map + n - 1;
    mapent_t *cur;
    size_t result = -1;
    unsigned int *p = res;
	
    if (!map || !n)
	return -1;
    if (!res)
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
    while (*p != -1) {
	if (result == *p) {
	    result = p[1];
	    break;
	}
	p += 2;
    }
    return result;
}

size_t getlbclass(unsigned int c, unsigned int *res) {
    return _bsearch(propmaps[0], propmapsizes[0], c, LB_XX, res);
}

int getlbrule(size_t b_idx, size_t a_idx, unsigned int *res) {
    int result = 0;
    unsigned int *p = res;

    if (!ruletable || !ruletablesiz)
	return 0;
    if (!res)
	return 0;
    if (b_idx < 0 || ruletablesiz <= b_idx ||
	a_idx < 0 || ruletablesiz <= a_idx)
	;
    else
	result = ruletable[b_idx][a_idx];
    if (result == 0)
	result = DIRECT;
    while (*p != -1) {
	if (result == *p) {
	    result = p[1];
	    break;
	}
	p += 2;
    }
    return result;
}

MODULE = Unicode::LineBreak	PACKAGE = Unicode::LineBreak	

void
_loadconst(lb_xx, direct)
	size_t lb_xx;
	int direct;
    CODE:
	LB_XX = lb_xx;
	DIRECT = direct;

void
_loadmap(idx, mapref)
	size_t	idx;
	SV *	mapref;
    INIT:
	size_t n, beg, end, propmapsiz;
	AV * map;
	AV * ent;
	size_t prop;
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

size_t
_bsearch(idx, val, def, res)
	size_t idx;
	unsigned int val;
	size_t def;
	char *res;
    INIT:
	size_t prop;
	prop = _bsearch(propmaps[idx], propmapsizes[idx], val,
			def, (unsigned int *)res);
	if (prop == -1)
	    XSRETURN_UNDEF;
    CODE:
	RETVAL = prop;
    OUTPUT:
	RETVAL

size_t
getlbclass(obj, str)
	SV *obj;
	unsigned char *str;
    INIT:
	unsigned int c;
	HV *hash;
	unsigned int *res;
	size_t prop;

	/* FIXME: return undef unless defined $str and length $str; */
	if (!str)
	    XSRETURN_UNDEF;
	c = utf8_to_uvuni(str, NULL);
	hash = (HV *)SvRV(obj);
	res = (unsigned int *)SvRV(*hv_fetch(hash, "_lb_hash", 8, 0));
	prop = getlbclass(c, res);
	if (prop == -1)
	    XSRETURN_UNDEF;
    CODE:
	RETVAL = prop;	
    OUTPUT:
	RETVAL

int
getlbrule(obj, b_idx, a_idx)
	SV * obj;	
	size_t b_idx;
	size_t a_idx;
    INIT:
	int prop;
	HV *hash;
	unsigned int *res;

	if (!SvOK(ST(1)) || !SvOK(ST(2)))
	    XSRETURN_UNDEF;
    CODE:
	hash = (HV *)SvRV(obj);
	res = (unsigned int *)SvRV(*hv_fetch(hash, "_rule_hash", 10, 0));
	prop = getlbrule(b_idx, a_idx, res);
	if (!prop)
	    XSRETURN_UNDEF;
	RETVAL = prop;
    OUTPUT:
	RETVAL

