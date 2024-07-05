include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(TProject_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(TProject_setup_options)
  option(TProject_ENABLE_HARDENING "Enable hardening" ON)
  option(TProject_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    TProject_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    TProject_ENABLE_HARDENING
    OFF)

  TProject_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR TProject_PACKAGING_MAINTAINER_MODE)
    option(TProject_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(TProject_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(TProject_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(TProject_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(TProject_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(TProject_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(TProject_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(TProject_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(TProject_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(TProject_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(TProject_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(TProject_ENABLE_PCH "Enable precompiled headers" OFF)
    option(TProject_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(TProject_ENABLE_IPO "Enable IPO/LTO" ON)
    option(TProject_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(TProject_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(TProject_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(TProject_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(TProject_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(TProject_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(TProject_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(TProject_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(TProject_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(TProject_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(TProject_ENABLE_PCH "Enable precompiled headers" OFF)
    option(TProject_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      TProject_ENABLE_IPO
      TProject_WARNINGS_AS_ERRORS
      TProject_ENABLE_USER_LINKER
      TProject_ENABLE_SANITIZER_ADDRESS
      TProject_ENABLE_SANITIZER_LEAK
      TProject_ENABLE_SANITIZER_UNDEFINED
      TProject_ENABLE_SANITIZER_THREAD
      TProject_ENABLE_SANITIZER_MEMORY
      TProject_ENABLE_UNITY_BUILD
      TProject_ENABLE_CLANG_TIDY
      TProject_ENABLE_CPPCHECK
      TProject_ENABLE_COVERAGE
      TProject_ENABLE_PCH
      TProject_ENABLE_CACHE)
  endif()

  TProject_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (TProject_ENABLE_SANITIZER_ADDRESS OR TProject_ENABLE_SANITIZER_THREAD OR TProject_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(TProject_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(TProject_global_options)
  if(TProject_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    TProject_enable_ipo()
  endif()

  TProject_supports_sanitizers()

  if(TProject_ENABLE_HARDENING AND TProject_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR TProject_ENABLE_SANITIZER_UNDEFINED
       OR TProject_ENABLE_SANITIZER_ADDRESS
       OR TProject_ENABLE_SANITIZER_THREAD
       OR TProject_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${TProject_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${TProject_ENABLE_SANITIZER_UNDEFINED}")
    TProject_enable_hardening(TProject_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(TProject_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(TProject_warnings INTERFACE)
  add_library(TProject_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  TProject_set_project_warnings(
    TProject_warnings
    ${TProject_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(TProject_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    TProject_configure_linker(TProject_options)
  endif()

  include(cmake/Sanitizers.cmake)
  TProject_enable_sanitizers(
    TProject_options
    ${TProject_ENABLE_SANITIZER_ADDRESS}
    ${TProject_ENABLE_SANITIZER_LEAK}
    ${TProject_ENABLE_SANITIZER_UNDEFINED}
    ${TProject_ENABLE_SANITIZER_THREAD}
    ${TProject_ENABLE_SANITIZER_MEMORY})

  set_target_properties(TProject_options PROPERTIES UNITY_BUILD ${TProject_ENABLE_UNITY_BUILD})

  if(TProject_ENABLE_PCH)
    target_precompile_headers(
      TProject_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(TProject_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    TProject_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(TProject_ENABLE_CLANG_TIDY)
    TProject_enable_clang_tidy(TProject_options ${TProject_WARNINGS_AS_ERRORS})
  endif()

  if(TProject_ENABLE_CPPCHECK)
    TProject_enable_cppcheck(${TProject_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(TProject_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    TProject_enable_coverage(TProject_options)
  endif()

  if(TProject_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(TProject_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(TProject_ENABLE_HARDENING AND NOT TProject_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR TProject_ENABLE_SANITIZER_UNDEFINED
       OR TProject_ENABLE_SANITIZER_ADDRESS
       OR TProject_ENABLE_SANITIZER_THREAD
       OR TProject_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    TProject_enable_hardening(TProject_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
