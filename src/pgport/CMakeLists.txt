function(_pgport_define_target name extra_flags)
    add_library(${name} STATIC ${PGPORT_SOURCES}
                ${PGPORT_SOURCES_CRC}
                ${PGPORT_SOURCES_POPCNT}
                ${PGPORT_SOURCES_XSAVE})
    add_dependencies(${name} pg_errcodes)
    target_include_directories(${name} PUBLIC
        "$<BUILD_INTERFACE:${PG_GENERATED_INCLUDE_DIR}>"
        "$<BUILD_INTERFACE:${PG_SOURCE_DIR}/src/include>"
        "$<BUILD_INTERFACE:${PG_SOURCE_DIR}/src/port>"
        "$<INSTALL_INTERFACE:include>")
    target_compile_definitions(${name} PRIVATE FRONTEND _GNU_SOURCE)
    if(WIN32 AND NOT CYGWIN)
        target_compile_definitions(${name} PRIVATE
            WIN32_STACK_RLIMIT=4194304
            BUILDING_DLL)
        target_include_directories(${name} PUBLIC
            "$<BUILD_INTERFACE:${PG_SOURCE_DIR}/src/include/port/win32>"
            "$<BUILD_INTERFACE:${PG_SOURCE_DIR}/src/include/port/win32_msvc>")
    endif()
    if(extra_flags)
        target_compile_options(${name} PRIVATE ${extra_flags})
    endif()
    target_link_libraries(${name} PUBLIC Threads::Threads)
    # pg_strong_random.c does `#include <openssl/rand.h>` under USE_OPENSSL,
    # so pgport itself needs OpenSSL's headers (and libcrypto) when the
    # build is configured with TLS support. Linking the imported target
    # also propagates the right include directories to consumers.
    if(LIBPQ_WITH_OPENSSL)
        target_link_libraries(${name} PUBLIC OpenSSL::Crypto)
    endif()
    set_target_properties(${name} PROPERTIES C_STANDARD 99)

    # Per-source flag overrides (CRC, POPCNT, XSAVE)
    foreach(_src IN LISTS PGPORT_SOURCES_CRC)
        set_source_files_properties("${_src}" PROPERTIES
            COMPILE_OPTIONS "${PG_CFLAGS_CRC}")
    endforeach()
    foreach(_src IN LISTS PGPORT_SOURCES_POPCNT)
        set_source_files_properties("${_src}" PROPERTIES
            COMPILE_OPTIONS "${PG_CFLAGS_POPCNT}")
    endforeach()
    foreach(_src IN LISTS PGPORT_SOURCES_XSAVE)
        set_source_files_properties("${_src}" PROPERTIES
            COMPILE_OPTIONS "${PG_CFLAGS_XSAVE}")
    endforeach()
endfunction()

_pgport_define_target(pgport "")
_pgport_define_target(pgport_shlib "")
set_target_properties(pgport_shlib PROPERTIES POSITION_INDEPENDENT_CODE ON)

if(LIBPQ_INSTALL)
    install(TARGETS pgport pgport_shlib EXPORT libpq-cmake-targets)
endif()
