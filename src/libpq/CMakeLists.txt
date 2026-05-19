set(_libpq_dir "${PG_SOURCE_DIR}/src/interfaces/libpq")

set(_libpq_sources
    fe-auth-scram.c
    fe-auth.c
    fe-cancel.c
    fe-connect.c
    fe-exec.c
    fe-lobj.c
    fe-misc.c
    fe-print.c
    fe-protocol3.c
    fe-secure.c
    fe-trace.c
    legacy-pqsignal.c
    libpq-events.c
    pqexpbuffer.c)

if(LIBPQ_WITH_OPENSSL)
    list(APPEND _libpq_sources
        fe-secure-common.c
        fe-secure-openssl.c)
endif()

if(WIN32 AND NOT CYGWIN)
    list(APPEND _libpq_sources pthread-win32.c win32.c)
endif()

set(_libpq_sources_abs)

foreach(_s IN LISTS _libpq_sources)
    list(APPEND _libpq_sources_abs "${_libpq_dir}/${_s}")
endforeach()

add_library(libpq_static STATIC ${_libpq_sources_abs})
add_dependencies(libpq_static pg_errcodes)
set_target_properties(libpq_static PROPERTIES
    OUTPUT_NAME pq
    C_STANDARD 99)
target_include_directories(libpq_static PUBLIC
    "$<BUILD_INTERFACE:${PG_GENERATED_INCLUDE_DIR}>"
    "$<BUILD_INTERFACE:${PG_SOURCE_DIR}/src/include>"
    "$<BUILD_INTERFACE:${PG_SOURCE_DIR}/src/interfaces/libpq>"
    "$<BUILD_INTERFACE:${PG_SOURCE_DIR}/src/port>"
    "$<INSTALL_INTERFACE:include>")

if(WIN32 AND NOT CYGWIN)
    target_include_directories(libpq_static PUBLIC
        "$<BUILD_INTERFACE:${PG_SOURCE_DIR}/src/include/port/win32>"
        "$<BUILD_INTERFACE:${PG_SOURCE_DIR}/src/include/port/win32_msvc>")
endif()

target_compile_definitions(libpq_static PRIVATE FRONTEND _GNU_SOURCE)
if(LIBPQ_VENDOR_PG_C_FLAGS)
    target_compile_options(libpq_static PRIVATE ${LIBPQ_VENDOR_PG_C_FLAGS})
endif()
if(WIN32 AND NOT CYGWIN AND NOT MSVC)
    target_compile_options(libpq_static PRIVATE
        -include "${CMAKE_SOURCE_DIR}/cmake/win32_clang_compat.h")
endif()
target_link_libraries(libpq_static PUBLIC pgcommon pgport Threads::Threads)

if(LIBPQ_WITH_OPENSSL)
    target_link_libraries(libpq_static PUBLIC OpenSSL::SSL OpenSSL::Crypto)
endif()

if(WIN32 AND NOT CYGWIN)
    target_link_libraries(libpq_static PUBLIC ws2_32 secur32 wldap32)
elseif(UNIX)
    target_link_libraries(libpq_static PUBLIC m)
endif()

add_library(libpq::libpq_static ALIAS libpq_static)

