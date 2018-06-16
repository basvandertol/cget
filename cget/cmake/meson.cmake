cmake_minimum_required (VERSION 2.8)

project(meson)
enable_language(C CXX)

include(CTest)

# find meson
find_program(MESON_EXE meson)
if(NOT MESON_EXE)
    message(FATAL_ERROR "Meson build system not installed.")
endif()

find_program(NINJA_EXE ninja)
if(NOT NINJA_EXE)
    message(FATAL_ERROR "Ninja build system not installed.")
endif()
get_filename_component(NINJA_PATH ${NINJA_EXE} DIRECTORY)

set(MESON_OPTIONS)
get_cmake_property(_variableNames VARIABLES)
foreach (VAR ${_variableNames})
    if(VAR MATCHES "MESON_")
        string(TOLOWER ${VAR} OPTION)
        string(REPLACE "_" "-" OPTION ${OPTION})
        string(REPLACE "meson-" "" OPTION ${OPTION})
        list(APPEND MESON_OPTIONS -D ${OPTION}=${${VAR}})
    endif()
endforeach()

# preamble
set(PATH_SEP ":")
if(WIN32)
    set(PATH_SEP ";")
endif()
macro(adjust_path PATH_LIST)
    string(REPLACE ";" "${PATH_SEP}" ${PATH_LIST} "${${PATH_LIST}}")
endmacro()
macro(get_property_list VAR PROP)
    get_directory_property(${VAR} ${PROP})
    string(REPLACE ";" " " ${VAR} "${${VAR}}")
endmacro()
function(exec)
    execute_process(${ARGN} RESULT_VARIABLE RESULT)
    if(NOT RESULT EQUAL 0)
        message(FATAL_ERROR "Process failed: ${ARGN}")
    endif()
