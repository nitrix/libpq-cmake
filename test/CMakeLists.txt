add_executable(connect_test connect_test.c)
target_link_libraries(connect_test PRIVATE libpq::libpq)
target_include_directories(connect_test PRIVATE
    "${PG_SOURCE_DIR}/src/interfaces/libpq"
    "${PG_SOURCE_DIR}/src/include")

# Windows-flavored loaders (native Windows AND cygwin) follow Windows
# DLL search order, which doesn't include arbitrary build subdirs. ctest
# doesn't tweak PATH for us and the runner image's PATH doesn't include
# our build tree, so a connect_test.exe that depends on libpq.dll /
# cygpq-5.dll exits with STATUS_DLL_NOT_FOUND before main() even runs
# — the failure shows up as a ~20 ms test with no captured stderr.
# Copying the shared lib next to connect_test.exe sidesteps that on
# every PE target (msvc, mingw, msys2-clang64, cygwin). It's a no-op
# on Linux/macOS because the condition is false there.
if((WIN32 OR CYGWIN) AND TARGET libpq_shared)
    add_custom_command(TARGET connect_test POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:libpq_shared>
            $<TARGET_FILE_DIR:connect_test>
        VERBATIM)
endif()

add_test(NAME connect_test COMMAND connect_test)
set_tests_properties(connect_test PROPERTIES
    ENVIRONMENT "PG_CONNINFO=$ENV{PG_CONNINFO}"
    TIMEOUT 30)
