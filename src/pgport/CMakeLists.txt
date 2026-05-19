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
    if(LIBPQ_VENDOR_PG_C_FLAGS)
        target_compile_options(${name} PRIVATE ${LIBPQ_VENDOR_PG_C_FLAGS})
    endif()
    target_link_libraries(${name} PUBLIC Threads::Threads)
    if(LIBPQ_WITH_OPENSSL)
        target_link_libraries(${name} PUBLIC OpenSSL::Crypto)
    endif()
    set_target_properties(${name} PROPERTIES C_STANDARD 99)

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
