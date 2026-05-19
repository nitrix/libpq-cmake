# Resolves PostgreSQL's autoconf-driven LIBOBJS list (per-platform source
# replacements) and CRC32C variant selection into a flat list of pgport
# sources plus per-source compile flag overrides.
#
# Outputs:
#   PGPORT_SOURCES            - .c files compiled into both pgport variants
#   PGPORT_SOURCES_CRC        - .c files needing PG_CFLAGS_CRC
#   PGPORT_SOURCES_POPCNT     - .c files needing PG_CFLAGS_POPCNT
#   PGPORT_SOURCES_XSAVE      - .c files needing PG_CFLAGS_XSAVE

set(_pgport_dir "${PG_SOURCE_DIR}/src/port")

set(PGPORT_SOURCES
    "${_pgport_dir}/bsearch_arg.c"
    "${_pgport_dir}/chklocale.c"
    "${_pgport_dir}/inet_net_ntop.c"
    "${_pgport_dir}/noblock.c"
    "${_pgport_dir}/path.c"
    "${_pgport_dir}/pg_bitutils.c"
    "${_pgport_dir}/pg_strong_random.c"
    "${_pgport_dir}/pgcheckdir.c"
    "${_pgport_dir}/pgmkdirp.c"
    "${_pgport_dir}/pgsleep.c"
    "${_pgport_dir}/pgstrcasecmp.c"
    "${_pgport_dir}/pgstrsignal.c"
    "${_pgport_dir}/pqsignal.c"
    "${_pgport_dir}/qsort.c"
    "${_pgport_dir}/qsort_arg.c"
    "${_pgport_dir}/quotes.c"
    "${_pgport_dir}/snprintf.c"
    "${_pgport_dir}/strerror.c"
    "${_pgport_dir}/tar.c"
    "${_pgport_dir}/user.c")

if(WIN32 AND NOT CYGWIN)
    list(APPEND PGPORT_SOURCES
        "${_pgport_dir}/dirmod.c"
        "${_pgport_dir}/kill.c"
        "${_pgport_dir}/open.c"
        "${_pgport_dir}/system.c"
        "${_pgport_dir}/win32common.c"
        "${_pgport_dir}/win32dlopen.c"
        "${_pgport_dir}/win32env.c"
        "${_pgport_dir}/win32error.c"
        "${_pgport_dir}/win32fdatasync.c"
        "${_pgport_dir}/win32fseek.c"
        "${_pgport_dir}/win32gai_strerror.c"
        "${_pgport_dir}/win32getrusage.c"
        "${_pgport_dir}/win32link.c"
        "${_pgport_dir}/win32ntdll.c"
        "${_pgport_dir}/win32pread.c"
        "${_pgport_dir}/win32pwrite.c"
        "${_pgport_dir}/win32security.c"
        "${_pgport_dir}/win32setlocale.c"
        "${_pgport_dir}/win32stat.c")
elseif(CYGWIN)
    list(APPEND PGPORT_SOURCES "${_pgport_dir}/dirmod.c")
endif()

if(MSVC)
    list(APPEND PGPORT_SOURCES
        "${_pgport_dir}/dirent.c"
        "${_pgport_dir}/win32gettimeofday.c")
endif()

# --- LIBOBJS: replacements when libc lacks a function -------------------

set(_pgport_neg
    explicit_bzero getopt getopt_long getpeereid inet_aton mkdtemp
    strlcat strlcpy strnlen timingsafe_bcmp)
if(NOT WIN32 OR CYGWIN)
    list(APPEND _pgport_neg pthread_barrier_wait)
endif()

foreach(_f IN LISTS _pgport_neg)
    string(TOUPPER "${_f}" _u)
    if(NOT HAVE_${_u})
        list(APPEND PGPORT_SOURCES "${_pgport_dir}/${_f}.c")
    endif()
endforeach()

# CRC32C variants
set(PGPORT_SOURCES_CRC)
set(PGPORT_SOURCES_POPCNT)
set(PGPORT_SOURCES_XSAVE)

if(USE_SSE42_CRC32C)
    list(APPEND PGPORT_SOURCES "${_pgport_dir}/pg_crc32c_sse42.c")
elseif(USE_SSE42_CRC32C_WITH_RUNTIME_CHECK)
    list(APPEND PGPORT_SOURCES
        "${_pgport_dir}/pg_crc32c_sse42_choose.c"
        "${_pgport_dir}/pg_crc32c_sb8.c")
    list(APPEND PGPORT_SOURCES_CRC "${_pgport_dir}/pg_crc32c_sse42.c")
elseif(USE_ARMV8_CRC32C)
    list(APPEND PGPORT_SOURCES "${_pgport_dir}/pg_crc32c_armv8.c")
elseif(USE_ARMV8_CRC32C_WITH_RUNTIME_CHECK)
    list(APPEND PGPORT_SOURCES
        "${_pgport_dir}/pg_crc32c_armv8_choose.c"
        "${_pgport_dir}/pg_crc32c_sb8.c")
    list(APPEND PGPORT_SOURCES_CRC "${_pgport_dir}/pg_crc32c_armv8.c")
elseif(USE_LOONGARCH_CRC32C)
    list(APPEND PGPORT_SOURCES "${_pgport_dir}/pg_crc32c_loongarch.c")
else()
    list(APPEND PGPORT_SOURCES "${_pgport_dir}/pg_crc32c_sb8.c")
endif()

if(USE_AVX512_POPCNT_WITH_RUNTIME_CHECK)
    list(APPEND PGPORT_SOURCES_POPCNT "${_pgport_dir}/pg_popcount_avx512.c")
    list(APPEND PGPORT_SOURCES_XSAVE  "${_pgport_dir}/pg_popcount_avx512_choose.c")
endif()

# mingw/cygwin strtof shim
if((WIN32 AND NOT MSVC) OR CYGWIN)
    list(APPEND PGPORT_SOURCES "${_pgport_dir}/strtof.c")
endif()
