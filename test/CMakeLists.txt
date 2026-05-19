add_executable(connect_test connect_test.c)
target_link_libraries(connect_test PRIVATE libpq::libpq)
target_include_directories(connect_test PRIVATE
    "${PG_SOURCE_DIR}/src/interfaces/libpq"
    "${PG_SOURCE_DIR}/src/include")

# Windows (native, not cygwin): no rpath, so a shared libpq.dll has to
# either live on PATH or sit next to the consumer. ctest doesn't tweak
# PATH for us and the runner image's PATH doesn't include our build
# tree, so the previous run's msys2-clang64 ctest exited with
# 0xC0000135 (STATUS_DLL_NOT_FOUND) before connect_test's main() even
# started. Copying the import library next to connect_test.exe after
# build is a no-op on every other generator and platform.
if(WIN32 AND NOT CYGWIN AND TARGET libpq_shared)
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
