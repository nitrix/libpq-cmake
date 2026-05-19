# Converts upstream src/interfaces/libpq/exports.txt into an ELF version
# script (`.map`) so the shared libpq exports only the documented entries.
#
# Inputs: EXPORTS_TXT, MAP_FILE

file(STRINGS "${EXPORTS_TXT}" _lines)
set(_syms "")
foreach(_l IN LISTS _lines)
    string(STRIP "${_l}" _l)
    if(_l STREQUAL "" OR _l MATCHES "^#")
        continue()
    endif()
    if(_l MATCHES "^([A-Za-z_][A-Za-z0-9_]*)[ \t]+([0-9]+)$")
        set(_syms "${_syms}        ${CMAKE_MATCH_1};\n")
    endif()
endforeach()
file(WRITE "${MAP_FILE}"
"{
    global:
${_syms}    local:
        *;
};
")