endfunction()
macro(preamble PREFIX)
    # TODO: Adjust paths based on cross-compiling
    set(${PREFIX}_PATH ${CMAKE_PREFIX_PATH} ${CMAKE_SYSTEM_PREFIX_PATH})
    set(${PREFIX}_SYSTEM_PATH)
    foreach(P ${PREFIX}_PATH)
        list(APPEND ${PREFIX}_SYSTEM_PATH ${P}/bin)
    endforeach()
    adjust_path(${PREFIX}_SYSTEM_PATH)

    set(${PREFIX}_PKG_CONFIG_PATH)
    foreach(P ${PREFIX}_PATH)
        foreach(SUFFIX lib lib64 share)
            list(APPEND ${PREFIX}_PKG_CONFIG_PATH ${P}/${SUFFIX}/pkgconfig)
        endforeach()
    endforeach()
    adjust_path(${PREFIX}_PKG_CONFIG_PATH)

    get_property_list(${PREFIX}_COMPILE_FLAGS COMPILE_OPTIONS)
    get_directory_property(${PREFIX}_INCLUDE_DIRECTORIES INCLUDE_DIRECTORIES)
    foreach(DIR ${${PREFIX}_INCLUDE_DIRECTORIES})
        if(MSVC)
            string(APPEND ${PREFIX}_COMPILE_FLAGS " /I ${DIR}")
        else()
            string(APPEND ${PREFIX}_COMPILE_FLAGS " -isystem ${DIR}")
        endif()
    endforeach()
    get_directory_property(${PREFIX}_COMPILE_DEFINITIONS COMPILE_DEFINITIONS)
    foreach(DEF ${${PREFIX}_COMPILE_DEFINITIONS})
        if(MSVC)
            string(APPEND ${PREFIX}_COMPILE_FLAGS " /D ${DEF}")
        else()
            string(APPEND ${PREFIX}_COMPILE_FLAGS " -D${DEF}")
        endif()
    endforeach()

    set(${PREFIX}_LINK "static")
    if(BUILD_SHARED_LIBS)
        set(${PREFIX}_LINK "shared")
    endif()

    set(${PREFIX}_PIC_FLAG)
    if(CMAKE_POSITION_INDEPENDENT_CODE AND NOT WIN32)
        set(${PREFIX}_PIC_FLAG "-fPIC")
    endif()
    get_property_list(${PREFIX}_LINK_FLAGS LINK_FLAGS)
    if(BUILD_SHARED_LIBS)
        string(APPEND ${PREFIX}_LINK_FLAGS " ${CMAKE_SHARED_LINKER_FLAGS}")
    else()
        string(APPEND ${PREFIX}_LINK_FLAGS " ${CMAKE_STATIC_LINKER_FLAGS}")
    endif()
    get_property_list(${PREFIX}_LINK_FLAGS LINK_FLAGS)
    # TODO: Link libraries

    set(${PREFIX}_C_FLAGS "${CMAKE_C_FLAGS} ${${PREFIX}_COMPILE_FLAGS} ${${PREFIX}_PIC_FLAG}")
    set(${PREFIX}_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${${PREFIX}_COMPILE_FLAGS} ${${PREFIX}_PIC_FLAG}")

    # Compensate for extra spaces in the flags, which can cause build failures
    foreach(VAR ${PREFIX}_C_FLAGS ${PREFIX}_CXX_FLAGS ${PREFIX}_LINK_FLAGS)
        string(REGEX REPLACE "  +" " " ${VAR} "${${VAR}}")
        string(STRIP "${${VAR}}" ${VAR})
    endforeach()

    # TODO: Check against the DEBUG_CONFIGURATIONS property
    string(TOLOWER "${CMAKE_BUILD_TYPE}" BUILD_TYPE)
    if(BUILD_TYPE STREQUAL "debug")
        set(${PREFIX}_VARIANT "debug")
    else()
        set(${PREFIX}_VARIANT "release")
    endif()

    # TODO: Adjust pkgconfig path based on cross-compiling
    set(${PREFIX}_ENV_COMMAND ${CMAKE_COMMAND} -E env
        "CC=${CMAKE_C_COMPILER}"
        "CXX=${CMAKE_CXX_COMPILER}"
        "CFLAGS=${${PREFIX}_C_FLAGS}"
        "CXXFLAGS=${${PREFIX}_CXX_FLAGS}"
        "LDFLAGS=${${PREFIX}_LINK_FLAGS}"
        "PATH=${${PREFIX}_SYSTEM_PATH}${PATH_SEP}$ENV{PATH}"
        "PKG_CONFIG_PATH=${${PREFIX}_PKG_CONFIG_PATH}") 
endmacro()
# preamble

preamble(MESON)

set(BUILD_DIR ${CMAKE_CURRENT_BINARY_DIR}/build)
file(MAKE_DIRECTORY ${BUILD_DIR})

set(MESON_CMD ${MESON_EXE} 
    ${CMAKE_CURRENT_SOURCE_DIR} 
    ${BUILD_DIR} 
    --prefix=${CMAKE_INSTALL_PREFIX}
    --buildtype=${MESON_VARIANT}
    --default-library=${MESON_LINK}
    ${MESON_OPTIONS})

string(REPLACE ";" " " MESON_COMMENT "${MESON_CMD}")

message("${MESON_COMMENT}")
exec(COMMAND ${MESON_ENV_COMMAND} ${MESON_CMD})

add_custom_target(meson ALL
    COMMAND ${NINJA_EXE}
    COMMENT "${NINJA_EXE}"
    VERBATIM
    WORKING_DIRECTORY ${BUILD_DIR}
)

add_custom_target(meson_install
    COMMAND ${NINJA_EXE} install
    install
    COMMENT "${NINJA_EXE} install"
    VERBATIM
    WORKING_DIRECTORY ${BUILD_DIR}
)

install(CODE "
execute_process(
    COMMAND ${CMAKE_COMMAND} --build . --target meson_install
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
)
")
