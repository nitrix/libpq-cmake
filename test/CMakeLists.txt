add_executable(connect_test connect_test.c)
target_link_libraries(connect_test PRIVATE libpq::libpq)
target_include_directories(connect_test PRIVATE
    "${PG_SOURCE_DIR}/src/interfaces/libpq"
    "${PG_SOURCE_DIR}/src/include")

add_test(NAME connect_test COMMAND connect_test)
set_tests_properties(connect_test PROPERTIES
    ENVIRONMENT "PG_CONNINFO=$ENV{PG_CONNINFO}"
    TIMEOUT 30)
