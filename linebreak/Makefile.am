lib_LTLIBRARIES = libinebreak.la
libinebreak_la_SOURCES = lib/break.c lib/charprop.c lib/gcstring.c \
			 lib/linebreak.c lib/southeastasian.c \
			 lib/@UNICODE_VERSION@.c
libinebreak_la_CFLAGS = -I. -Iinclude @LIBTHAI_CFLAGS@
libinebreak_la_LDFLAGS = -version-info 1:0:0 @LIBTHAI_LIBS@
if !HAVE_STRERROR
libinebreak_la_SOURCES += src/strerror.c
endif
if !HAVE_STRCASECMP
libinebreak_la_SOURCES += src/strcasecmp.c
endif

include_HEADERS = include/linebreak.h include/linebreak_constants.h
nodist_include_HEADERS = 

pkgdata_DATA = 
pkgdatasubdir = 
pkgdatasub_DATA = 
EXTRA_DIST = 
