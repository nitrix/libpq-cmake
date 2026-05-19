# Converts upstream src/interfaces/libpq/exports.txt into a Windows .def file
# (used to define the export table for libpq.dll on Windows builds).
#
# Inputs: EXPORTS_TXT, DEF_FILE, LIB_NAME

file(STRINGS "${EXPORTS_TXT}" _lines)
set(_out "LIBRARY ${LIB_NAME}\nEXPORTS\n")
foreach(_l IN LISTS _lines)
    string(STRIP "${_l}" _l)
    if(_l STREQUAL "" OR _l MATCHES "^#")
        continue()
    endif()
    if(_l MATCHES "^([A-Za-z_][A-Za-z0-9_]*)[ \t]+([0-9]+)$")
        set(_out "${_out}    ${CMAKE_MATCH_1} @${CMAKE_MATCH_2}\n")
    endif()
endforeach()
file(WRITE "${DEF_FILE}" "${_out}")
