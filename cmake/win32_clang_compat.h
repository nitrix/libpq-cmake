/*
 * win32_clang_compat.h — small compatibility shim for non-MSVC Windows
 *                       builds (notably MSYS2 CLANG64 / mingw-w64-clang).
 *
 * Upstream Postgres' src/include/port/win32_port.h only declares
 *
 *   extern int gettimeofday(struct timeval *tp, void *tzp);
 *
 * for `_MSC_VER`, on the assumption that MinGW's <sys/time.h> declares it
 * for us. With current mingw-w64 headers reached after <winsock2.h> has
 * pre-defined the timeval guards (by way of win32_port.h's WIN32_LEAN_AND_
 * MEAN block), that declaration / macro alias is no longer visible at the
 * libpq call sites — fe-connect.c, fe-misc.c and fe-trace.c each call
 * `gettimeofday(&tval, NULL)` directly. Clang then errors out under
 *
 *   -Wimplicit-function-declaration  (a hard error in C99 since clang 16)
 *
 * src/libpq/CMakeLists.txt force-includes this header for libpq's compile
 * units on Windows-non-MSVC builds so the declaration is in scope; the
 * matching symbol is resolved at link time from mingw-w64's libmingwex,
 * which exposes `gettimeofday` (as an alias for mingw_gettimeofday).
 */
#ifndef LIBPQ_CMAKE_WIN32_CLANG_COMPAT_H
#define LIBPQ_CMAKE_WIN32_CLANG_COMPAT_H

#if defined(_WIN32) && !defined(_MSC_VER) && !defined(__CYGWIN__)

/* Forward declaration is enough; the call sites only pass a struct
 * timeval *. We avoid pulling in <sys/time.h> here to dodge any inclusion-
 * order interactions with win32_port.h's WIN32_LEAN_AND_MEAN block. */
struct timeval;

extern int gettimeofday(struct timeval *tp, void *tzp);

#endif

#endif /* LIBPQ_CMAKE_WIN32_CLANG_COMPAT_H */
