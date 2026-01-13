cmake_minimum_required(VERSION 3.20)

project(clblast_bw_test)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Set cmake module paths
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

find_package(OpenCL REQUIRED)

add_executable(clblast_bw_test main.cc)

target_include_directories(clblast_bw_test PRIVATE 
  ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(clblast_bw_test PRIVATE OpenCL::OpenCL)