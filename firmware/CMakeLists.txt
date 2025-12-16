# Add support for building in conda environment
if (DEFINED ENV{CONDA_PREFIX})
   set(CMAKE_PREFIX_PATH "$ENV{CONDA_PREFIX}")
   link_directories($ENV{CONDA_PREFIX}/lib)
endif()

# Check cmake version
cmake_minimum_required(VERSION 3.15)
include(InstallRequiredSystemLibraries)

# Project name, Replace with your name
project (PosFit)

# C/C++
enable_language(CXX)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++0x -Wno-deprecated")
add_definitions(-D__STDC_FORMAT_MACROS)

SET(CMAKE_CXX_STANDARD 14)
SET(CMAKE_SKIP_BUILD_RPATH TRUE)
SET(CMAKE_BUILD_WITH_INSTALL_RPATH FALSE)
SET(CMAKE_INSTALL_RPATH_USE_LINK_PATH FALSE)

#####################################
# Find Rogue & Support Libraries
#####################################
if (DEFINED ENV{ROGUE_DIR})
   set(Rogue_DIR $ENV{ROGUE_DIR}/lib)
else()
   set(Rogue_DIR ${CMAKE_PREFIX_PATH}/lib)
endif()
find_package(Rogue)

# GSL used for fitting routines
find_package(GSL)

#####################################
# Setup build
#####################################

# Include files
include_directories(${ROGUE_INCLUDE_DIRS})

# Create rogue python library, point to your source file
add_library(PosFit SHARED src/PosFit.cpp src/PosFit.h src/bobyqa/bobyqa.cc src/bobyqa/bobyqa.h)

# Set output to TOP/lib, remove lib prefix
set_target_properties(PosFit PROPERTIES LIBRARY_OUTPUT_DIRECTORY ${PROJECT_SOURCE_DIR}/python/kek_bpm_rfsoc_stripline/)
set_target_properties(PosFit PROPERTIES PREFIX "")

message(ROGUE_LIBRARIES="${ROGUE_LIBRARIES}")
message(PROJECT_SOURCE_DIR="${PROJECT_SOURCE_DIR}")

# Link to rogue core
TARGET_LINK_LIBRARIES(PosFit ${ROGUE_LIBRARIES} PRIVATE GSL::gsl)
