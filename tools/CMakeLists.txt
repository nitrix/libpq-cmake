# Host build tools: these run at build time to generate sources that get
# compiled into libpq. They are pure C with no external dependencies, so
# they cross-compile cleanly along with the rest of the build (a true
# cross build would need a separate native-tools step — out of scope here).

add_executable(gen_errcodes      gen_errcodes.c)
add_executable(gen_keywordlist   gen_keywordlist.c)

set_target_properties(gen_errcodes gen_keywordlist PROPERTIES
    C_STANDARD       99
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tools")
