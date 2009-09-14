#include "linebreak.h"

extern propval_t *linebreak_rules[];
extern size_t linebreak_rulessiz;
extern void linebreak_charprop(linebreak_t *, unichar_t,
                               propval_t *, propval_t *, propval_t *,
                               propval_t *);
extern size_t gcstring_columns(gcstring_t *);
extern gcstring_t *gcstring_concat(gcstring_t *, gcstring_t *);
extern void gcstring_destroy(gcstring_t *);

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

    linebreak_charprop(obj, c, &lbc, NULL, &gbc, &scr);
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
    
    linebreak_charprop(obj, c, NULL, &eaw, NULL, NULL);
    return eaw;
}

size_t linebreak_strsize(linebreak_t *obj, size_t len, gcstring_t *pre,
			 gcstring_t *spc, gcstring_t *str, size_t max)
{
    gcstring_t *spcstr;
    size_t idx, pos;

    if (max < 0)
	max = 0;
    if ((!spc || !spc->str || !spc->len) && (!str || !str->str || !str->len))
	return max? 0: len;

    if ((spcstr = gcstring_concat(spc, str)) == NULL)
	return -1;
    if (!max) {
	len += gcstring_columns(spcstr);
	gcstring_destroy(spcstr);
	return len;
    }

    for (idx = 0, pos = 0; pos < spcstr->gclen; pos++) {
	gcchar_t *gc;
	size_t gcol;

	gc = spcstr->gcstr + pos;
	gcol = gc->col;

	if (max < len + gcol) {
	    if (idx < spc->len)
		idx = 0;
	    else
		idx -= spc->len;
	    gcstring_destroy(spcstr);
	    return idx;
	}
	idx += gc->len;
	len += gcol;
    }
    gcstring_destroy(spcstr);
    return str->len;
}
