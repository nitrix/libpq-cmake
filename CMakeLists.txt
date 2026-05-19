cmake_minimum_required(VERSION 3.20)
project(libpq-cmake VERSION 17.0 LANGUAGES C)

# --- Options --------------------------------------------------------------
option(LIBPQ_WITH_OPENSSL "Build OpenSSL/TLS support" OFF)
option(LIBPQ_BUILD_SHARED "Build shared libpq in addition to static" OFF)
option(LIBPQ_BUILD_TESTS "Build connect_test executable" OFF)
option(LIBPQ_INSTALL "Generate install/export rules" ON)

# --- Submodule check ------------------------------------------------------
set(PG_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/vendor/postgres")

if(NOT EXISTS "${PG_SOURCE_DIR}/src/interfaces/libpq/fe-connect.c")
    message(FATAL_ERROR
        "vendor/postgres is empty. Initialize the submodule:\n"
        "  git submodule update --init --recursive vendor/postgres")
endif()

# --- PostgreSQL version (parsed from upstream sources) --------------------
file(READ "${PG_SOURCE_DIR}/configure.ac" _pg_configure_ac LIMIT 4096)
string(REGEX MATCH "AC_INIT\\(\\[PostgreSQL\\], \\[([0-9.a-zA-Z]+)\\]"
    _pg_init_match "${_pg_configure_ac}")
set(PG_VERSION "${CMAKE_MATCH_1}")

if(PG_VERSION MATCHES "^([0-9]+)")
    set(PG_MAJORVERSION_NUM "${CMAKE_MATCH_1}")
else()
    set(PG_MAJORVERSION_NUM 17)
endif()

set(PG_MAJORVERSION "${PG_MAJORVERSION_NUM}")

if(PG_VERSION MATCHES "^[0-9]+\\.([0-9]+)")
    set(PG_MINORVERSION_NUM "${CMAKE_MATCH_1}")
else()
    set(PG_MINORVERSION_NUM 0)
endif()

math(EXPR PG_VERSION_NUM "${PG_MAJORVERSION_NUM} * 10000 + ${PG_MINORVERSION_NUM}")
message(STATUS "PostgreSQL: ${PG_VERSION} (major=${PG_MAJORVERSION_NUM}, num=${PG_VERSION_NUM})")

# --- Dependencies ---------------------------------------------------------
find_package(Threads REQUIRED)

if(LIBPQ_WITH_OPENSSL)
    find_package(OpenSSL REQUIRED)
endif()

# Build the C host tools (gen_errcodes, gen_keywordlist) before any
# library target needs the headers they produce.
add_subdirectory(tools)

# --- Platform detection ---------------------------------------------------
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(FindPgPortName)
include(ConfigureChecks)
include(PortSources)

# --- Warning suppressions for vendored upstream-PostgreSQL sources -------
#
# Upstream Postgres is portable C that triggers a couple of clang-only
# warnings we can't fix from this repo. We funnel them through one variable
# applied PRIVATE-ly to pgport / pgcommon / libpq so consumers of
# libpq::libpq don't inherit any -Wno-* flags from us.
set(LIBPQ_VENDOR_PG_C_FLAGS "")
if(CMAKE_C_COMPILER_ID MATCHES "^(Clang|AppleClang)$")
    # `pg_attribute_printf(...)` expands to
    # `__attribute__((format(gnu_printf, ...)))` on GCC-style compilers.
    # Plain clang / AppleClang only know the `printf` archetype on
    # non-MinGW targets and emit -Wignored-attributes for every printf-like
    # declaration in port.h / fe_memutils.h (hundreds per build).
    list(APPEND LIBPQ_VENDOR_PG_C_FLAGS -Wno-ignored-attributes)
endif()
if(CMAKE_C_COMPILER_ID STREQUAL "AppleClang")
    # snprintf.c calls strchrnul(), introduced in the macOS 15.4 SDK. The
    # macos-15 runners build with a 15.0 deployment target but already have
    # strchrnul at runtime, so the unguarded-availability diagnostic is
    # cosmetic. Silencing it keeps the macOS log clean.
    list(APPEND LIBPQ_VENDOR_PG_C_FLAGS -Wno-unguarded-availability-new)
endif()

# --- Generated headers ----------------------------------------------------
set(PG_GENERATED_INCLUDE_DIR "${CMAKE_BINARY_DIR}/include")
file(MAKE_DIRECTORY "${PG_GENERATED_INCLUDE_DIR}")

configure_file("${CMAKE_CURRENT_SOURCE_DIR}/cmake/pg_config.h.in"
    "${PG_GENERATED_INCLUDE_DIR}/pg_config.h" @ONLY)
configure_file("${CMAKE_CURRENT_SOURCE_DIR}/cmake/pg_config_ext.h.in"
    "${PG_GENERATED_INCLUDE_DIR}/pg_config_ext.h" @ONLY)
configure_file("${CMAKE_CURRENT_SOURCE_DIR}/cmake/pg_config_paths.h.in"
    "${PG_GENERATED_INCLUDE_DIR}/pg_config_paths.h" @ONLY)
configure_file("${PG_SOURCE_DIR}/src/include/port/${PG_PORTNAME}.h"
    "${PG_GENERATED_INCLUDE_DIR}/pg_config_os.h" COPYONLY)

# Generated headers normally produced by upstream Makefiles -----------------

# utils/errcodes.h — generated from src/backend/utils/errcodes.txt and
# pulled in (transitively via postgres.h) by hashfn.c and friends.
set(_errcodes_dir "${PG_GENERATED_INCLUDE_DIR}/utils")
file(MAKE_DIRECTORY "${_errcodes_dir}")
add_custom_command(
    OUTPUT "${_errcodes_dir}/errcodes.h"
    COMMAND $<TARGET_FILE:gen_errcodes>
    "${PG_SOURCE_DIR}/src/backend/utils/errcodes.txt"
    "${_errcodes_dir}/errcodes.h"
    DEPENDS gen_errcodes
    "${PG_SOURCE_DIR}/src/backend/utils/errcodes.txt"
    COMMENT "Generating utils/errcodes.h"
    VERBATIM)
add_custom_target(pg_errcodes DEPENDS "${_errcodes_dir}/errcodes.h")

# --- Subprojects ----------------------------------------------------------
add_subdirectory(src/pgport)
add_subdirectory(src/pgcommon)
add_subdirectory(src/libpq)

if(LIBPQ_BUILD_TESTS)
    enable_testing()
    add_subdirectory(test)
endif()

# --- Install / export -----------------------------------------------------
if(LIBPQ_INSTALL)
    include(CMakePackageConfigHelpers)
    install(FILES
        "${PG_SOURCE_DIR}/src/interfaces/libpq/libpq-fe.h"
        "${PG_SOURCE_DIR}/src/interfaces/libpq/libpq-events.h"
        "${PG_SOURCE_DIR}/src/include/postgres_ext.h"
        "${PG_GENERATED_INCLUDE_DIR}/pg_config_ext.h"
        DESTINATION include)
    install(EXPORT libpq-cmake-targets
        FILE libpq-cmake-targets.cmake
        NAMESPACE libpq::
        DESTINATION lib/cmake/libpq-cmake)
    write_basic_package_version_file(
        "${CMAKE_CURRENT_BINARY_DIR}/libpq-cmake-config-version.cmake"
        VERSION ${PROJECT_VERSION}
        COMPATIBILITY SameMajorVersion)
    configure_package_config_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/cmake/libpq-cmake-config.cmake.in"
        "${CMAKE_CURRENT_BINARY_DIR}/libpq-cmake-config.cmake"
        INSTALL_DESTINATION lib/cmake/libpq-cmake)
    install(FILES
        "${CMAKE_CURRENT_BINARY_DIR}/libpq-cmake-config.cmake"
        "${CMAKE_CURRENT_BINARY_DIR}/libpq-cmake-config-version.cmake"
        DESTINATION lib/cmake/libpq-cmake)
endif()
