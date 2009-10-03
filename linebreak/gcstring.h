#ifndef _LINEBREAK_GCSTRING_H_
#include "common.h"

extern gcstring_t *gcstring_new(unistr_t *, linebreak_t *);
extern gcstring_t *gcstring_copy(gcstring_t *);
extern void gcstring_destroy(gcstring_t *);
/* extern gcstring_t *gcstring_append(gcstring_t *, gcstring_t *); */
extern size_t gcstring_columns(gcstring_t *);
extern int gcstring_cmp(gcstring_t *, gcstring_t *);
extern gcstring_t *gcstring_concat(gcstring_t *, gcstring_t *);
extern gcchar_t *gcstring_next(gcstring_t *);
extern void gcstring_setpos(gcstring_t *, int);
extern gcstring_t *gcstring_substr(gcstring_t *, int, int, gcstring_t *);

#define gcstring_eot(gcstr) \
  ((gcstr)->gclen <= (gcstr)->pos)
#define gcstring_getpos(gcstr) \
  ((gcstr)->pos)

#define _LINEBREAK_GCSTRING_H_
#endif /* _LINEBREAK_GCSTRING_H_ */
