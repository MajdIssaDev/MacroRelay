cmake_minimum_required(VERSION 3.14)
project(macro_relay_native LANGUAGES CXX)

add_library(macro_relay_native SHARED
  src/macro_relay.cpp
)

target_include_directories(macro_relay_native PUBLIC include)
target_compile_definitions(macro_relay_native PRIVATE MACRO_RELAY_EXPORTS UNICODE _UNICODE)
target_compile_features(macro_relay_native PUBLIC cxx_std_17)
target_link_libraries(macro_relay_native PRIVATE user32 advapi32)
set_target_properties(macro_relay_native PROPERTIES
  OUTPUT_NAME "macro_relay_native"
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)
