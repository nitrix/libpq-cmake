set(_common_dir "${PG_SOURCE_DIR}/src/common")

# kwlist_d.h is generated from src/include/parser/kwlist.h by our C tool.
set(_kwlist_input "${PG_SOURCE_DIR}/src/include/parser/kwlist.h")
set(_kwlist_output "${PG_GENERATED_INCLUDE_DIR}/kwlist_d.h")
add_custom_command(
    OUTPUT  "${_kwlist_output}"
    COMMAND $<TARGET_FILE:gen_keywordlist>
            --extern
            --output "${PG_GENERATED_INCLUDE_DIR}"
            "${_kwlist_input}"
    DEPENDS gen_keywordlist "${_kwlist_input}"
    COMMENT "Generating kwlist_d.h"
    VERBATIM)
add_custom_target(pgcommon_kwlist DEPENDS "${_kwlist_output}")

# pgcommon files that libpq actually consumes (transitively). The full
# upstream pgcommon also ships backend helpers (relpath.c, controldata_utils.c,
# blkreftable.c, ...) that would require additional generated catalog
# headers; libpq doesn't need any of them, so we keep the source list lean.
set(_common_sources
    base64.c
    encnames.c
    ip.c
    link-canary.c
    md5_common.c
    pg_prng.c
    psprintf.c
    saslprep.c
    scram-common.c
    string.c
    stringinfo.c
    unicode_norm.c
    wchar.c)

if(LIBPQ_WITH_OPENSSL)
    list(APPEND _common_sources
        cryptohash_openssl.c
        hmac_openssl.c
        protocol_openssl.c)
else()
    list(APPEND _common_sources
        cryptohash.c
        hmac.c
        md5.c
        sha1.c
        sha2.c)
endif()

# Frontend-only helpers also linked into libpq's shared variant.
set(_common_shlib_extra
    fe_memutils.c
    sprompt.c)
# logging.c is added only to the static-only variant by upstream policy
# (shared libpq must not log directly).
set(_common_static_extra logging.c)

set(_common_abs)
foreach(_s IN LISTS _common_sources _common_shlib_extra)
    list(APPEND _common_abs "${_common_dir}/${_s}")
endforeach()
set(_common_abs_static "${_common_abs}")
foreach(_s IN LISTS _common_static_extra)
    list(APPEND _common_abs_static "${_common_dir}/${_s}")
endforeach()

function(_pgcommon_define_target name sources extra_defs)
    add_library(${name} STATIC ${sources})
    add_dependencies(${name} pgcommon_kwlist pg_errcodes)
    target_include_directories(${name} PUBLIC
        "$<BUILD_INTERFACE:${PG_GENERATED_INCLUDE_DIR}>"
        "$<BUILD_INTERFACE:${PG_SOURCE_DIR}/src/include>"
        "$<BUILD_INTERFACE:${PG_SOURCE_DIR}/src/common>"
        "$<BUILD_INTERFACE:${PG_SOURCE_DIR}/src/port>"
        "$<INSTALL_INTERFACE:include>")
    if(WIN32 AND NOT CYGWIN)
        target_include_directories(${name} PUBLIC
            "$<BUILD_INTERFACE:${PG_SOURCE_DIR}/src/include/port/win32>"
            "$<BUILD_INTERFACE:${PG_SOURCE_DIR}/src/include/port/win32_msvc>")
    endif()
    target_compile_definitions(${name} PRIVATE FRONTEND _GNU_SOURCE ${extra_defs})
    target_link_libraries(${name} PUBLIC pgport Threads::Threads)
    if(LIBPQ_WITH_OPENSSL)
        target_link_libraries(${name} PUBLIC OpenSSL::SSL OpenSSL::Crypto)
    endif()
    set_target_properties(${name} PROPERTIES C_STANDARD 99)
endfunction()

_pgcommon_define_target(pgcommon       "${_common_abs_static}" "USE_PRIVATE_ENCODING_FUNCS")
_pgcommon_define_target(pgcommon_shlib "${_common_abs}"         "")
set_target_properties(pgcommon_shlib PROPERTIES POSITION_INDEPENDENT_CODE ON)

if(LIBPQ_INSTALL)
    install(TARGETS pgcommon pgcommon_shlib EXPORT libpq-cmake-targets)
endif()
