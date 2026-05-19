add_executable(gen_errcodes      gen_errcodes.c)
add_executable(gen_keywordlist   gen_keywordlist.c)

set_target_properties(gen_errcodes gen_keywordlist PROPERTIES
    C_STANDARD       99
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tools")
