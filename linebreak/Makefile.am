lib_LTLIBRARIES = liblinebreak.la
liblinebreak_la_SOURCES = lib/break.c lib/charprop.c lib/gcstring.c \
			  lib/linebreak.c lib/southeastasian.c \
			  lib/@UNICODE_VERSION@.c
liblinebreak_la_CFLAGS = -I. -Iinclude @LIBTHAI_CFLAGS@
liblinebreak_la_LDFLAGS = -version-info 1:1:0 @LIBTHAI_LIBS@
#if !HAVE_STRERROR
#liblinebreak_la_SOURCES += src/strerror.c
#endif
#if !HAVE_STRCASECMP
#liblinebreak_la_SOURCES += src/strcasecmp.c
#endif

include_HEADERS = include/linebreak.h include/linebreak_constants.h
nodist_include_HEADERS = 

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = liblinebreak.pc

pkgdata_DATA = 
pkgdatasubdir = 
pkgdatasub_DATA = 
EXTRA_DIST = 
