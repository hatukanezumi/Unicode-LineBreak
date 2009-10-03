lib_LTLIBRARIES = libinebreak.la
libinebreak_la_SOURCES = charprop.c gcstring.c linebreak.c southeastasian.c \
			 @UNICODE_VERSION@.c
if !HAVE_STRERROR
libinebreak_la_SOURCES += strerror.c
endif
if !HAVE_STRCASECMP
libinebreak_la_SOURCES += strcasecmp.c
endif
libinebreak_la_CFLAGS = -I. $(LIBTHAI_CFLAGS)
libinebreak_la_LDFLAGS = -version-info 1:0:0 $(LIBTHAI_LIBS)

include_HEADERS = common.h linebreak.h gcstring.h
nodist_include_HEADERS = 

pkgdata_DATA = 
pkgdatasubdir = 
pkgdatasub_DATA = 
EXTRA_DIST = 