if(LIBPQ_BUILD_SHARED)
    add_library(libpq_shared SHARED ${_libpq_sources_abs})
    add_dependencies(libpq_shared pg_errcodes)
    set_target_properties(libpq_shared PROPERTIES
        OUTPUT_NAME pq
        C_STANDARD 99
        POSITION_INDEPENDENT_CODE ON
        VERSION "5.${PG_MAJORVERSION_NUM}"
        SOVERSION 5)
    target_include_directories(libpq_shared PUBLIC
        "$<BUILD_INTERFACE:${PG_GENERATED_INCLUDE_DIR}>"
        "$<BUILD_INTERFACE:${PG_SOURCE_DIR}/src/include>"
        "$<BUILD_INTERFACE:${PG_SOURCE_DIR}/src/interfaces/libpq>"
        "$<BUILD_INTERFACE:${PG_SOURCE_DIR}/src/port>"
        "$<INSTALL_INTERFACE:include>")

    if(WIN32 AND NOT CYGWIN)
        target_include_directories(libpq_shared PUBLIC
            "$<BUILD_INTERFACE:${PG_SOURCE_DIR}/src/include/port/win32>"
            "$<BUILD_INTERFACE:${PG_SOURCE_DIR}/src/include/port/win32_msvc>")
    endif()

    target_compile_definitions(libpq_shared PRIVATE
        FRONTEND _GNU_SOURCE SO_MAJOR_VERSION=5)
    if(LIBPQ_VENDOR_PG_C_FLAGS)
        target_compile_options(libpq_shared PRIVATE ${LIBPQ_VENDOR_PG_C_FLAGS})
    endif()
    if(WIN32 AND NOT CYGWIN AND NOT MSVC)
        target_compile_options(libpq_shared PRIVATE
            -include "${CMAKE_SOURCE_DIR}/cmake/win32_clang_compat.h")
    endif()
    target_link_libraries(libpq_shared PUBLIC
        pgcommon_shlib pgport_shlib Threads::Threads)

    if(LIBPQ_WITH_OPENSSL)
        target_link_libraries(libpq_shared PUBLIC OpenSSL::SSL OpenSSL::Crypto)
    endif()

    if(UNIX)
        target_link_libraries(libpq_shared PUBLIC m)
    endif()

    if(WIN32 AND NOT CYGWIN)
        target_link_libraries(libpq_shared PUBLIC ws2_32 secur32 wldap32 shell32)

        set(_def_file "${CMAKE_CURRENT_BINARY_DIR}/libpq.def")
        add_custom_command(
            OUTPUT "${_def_file}"
            COMMAND ${CMAKE_COMMAND}
            -DEXPORTS_TXT=${_libpq_dir}/exports.txt
            -DDEF_FILE=${_def_file}
            -DLIB_NAME=$<TARGET_FILE_PREFIX:libpq_shared>$<TARGET_FILE_BASE_NAME:libpq_shared>
            -P "${CMAKE_SOURCE_DIR}/cmake/MakeExportsDef.cmake"
            DEPENDS "${_libpq_dir}/exports.txt"
            "${CMAKE_SOURCE_DIR}/cmake/MakeExportsDef.cmake"
            VERBATIM)
        target_sources(libpq_shared PRIVATE "${_def_file}")
    elseif(NOT APPLE AND UNIX)
        set(_ver_file "${CMAKE_CURRENT_BINARY_DIR}/libpq.map")
        add_custom_command(
            OUTPUT "${_ver_file}"
            COMMAND ${CMAKE_COMMAND}
            -DEXPORTS_TXT=${_libpq_dir}/exports.txt
            -DMAP_FILE=${_ver_file}
            -P "${CMAKE_SOURCE_DIR}/cmake/MakeExportsMap.cmake"
            DEPENDS "${_libpq_dir}/exports.txt"
            "${CMAKE_SOURCE_DIR}/cmake/MakeExportsMap.cmake"
            VERBATIM)
        add_custom_target(libpq_versionscript DEPENDS "${_ver_file}")
        add_dependencies(libpq_shared libpq_versionscript)
        target_link_options(libpq_shared PRIVATE
            "-Wl,--version-script=${_ver_file}")
    endif()

    add_library(libpq::libpq_shared ALIAS libpq_shared)
endif()

if(LIBPQ_BUILD_SHARED)
    add_library(libpq::libpq ALIAS libpq_shared)
else()
    add_library(libpq::libpq ALIAS libpq_static)
endif()

if(LIBPQ_INSTALL)
    set(_install_targets libpq_static)

    if(LIBPQ_BUILD_SHARED)
        list(APPEND _install_targets libpq_shared)
    endif()

    install(TARGETS ${_install_targets}
        EXPORT libpq-cmake-targets
        RUNTIME DESTINATION bin
        LIBRARY DESTINATION lib
        ARCHIVE DESTINATION lib)
    install(FILES
        "${_libpq_dir}/libpq-int.h"
        "${_libpq_dir}/fe-auth-sasl.h"
        "${_libpq_dir}/pqexpbuffer.h"
        DESTINATION include/postgresql/internal)
    install(FILES "${_libpq_dir}/pg_service.conf.sample"
        DESTINATION share/postgresql)
endif()
