cmake_minimum_required(VERSION 3.10)

project(AoE2DESpecChat_Server VERSION 0.1)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED True)
set(CMAKE_BUILD_TYPE Debug)

add_executable(AoE2DESpecChat_Server main.cpp)

set_target_properties(AoE2DESpecChat_Server PROPERTIES OUTPUT_NAME "server")

target_link_libraries(AoE2DESpecChat_Server -pthread)
target_link_libraries(AoE2DESpecChat_Server -latomic)
