# All the autoconf-style probes that libpq+pgcommon+pgport rely on.
# Sets cache variables consumed by cmake/pg_config.h.in via @VAR@ substitution
# and #cmakedefine guards.

include(CheckIncludeFile)
include(CheckSymbolExists)
include(CheckFunctionExists)
include(CheckTypeSize)
include(CheckCSourceCompiles)
include(CheckCSourceRuns)
include(CheckStructHasMember)
include(TestBigEndian)

# --- Headers --------------------------------------------------------------

set(_pg_headers
    atomic.h crtdefs.h editline/history.h editline/readline.h execinfo.h
    getopt.h gssapi/gssapi.h gssapi.h gssapi/gssapi_ext.h gssapi_ext.h
    history.h ifaddrs.h inttypes.h langinfo.h mbarrier.h memory.h
    ossp/uuid.h pam/pam_appl.h readline.h readline/history.h readline/readline.h
    security/pam_appl.h stdint.h stdlib.h strings.h string.h
    sys/epoll.h sys/event.h sys/personality.h sys/prctl.h sys/procctl.h
    sys/signalfd.h sys/stat.h sys/types.h sys/ucred.h
    termios.h ucred.h unistd.h uuid.h uuid/uuid.h copyfile.h)

foreach(_h IN LISTS _pg_headers)
    string(TOUPPER "${_h}" _u)
    string(REGEX REPLACE "[/.]" "_" _u "${_u}")
    check_include_file("${_h}" HAVE_${_u})
endforeach()

# --- Function probes ------------------------------------------------------

set(CMAKE_REQUIRED_DEFINITIONS_BACKUP "${CMAKE_REQUIRED_DEFINITIONS}")
list(APPEND CMAKE_REQUIRED_DEFINITIONS -D_GNU_SOURCE)

set(_pg_funcs
    backtrace_symbols copy_file_range copyfile explicit_bzero
    getifaddrs getopt getopt_long getpeereid getpeerucred
    history_truncate_file inet_aton inet_pton kqueue mbstowcs_l
    mkdtemp posix_fadvise posix_fallocate ppoll
    pthread_barrier_wait pthread_is_threaded_np
    rl_completion_matches rl_filename_completion_function
    rl_reset_screen_size rl_variable_bind
    setproctitle setproctitle_fast strerror_r
    strlcat strlcpy strnlen strsignal
    sync_file_range syncfs timingsafe_bcmp uselocale wcstombs_l)

foreach(_f IN LISTS _pg_funcs)
    string(TOUPPER "${_f}" _u)
    check_function_exists("${_f}" HAVE_${_u})
endforeach()

