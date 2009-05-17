#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

typedef struct {
    unsigned int beg;
    unsigned int end;
    char *prop;
} mapent_t;

static mapent_t *MAPs[2] = { NULL, NULL };
static size_t MAPsizes[2] = { 0, 0};
static int **RULE = NULL;
static size_t RULEsiz = 0;

char *_bsearch(mapent_t* map, size_t n, unsigned int c)
{
    mapent_t *top = map;
    mapent_t *bot = map + n - 1;
    mapent_t *cur;
	
    if (!map || !n)
	return NULL;
    while (top <= bot) {
	cur = top + (bot - top) / 2;
	if (c < cur->beg)
	    bot = cur - 1;
	else if (cur->end < c)
	    top = cur + 1;
	else
	    return cur->prop;
    }
    return NULL;
}

int _getlbrule(size_t b_idx, size_t a_idx) {
    if (!RULE || !RULEsiz)
	return 0;
    if (b_idx < 0 || RULEsiz <= b_idx || a_idx < 0 || RULEsiz <= a_idx)
	return 0;
    return RULE[b_idx][a_idx];
}

MODULE = Unicode::LineBreak	PACKAGE = Unicode::LineBreak	

void
_loadmap(idx, mapref)
	size_t	idx;
	SV *	mapref;
    INIT:
	size_t n, beg, end, MAPsiz;
	AV * map;
	AV * ent;
	char * prop;
	mapent_t * MAP;
    CODE:
	MAP = MAPs[idx];
	if (MAP)
	    free(MAP);
	map = (AV *)SvRV(mapref);
	MAPsiz = av_len(map) + 1;
	if (MAPsiz <= 0) {
	    MAPsiz = 0;
	    MAP = NULL;
	} else if ((MAP = malloc(sizeof(mapent_t) * MAPsiz)) == NULL) {
	    MAPsiz = 0;
	    MAP = NULL;
	    croak("Can't allocate memory");
	} else {
	    for (n = 0; n < MAPsiz; n++) {
		ent = (AV *)SvRV(*av_fetch(map, n, 0));
		beg = SvUV(*av_fetch(ent, 0, 0));
		end = SvUV(*av_fetch(ent, 1, 0));
		prop = (char *)SvRV(*av_fetch(ent, 2, 0));
		MAP[n].beg = beg;
		MAP[n].end = end;
		MAP[n].prop = prop;
	    }
	}
	MAPsizes[idx] = MAPsiz;
	MAPs[idx] = MAP;

void
_loadrule(tableref)
	SV *	tableref;
    INIT:
	size_t n, m;
	AV * rule;
	AV * ent;
	int prop;
    CODE:
	if (RULE && RULEsiz) {
	    for (n = 0; n < RULEsiz; n++)
		free(RULE[n]);
	    free(RULE);
	}
	rule = (AV *)SvRV(tableref);
	RULEsiz = av_len(rule) + 1;
	if (RULEsiz <= 0) {
	    RULEsiz = 0;
	    RULE = NULL;
	} else if ((RULE = malloc(sizeof(int **) * RULEsiz)) == NULL) {
	    RULEsiz = 0;
	    RULE = NULL;
	    croak("Can't allocate memory");
	} else {
	    for (n = 0; n < RULEsiz; n++) {
		if ((RULE[n] = malloc(sizeof(int) * RULEsiz)) == NULL) {
		    RULEsiz = 0;
		    RULE = NULL;
		    croak("Can't allocate memory");
		} else {
		    ent = (AV *)SvRV(*av_fetch(rule, n, 0));
		    for (m = 0; m < RULEsiz; m++) {
			prop = SvIV(*av_fetch(ent, m, 1));
			RULE[n][m] = prop;
		    }
		}		    
	    }
	}

char *
_bsearch(idx, val)
	size_t idx;
	unsigned int val;
    INIT:
	char *prop;
	prop = _bsearch(MAPs[idx], MAPsizes[idx], val);
	if (prop == NULL)
	    XSRETURN_UNDEF;
    CODE:
	RETVAL = prop;
    OUTPUT:
	RETVAL

int
_getlbrule(b_idx, a_idx)
	size_t b_idx;
	size_t a_idx;
    INIT:
	int prop;
	prop = _getlbrule(b_idx, a_idx);
	if (!prop)
	    XSRETURN_UNDEF;
    CODE:
	RETVAL = prop;
    OUTPUT:
	RETVAL

