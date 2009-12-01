# Process this file with autoconf to produce a configure script.

AC_PREREQ(2.59)
AC_INIT(linebreak, 1.4.520.p1, hatuka@nezumi.nu)
DEFAULT_UNICODE_VERSION="5.2.0"
LPATH="$PATH:/usr/local/bin"

AM_INIT_AUTOMAKE
AC_CONFIG_HEADER([config.h])

# Checks for programs.
AC_PROG_MAKE_SET
AM_PROG_LIBTOOL
AC_PROG_INSTALL
AC_PROG_LN_S
AC_PROG_CC
#AC_PROG_RANLIB

# Checks for libraries.
#AM_ICONV

# Checks for header files.
#AC_HEADER_STDC
AC_CHECK_HEADERS([errno.h stdlib.h stddef.h string.h wchar.h strings.h])

# Checks for typedefs, structures, and compiler characteristics.
AC_C_CONST
AC_TYPE_SIZE_T

# Checks for library functions.
#AC_FUNC_MALLOC
AC_CHECK_FUNCS([strerror])
AM_CONDITIONAL(HAVE_STRERROR, [test "$ac_cv_func_strerror" = "yes"])
AC_CHECK_FUNCS([strcasecmp])
AM_CONDITIONAL(HAVE_STRCASECMP, [test "$ac_cv_func_strcasecmp" = "yes"])

PKG_CHECK_MODULES(LIBTHAI, [libthai],
  [LIBTHAI="libthai/`$PKG_CONFIG --modversion libthai`"], [LIBTHAI=])
AC_MSG_CHECKING(whether libthai support enabled)
AC_ARG_ENABLE(libthai,
  [  --disable-libthai       Disable libthai support],
  [],
  [enable_libthai=yes])
if test -z "$LIBTHAI"
then
  enable_libthai=no
fi
if test "$enable_libthai" = "no"
then
  AC_MSG_RESULT(no.)
else
  AC_DEFINE_UNQUOTED(USE_LIBTHAI, "$LIBTHAI",
    [ Set this to use libthai library. ])
  AC_SUBST(LIBTHAI_CFLAGS)
  AC_SUBST(LIBTHAI_LIBS)
  AC_MSG_RESULT($LIBTHAI)
fi

AC_MSG_CHECKING(what version of Unicode standard will be used)
AC_ARG_WITH(unicode-version,
  AC_HELP_STRING(--with-unicode-version=version,
  [version of Unicode standard]),
  UNICODE_VERSION=$withval,UNICODE_VERSION=$DEFAULT_UNICODE_VERSION)
AC_CHECK_FILE([lib/$UNICODE_VERSION.c],
  AC_MSG_RESULT(Use Unicode version $UNICODE_VERSION),
  AC_MSG_ERROR(unknown Unicode version $UNICODE_VERSION))
AC_SUBST(UNICODE_VERSION)

AC_CONFIG_FILES(Makefile liblinebreak.pc)
AC_OUTPUT
