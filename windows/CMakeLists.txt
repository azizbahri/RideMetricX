cmake_minimum_required(VERSION 3.14)
project(ride_metric_x LANGUAGES CXX)

set(BINARY_NAME "ride_metric_x")

cmake_policy(SET CMP0063 NEW)

set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}/run" CACHE PATH "..." FORCE)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/run")
else()
  set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/${BINARY_NAME}")
endif()

# Configure cmake to find Visual C++ compiler and Windows SDK.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED YES)
set(CMAKE_CXX_EXTENSIONS NO)

add_definitions(-DUNICODE -D_UNICODE)

include(flutter/generated_plugins.cmake)

# Application build
add_subdirectory("runner")

# Generated plugin build rules, which manage building the plugins and installing
# them alongside the app.
apply_standard_settings(${BINARY_NAME})