# strerror_r returns int (XSI) on most systems we care about; glibc default is
# char*. Detect by looking at the prototype signature.
check_c_source_compiles("
#define _XOPEN_SOURCE 600
#include <string.h>
int main(void) {
    char b[64];
    int r = strerror_r(0, b, sizeof b);
    return r;
}" STRERROR_R_INT)

# decl probes (HAVE_DECL_*): autoconf records 0/1 for declared, libpq sources
# expect the macro to always be defined. Default to 1 if function probe found.
foreach(_pair
    "fdatasync;HAVE_DECL_FDATASYNC"
    "F_FULLFSYNC;HAVE_DECL_F_FULLFSYNC"
    "memset_s;HAVE_DECL_MEMSET_S"
    "posix_fadvise;HAVE_DECL_POSIX_FADVISE"
    "preadv;HAVE_DECL_PREADV"
    "pwritev;HAVE_DECL_PWRITEV"
    "strchrnul;HAVE_DECL_STRCHRNUL"
    "strlcat;HAVE_DECL_STRLCAT"
    "strlcpy;HAVE_DECL_STRLCPY"
    "strnlen;HAVE_DECL_STRNLEN"
    "timingsafe_bcmp;HAVE_DECL_TIMINGSAFE_BCMP")
    string(REPLACE ";" "|" _p "${_pair}")
    string(REGEX REPLACE "^([^|]+)\\|(.+)$" "\\1" _sym "${_p}")
    string(REGEX REPLACE "^([^|]+)\\|(.+)$" "\\2" _var "${_p}")
    if(_sym STREQUAL "F_FULLFSYNC")
        check_symbol_exists(F_FULLFSYNC "fcntl.h" ${_var})
    elseif(_sym STREQUAL "fdatasync")
        check_symbol_exists(fdatasync "unistd.h" ${_var})
    elseif(_sym STREQUAL "memset_s")
        check_symbol_exists(memset_s "string.h" ${_var})
    elseif(_sym STREQUAL "posix_fadvise")
        check_symbol_exists(posix_fadvise "fcntl.h" ${_var})
    elseif(_sym STREQUAL "preadv")
        check_symbol_exists(preadv "sys/uio.h" ${_var})
    elseif(_sym STREQUAL "pwritev")
        check_symbol_exists(pwritev "sys/uio.h" ${_var})
    elseif(_sym STREQUAL "strchrnul")
        check_symbol_exists(strchrnul "string.h" ${_var})
    elseif(_sym STREQUAL "strlcat")
        check_symbol_exists(strlcat "string.h" ${_var})
    elseif(_sym STREQUAL "strlcpy")
        check_symbol_exists(strlcpy "string.h" ${_var})
    elseif(_sym STREQUAL "strnlen")
        check_symbol_exists(strnlen "string.h" ${_var})
    elseif(_sym STREQUAL "timingsafe_bcmp")
        check_symbol_exists(timingsafe_bcmp "string.h" ${_var})
    endif()
endforeach()

set(CMAKE_REQUIRED_DEFINITIONS "${CMAKE_REQUIRED_DEFINITIONS_BACKUP}")

# --- Types ----------------------------------------------------------------

check_type_size("long"          SIZEOF_LONG)
check_type_size("off_t"         SIZEOF_OFF_T)
check_type_size("size_t"        SIZEOF_SIZE_T)
check_type_size("void*"         SIZEOF_VOID_P)
check_type_size("bool"          SIZEOF_BOOL)
check_type_size("long long int" SIZEOF_LONG_LONG_INT)

if(SIZEOF_LONG EQUAL 8)
    set(HAVE_LONG_INT_64 1)
    set(PG_INT64_TYPE "long int")
    set(INT64_MODIFIER "\"l\"")
elseif(SIZEOF_LONG_LONG_INT EQUAL 8)
    set(HAVE_LONG_LONG_INT_64 1)
    set(PG_INT64_TYPE "long long int")
    set(INT64_MODIFIER "\"ll\"")
else()
    message(FATAL_ERROR "Need a 64-bit integer type")
endif()

# 128-bit integer
check_c_source_compiles("
int main(void) { __int128 x = 0; return (int)x; }
" HAVE___INT128)
if(HAVE___INT128)
    set(PG_INT128_TYPE "__int128")
    set(ALIGNOF_PG_INT128_TYPE 16)
endif()

# Alignments
check_c_source_runs("
#include <stddef.h>
#include <stdio.h>
struct s_int { char c; int x; };
int main(void) { printf(\"%d\", (int)offsetof(struct s_int, x)); return 0; }
" _dummy_run_int)
# Hardcode reasonable defaults; libpq itself rarely cares about backend alignment.
set(ALIGNOF_SHORT 2)
set(ALIGNOF_INT 4)
if(SIZEOF_LONG EQUAL 8)
    set(ALIGNOF_LONG 8)
else()
    set(ALIGNOF_LONG 4)
endif()
set(ALIGNOF_LONG_LONG_INT 8)
set(ALIGNOF_DOUBLE 8)
set(MAXIMUM_ALIGNOF 8)

# socklen_t
if(WIN32 AND NOT CYGWIN)
    check_symbol_exists(socklen_t "ws2tcpip.h" HAVE_SOCKLEN_T)
else()
    check_symbol_exists(socklen_t "sys/socket.h" HAVE_SOCKLEN_T)
endif()

check_struct_has_member("struct sockaddr" sa_len "sys/socket.h"
                        HAVE_STRUCT_SOCKADDR_SA_LEN)
check_struct_has_member("struct tm" tm_zone "time.h"
                        HAVE_STRUCT_TM_TM_ZONE)
check_struct_has_member("struct option" name "getopt.h"
                        HAVE_STRUCT_OPTION)

# fseeko
check_c_source_compiles("
#define _LARGEFILE_SOURCE
#include <stdio.h>
int main(void) { FILE *f = stdin; return (int)fseeko(f, 0, 0); }
" HAVE_FSEEKO)

# --- Compiler builtins ----------------------------------------------------

check_c_source_compiles("int main(void) { return __builtin_bswap16(1); }"
                        HAVE__BUILTIN_BSWAP16)
check_c_source_compiles("int main(void) { return __builtin_bswap32(1); }"
                        HAVE__BUILTIN_BSWAP32)
check_c_source_compiles("int main(void) { return (int)__builtin_bswap64(1); }"
                        HAVE__BUILTIN_BSWAP64)
check_c_source_compiles("int main(void) { return __builtin_clz(1); }"
                        HAVE__BUILTIN_CLZ)
check_c_source_compiles("int main(void) { return __builtin_ctz(1); }"
                        HAVE__BUILTIN_CTZ)
check_c_source_compiles("int main(void) { return __builtin_popcount(1); }"
                        HAVE__BUILTIN_POPCOUNT)
check_c_source_compiles("int main(void) { return __builtin_constant_p(1); }"
                        HAVE__BUILTIN_CONSTANT_P)
check_c_source_compiles("int main(void) { __builtin_unreachable(); }"
                        HAVE__BUILTIN_UNREACHABLE)
check_c_source_compiles("int main(void) {
    int a = 1, b = 2, r;
    return __builtin_add_overflow(a, b, &r) ? 1 : r;
}" HAVE__BUILTIN_OP_OVERFLOW)
check_c_source_compiles("int main(void) {
    return __builtin_types_compatible_p(int, int) ? 0 : 1;
}" HAVE__BUILTIN_TYPES_COMPATIBLE_P)
check_c_source_compiles("int main(int argc, char **argv) {
    return (int)__builtin_frame_address(0) ? 0 : argc;
}" HAVE__BUILTIN_FRAME_ADDRESS)
check_c_source_compiles("int main(void) { _Static_assert(1, \"x\"); return 0; }"
                        HAVE__STATIC_ASSERT)
check_c_source_compiles("int main(void) { typeof(int) x = 0; return x; }"
                        HAVE_TYPEOF)
check_c_source_compiles("
__attribute__((visibility(\"hidden\"))) int f(void) { return 0; }
int main(void) { return f(); }
" HAVE_VISIBILITY_ATTRIBUTE)
check_c_source_compiles("
static int x;
int main(int argc, char **argv) {
    void *labels[] = { &&l1, &&l2 };
    goto *labels[argc % 2];
l1: x = 1; return x;
l2: x = 2; return x;
}" HAVE_COMPUTED_GOTO)

# GCC-style atomics / sync
check_c_source_compiles("
int main(void) {
    int x = 0, e = 0;
    return __atomic_compare_exchange_n(&x, &e, 1, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST) ? 0 : 1;
}" HAVE_GCC__ATOMIC_INT32_CAS)
check_c_source_compiles("
#include <stdint.h>
int main(void) {
    int64_t x = 0, e = 0;
    return __atomic_compare_exchange_n(&x, &e, 1, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST) ? 0 : 1;
}" HAVE_GCC__ATOMIC_INT64_CAS)
check_c_source_compiles("
int main(void) { int x = 0; return __sync_val_compare_and_swap(&x, 0, 1); }
" HAVE_GCC__SYNC_INT32_CAS)
check_c_source_compiles("
int main(void) { int x = 0; return __sync_lock_test_and_set(&x, 1); }
" HAVE_GCC__SYNC_INT32_TAS)
check_c_source_compiles("
#include <stdint.h>
int main(void) { int64_t x = 0; return (int)__sync_val_compare_and_swap(&x, 0, 1); }
" HAVE_GCC__SYNC_INT64_CAS)
check_c_source_compiles("
int main(void) { char x = 0; return __sync_lock_test_and_set(&x, 1); }
" HAVE_GCC__SYNC_CHAR_TAS)

if(HAVE_GCC__ATOMIC_INT32_CAS OR HAVE_GCC__SYNC_INT32_CAS OR WIN32)
    set(HAVE_ATOMICS 1)
    set(HAVE_SPINLOCKS 1)
endif()

# Standard ANSI / int types
set(STDC_HEADERS 1)
check_c_source_compiles("
#include <stdbool.h>
int main(void) { _Bool b = false; return b; }
" PG_USE_STDBOOL)

# printf attribute archetype
check_c_source_compiles("
__attribute__((format(gnu_printf, 1, 2))) void f(const char *fmt, ...);
int main(void) { return 0; }
" _have_gnu_printf)
if(_have_gnu_printf)
    set(PG_C_PRINTF_ATTRIBUTE "gnu_printf")
    set(PG_CXX_PRINTF_ATTRIBUTE "gnu_printf")
else()
    set(PG_C_PRINTF_ATTRIBUTE "printf")
    set(PG_CXX_PRINTF_ATTRIBUTE "printf")
endif()

# inline / restrict / typeof are handled by C99 directly
set(_inline_kw "inline")
set(_restrict_kw "__restrict")

# --- CRC32C selection -----------------------------------------------------

check_c_source_compiles("
#include <nmmintrin.h>
int main(void) { unsigned int c = 0; c = _mm_crc32_u8(c, 1); c = _mm_crc32_u32(c, 1); return c; }
" _pg_have_sse42_crc)

check_c_source_compiles("
#include <arm_acle.h>
int main(void) { unsigned int c = 0; c = __crc32cb(c, 1); c = __crc32cw(c, 1); return c; }
" _pg_have_armv8_crc)

check_c_source_compiles("
unsigned int f(unsigned int a, unsigned int b) {
    return __builtin_ia32_crc32qi(a, (unsigned char)b);
}
int main(void) { return (int)f(0, 1); }
" _pg_have_builtin_ia32_crc)

if(_pg_have_sse42_crc OR _pg_have_builtin_ia32_crc)
    set(USE_SSE42_CRC32C_WITH_RUNTIME_CHECK 1)
elseif(_pg_have_armv8_crc)
    set(USE_ARMV8_CRC32C_WITH_RUNTIME_CHECK 1)
else()
    set(USE_SLICING_BY_8_CRC32C 1)
endif()

# x86 popcount
check_c_source_compiles("
int main(void) {
    __asm__ __volatile__ (\"popcntq %1,%0\" : \"=r\"(c) : \"rm\"(0));
    return 0;
}" HAVE_X86_64_POPCNTQ)
check_c_source_compiles("
#include <immintrin.h>
int main(void) {
    unsigned long long r = _mm512_reduce_add_epi64(_mm512_set1_epi64(1));
    return (int)r;
}" _pg_have_avx512)
if(_pg_have_avx512)
    set(USE_AVX512_POPCNT_WITH_RUNTIME_CHECK 1)
endif()
check_c_source_compiles("
#include <immintrin.h>
int main(void) {
    unsigned int a, b, c, d;
    return __get_cpuid(1, &a, &b, &c, &d);
}" _pg_have_get_cpuid)
if(_pg_have_get_cpuid)
    set(HAVE__GET_CPUID 1)
endif()
check_c_source_compiles("
#include <immintrin.h>
int main(void) {
    unsigned int a, b, c, d;
    return __get_cpuid_count(7, 0, &a, &b, &c, &d);
}" _pg_have_get_cpuid_count)
if(_pg_have_get_cpuid_count)
    set(HAVE__GET_CPUID_COUNT 1)
endif()
check_c_source_compiles("
#include <intrin.h>
int main(void) { int info[4]; __cpuid(info, 1); return info[0]; }
" _pg_have__cpuid)
if(_pg_have__cpuid)
    set(HAVE__CPUID 1)
endif()
check_c_source_compiles("
#include <intrin.h>
int main(void) { int info[4]; __cpuidex(info, 7, 0); return info[0]; }
" _pg_have__cpuidex)
if(_pg_have__cpuidex)
    set(HAVE__CPUIDEX 1)
endif()
check_c_source_compiles("
#include <immintrin.h>
int main(void) {
    unsigned long long x = _xgetbv(0);
    return (int)x;
}" HAVE_XSAVE_INTRINSICS)

# Compile flags for CRC and popcount variants
set(PG_CFLAGS_CRC "")
set(PG_CFLAGS_POPCNT "")
set(PG_CFLAGS_XSAVE "")
if(NOT MSVC)
    if(USE_SSE42_CRC32C_WITH_RUNTIME_CHECK)
        set(PG_CFLAGS_CRC "-msse4.2")
    elseif(USE_ARMV8_CRC32C_WITH_RUNTIME_CHECK)
        set(PG_CFLAGS_CRC "-march=armv8-a+crc")
    endif()
    if(USE_AVX512_POPCNT_WITH_RUNTIME_CHECK)
        set(PG_CFLAGS_POPCNT "-mavx512vpopcntdq;-mavx512bw")
        set(PG_CFLAGS_XSAVE  "-mxsave")
    endif()
endif()

# --- Endianness, file offset ----------------------------------------------

test_big_endian(_pg_big_endian)
if(_pg_big_endian)
    set(WORDS_BIGENDIAN 1)
endif()

if(NOT WIN32 AND NOT APPLE)
    set(_FILE_OFFSET_BITS 64)
    set(_LARGEFILE_SOURCE 1)
endif()

# --- Misc fixed values ----------------------------------------------------

set(BLCKSZ        8192)
set(XLOG_BLCKSZ   8192)
set(RELSEG_SIZE   131072)        # 1GB / 8KB
set(DEF_PGPORT     5432)
set(DEF_PGPORT_STR "\"5432\"")
set(PG_KRB_SRVNAM  "\"postgres\"")
set(PG_VERSION_STR "\"PostgreSQL ${PG_VERSION} on cmake-built libpq, compiled by ${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION}\"")
set(MEMSET_LOOP_LIMIT 1024)
set(PROFILE_PID_DIR 0)
set(CONFIGURE_ARGS "\"--with-cmake\"")
set(PACKAGE_NAME        "\"PostgreSQL\"")
set(PACKAGE_TARNAME     "\"postgresql\"")
set(PACKAGE_VERSION     "\"${PG_VERSION}\"")
set(PACKAGE_STRING      "\"PostgreSQL ${PG_VERSION}\"")
set(PACKAGE_BUGREPORT   "\"pgsql-bugs@lists.postgresql.org\"")
set(PACKAGE_URL         "\"https://www.postgresql.org/\"")

if(WIN32 AND NOT CYGWIN)
    set(DLSUFFIX "\".dll\"")
elseif(APPLE)
    set(DLSUFFIX "\".dylib\"")
else()
    set(DLSUFFIX "\".so\"")
endif()

# OpenSSL-related macros
if(LIBPQ_WITH_OPENSSL)
    set(USE_OPENSSL 1)
    set(HAVE_LIBSSL 1)
    set(HAVE_LIBCRYPTO 1)
    set(OPENSSL_API_COMPAT 0x10002000L)
    set(CMAKE_REQUIRED_LIBRARIES_BACKUP "${CMAKE_REQUIRED_LIBRARIES}")
    set(CMAKE_REQUIRED_INCLUDES "${OPENSSL_INCLUDE_DIR}")
    set(CMAKE_REQUIRED_LIBRARIES OpenSSL::SSL OpenSSL::Crypto)
    foreach(_ssl_fn
        ASN1_STRING_get0_data BIO_meth_new CRYPTO_lock
        HMAC_CTX_free HMAC_CTX_new OPENSSL_init_ssl
        SSL_CTX_set_cert_cb SSL_CTX_set_num_tickets
        X509_get_signature_info)
        string(TOUPPER "${_ssl_fn}" _u)
        check_function_exists("${_ssl_fn}" HAVE_${_u})
    endforeach()
    set(CMAKE_REQUIRED_LIBRARIES "${CMAKE_REQUIRED_LIBRARIES_BACKUP}")
endif()

# Threads
set(HAVE_PTHREAD 1)
if(NOT WIN32)
    set(PTHREAD_CREATE_JOINABLE PTHREAD_CREATE_JOINABLE)
endif()

# Locale-in-xlocale: macOS pre-Catalina needed it; Catalina+ have <locale.h>
if(APPLE)
    check_include_file("xlocale.h" HAVE_XLOCALE_H)
    if(HAVE_XLOCALE_H AND NOT HAVE_USELOCALE)
        set(LOCALE_T_IN_XLOCALE 1)
    endif()
endif()
