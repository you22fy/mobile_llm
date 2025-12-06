cmake_minimum_required(VERSION 3.14)

# llama.cppをサブディレクトリとして追加
# 注意: llama.cppは事前にビルドされている必要があります
# または、add_subdirectoryを使って直接ビルドすることもできます
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "Build common utils" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "Build examples" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "Build tools" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "Build tests" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "Build server" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build shared libraries" FORCE)

# llama.cppをサブディレクトリとして追加
add_subdirectory(../../../llama.cpp llama_cpp_build)

# llama_bridge.cppをビルド対象に追加
add_library(native_add
              SHARED
              ../../ios/Classes/native_add.cpp
              ../../ios/Classes/llama_bridge.cpp)

# llama.cppのインクルードディレクトリを追加
target_include_directories(native_add PRIVATE
    ../../../llama.cpp/include
    ../../ios/Classes
)

# llamaライブラリをリンク
target_link_libraries(native_add PRIVATE llama)
