add_executable(connect_test connect_test.c)
target_link_libraries(connect_test PRIVATE libpq::libpq)
target_include_directories(connect_test PRIVATE
    "${PG_SOURCE_DIR}/src/interfaces/libpq"
    "${PG_SOURCE_DIR}/src/include")

if((WIN32 OR CYGWIN) AND TARGET libpq_shared)
    add_custom_command(TARGET connect_test POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:libpq_shared> $<TARGET_RUNTIME_DLLS:connect_test>
            $<TARGET_FILE_DIR:connect_test>
        COMMAND_EXPAND_LISTS
        VERBATIM)
endif()

add_test(NAME connect_test COMMAND connect_test)
set_tests_properties(connect_test PROPERTIES
    ENVIRONMENT "PG_CONNINFO=$ENV{PG_CONNINFO}"
    TIMEOUT 30)
