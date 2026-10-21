cmake_minimum_required(VERSION 3.14)
project(magic_pointer_native C)
set(CMAKE_C_STANDARD 99)

if(NOT EZINJECT_SOURCE_DIR OR NOT EZINJECT_BUILD_DIR)
    message(FATAL_ERROR "Set EZINJECT_SOURCE_DIR and EZINJECT_BUILD_DIR")
endif()

# Use the CRT objects from the exact same build as the injector. The PHP
# library ships an older CRT and must not receive the modern bearing struct.
file(GLOB CRT_OBJECTS
    "${EZINJECT_BUILD_DIR}/CMakeFiles/ezinject_crt.dir/*.o"
    "${EZINJECT_BUILD_DIR}/CMakeFiles/ezinject_crt.dir/crt/*.o")
if(NOT CRT_OBJECTS)
    message(FATAL_ERROR "Build the ezinject_crt target first")
endif()
add_library(phpbridge SHARED phpbridge.c ${CRT_OBJECTS})
target_include_directories(phpbridge PRIVATE
    "${EZINJECT_SOURCE_DIR}" "${EZINJECT_BUILD_DIR}")
target_compile_definitions(phpbridge PRIVATE _GNU_SOURCE)
target_compile_options(phpbridge PRIVATE -marm -Wall -Wextra)
target_link_options(phpbridge PRIVATE "LINKER:--no-undefined")
target_link_libraries(phpbridge PRIVATE dl pthread)

foreach(MODE arm thumb)
    add_executable(pointer-test-${MODE} test-target.c)
    target_compile_options(pointer-test-${MODE} PRIVATE -O0 -m${MODE})
    target_link_options(pointer-test-${MODE} PRIVATE "LINKER:--export-dynamic")
endforeach()
