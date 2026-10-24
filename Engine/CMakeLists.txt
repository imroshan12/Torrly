cmake_minimum_required(VERSION 3.25)
project(TorrlyEngine LANGUAGES C CXX OBJC OBJCXX)

# libtorrent is built from Vendor/src/libtorrent (scripts/build-engine.sh clones it).
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../Vendor/src/libtorrent libtorrent EXCLUDE_FROM_ALL)

add_library(TorrlyEngine STATIC
    src/TLSession.mm
    src/TLModels.mm
)
target_include_directories(TorrlyEngine PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(TorrlyEngine PRIVATE torrent-rasterbar)
set_target_properties(TorrlyEngine PROPERTIES
    CXX_STANDARD 17
    OBJCXX_STANDARD 17
)
target_compile_options(TorrlyEngine PRIVATE -fobjc-arc)
