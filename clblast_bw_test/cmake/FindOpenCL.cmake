# ==================================================================================================
# This file is part of the CLBlast project. The project is licensed under Apache Version 2.0. This
# project loosely follows the Google C++ styleguide and uses a tab-size of two spaces and a max-
# width of 100 characters per line.
#
# Author(s):
#   Cedric Nugteren <www.cedricnugteren.nl>
#
# ==================================================================================================
#
# Defines the following variables:
#   OPENCL_FOUND          Boolean holding whether or not the OpenCL library was found
#   OPENCL_INCLUDE_DIRS   The OpenCL include directory
#   OPENCL_LIBRARIES      The OpenCL library
#
# In case OpenCL is not installed in the default directory, set the OPENCL_ROOT variable to point to
# the root of OpenCL, such that 'OpenCL/cl.h' or 'CL/cl.h' can be found in $OPENCL_ROOT/include.
# This can either be done using an environmental variable (e.g. export OPENCL_ROOT=/path/to/opencl)
# or using a CMake variable (e.g. cmake -DOPENCL_ROOT=/path/to/opencl ..).
#
# ==================================================================================================

# Sets the possible install locations
set(OPENCL_HINTS
  ${OPENCL_ROOT}
  $ENV{OPENCL_ROOT}
  $ENV{OCL_ROOT}
  $ENV{AMDAPPSDKROOT}
  $ENV{CUDA_PATH}
  $ENV{INTELOCLSDKROOT}
  $ENV{NVSDKCOMPUTE_ROOT}
  $ENV{ATISTREAMSDKROOT}
)
set(OPENCL_PATHS
  /usr/local/cuda
  /opt/cuda
  /opt/intel/opencl
  /usr
  /usr/local
  /opt/rocm/opencl
)

# Finds the include directories (only if not already set via -D)
if(NOT OPENCL_INCLUDE_DIRS)
  find_path(OPENCL_INCLUDE_DIRS
    NAMES OpenCL/cl.h CL/cl.h
    HINTS ${OPENCL_HINTS}
    PATH_SUFFIXES include OpenCL/common/inc inc include/x86_64 include/x64
    PATHS ${OPENCL_PATHS}
    DOC "OpenCL include header OpenCL/cl.h or CL/cl.h"
  )
endif()
mark_as_advanced(OPENCL_INCLUDE_DIRS)

# Finds the library (only if not already set via -D)
if(NOT OPENCL_LIBRARIES)
  find_library(OPENCL_LIBRARIES
    NAMES OpenCL
    HINTS ${OPENCL_HINTS}
    PATH_SUFFIXES lib lib64 lib/x86_64 lib/x86_64/sdk lib/x64 lib/x86 lib/Win32 OpenCL/common/lib/x64
    PATHS ${OPENCL_PATHS}
    DOC "OpenCL library"
  )
endif()
mark_as_advanced(OPENCL_LIBRARIES)

# ==================================================================================================

# Notification messages
if(NOT OPENCL_INCLUDE_DIRS)
    message(STATUS "Could NOT find 'OpenCL/cl.h' or 'CL/cl.h', install OpenCL or set OPENCL_ROOT")
endif()
if(NOT OPENCL_LIBRARIES)
    message(STATUS "Could NOT find OpenCL library, install it or set OPENCL_ROOT")
endif()

# Determines whether or not OpenCL was found
include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(OpenCL DEFAULT_MSG OPENCL_INCLUDE_DIRS OPENCL_LIBRARIES)

# Create imported target OpenCL::OpenCL if found
if(OpenCL_FOUND AND NOT TARGET OpenCL::OpenCL)
  add_library(OpenCL::OpenCL SHARED IMPORTED)
  set_target_properties(OpenCL::OpenCL PROPERTIES
    IMPORTED_LOCATION "${OPENCL_LIBRARIES}"
  )
  
  # Set include directories - use generator expression to avoid validation error if path doesn't exist yet
  # This allows paths that will exist at build time (e.g., in Android NDK builds)
  if(OPENCL_INCLUDE_DIRS)
    # Check if directory exists, if not use $<BUILD_INTERFACE:> to defer validation
    if(EXISTS "${OPENCL_INCLUDE_DIRS}")
      set_target_properties(OpenCL::OpenCL PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${OPENCL_INCLUDE_DIRS}"
      )
    else()
      # Use generator expression to avoid immediate validation
      # Note: This is a workaround for paths that don't exist at configure time
      set_target_properties(OpenCL::OpenCL PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "$<BUILD_INTERFACE:${OPENCL_INCLUDE_DIRS}>"
      )
      message(STATUS "OpenCL include directory '${OPENCL_INCLUDE_DIRS}' does not exist at configure time - will be validated at build time")
    endif()
  endif()
endif()

# ==================================================================================================