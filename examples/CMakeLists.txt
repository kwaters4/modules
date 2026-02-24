cmake_minimum_required(VERSION 3.20)

project(Foo
  VERSION      1.0.0
  DESCRIPTION  "Example Foo Library"
  LANGUAGES    C
)

# ── Standard install layout ──────────────────────────────────────────────────
include(GNUInstallDirs)
# Defines:
#   CMAKE_INSTALL_BINDIR     → bin
#   CMAKE_INSTALL_LIBDIR     → lib / lib64 (platform-dependent)
#   CMAKE_INSTALL_INCLUDEDIR → include

# ── RPATH policy (for the installed binaries / shared lib) ───────────────────
set(CMAKE_SKIP_RPATH                  OFF)
set(CMAKE_BUILD_WITH_INSTALL_RPATH    OFF)
set(CMAKE_INSTALL_RPATH               "$ORIGIN/../${CMAKE_INSTALL_LIBDIR}")
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH ON)

# ── Optional dependency example ──────────────────────────────────────────────
find_package(ZLIB QUIET)

# ── Binaries targets ─────────────────────────────────────────────────────────

add_executable(main src/hello.c)
install(TARGETS main
  RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# ── Library targets ──────────────────────────────────────────────────────────
add_library(foo_shared SHARED lib/foo.c)
add_library(foo_static STATIC lib/foo.c)

# Give the static lib the same base name (libfoo.a) without clashing
set_target_properties(foo_static PROPERTIES OUTPUT_NAME foo)

# Shared lib versioning  →  libfoo.so  →  libfoo.so.1  →  libfoo.so.1.0.0
set_target_properties(foo_shared PROPERTIES
  OUTPUT_NAME   foo
  VERSION       ${PROJECT_VERSION}
  SOVERSION     ${PROJECT_VERSION_MAJOR}
)

# Create the canonical namespaced aliases so in-tree consumers can use the
# same Foo::foo syntax they would use after installation.
add_library(Foo::foo        ALIAS foo_shared)
add_library(Foo::foo_static ALIAS foo_static)

# ── Include directories ───────────────────────────────────────────────────────
# BUILD_INTERFACE  = path used when building this project (or consuming it
#                   via add_subdirectory / FetchContent)
# INSTALL_INTERFACE = path recorded in the exported targets for external
#                   consumers after installation
foreach(tgt foo_shared foo_static)
  target_include_directories(${tgt}
    PUBLIC
      $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
      $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
  )
  target_compile_features(${tgt} PUBLIC cxx_std_17)

  if(ZLIB_FOUND)
    target_link_libraries(${tgt} PUBLIC ZLIB::ZLIB)
  endif()
endforeach()

# ── Install the library binaries and headers ──────────────────────────────────
install(TARGETS foo_shared foo_static
  EXPORT FooTargets                          # collect into an export set
  LIBRARY  DESTINATION ${CMAKE_INSTALL_LIBDIR}
  ARCHIVE  DESTINATION ${CMAKE_INSTALL_LIBDIR}
  RUNTIME  DESTINATION ${CMAKE_INSTALL_BINDIR} 
  INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

install(DIRECTORY include/
  DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

# ── Generate and install FooTargets.cmake ─────────────────────────────────────
# This file records IMPORTED_LOCATION, INTERFACE_INCLUDE_DIRECTORIES, etc.
# for each target in the FooTargets export set.
install(EXPORT FooTargets
  FILE        FooTargets.cmake
  NAMESPACE   Foo::
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/Foo
)

# ── Generate FooConfig.cmake and FooConfigVersion.cmake ──────────────────────
include(CMakePackageConfigHelpers)

# FooConfig.cmake — relocatable, expands @PACKAGE_INIT@ and @PACKAGE_*@ macros
configure_package_config_file(
  cmake/FooConfig.cmake.in                   # our template
  ${CMAKE_CURRENT_BINARY_DIR}/FooConfig.cmake
  INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/Foo

  # PATH_VARS causes configure_package_config_file to create
  # set_and_check()-validated PACKAGE_* variables in the output file,
  # usable in the .in template as @PACKAGE_CMAKE_INSTALL_INCLUDEDIR@ etc.
  PATH_VARS
    CMAKE_INSTALL_INCLUDEDIR
    CMAKE_INSTALL_LIBDIR
)

# FooConfigVersion.cmake — version compatibility check
write_basic_package_version_file(
  ${CMAKE_CURRENT_BINARY_DIR}/FooConfigVersion.cmake
  VERSION       ${PROJECT_VERSION}
  # SameMajorVersion: 1.x.x is compatible with 1.0.0 request
  # AnyNewerVersion: any version >= requested is compatible
  # ExactVersion:    must match exactly
  COMPATIBILITY SameMajorVersion
)

install(FILES
  ${CMAKE_CURRENT_BINARY_DIR}/FooConfig.cmake
  ${CMAKE_CURRENT_BINARY_DIR}/FooConfigVersion.cmake
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/Foo
)

# ── Generate foo.pc ───────────────────────────────────────────────────────────
# Build up transitive private libs string for static linking consumers
set(FOO_PC_PRIVATE_LIBS "")
set(FOO_PC_REQUIRES     "")
if(ZLIB_FOUND)
  # If zlib has a .pc file, use Requires.private instead of Libs.private
  # so pkg-config can resolve flags itself.
  set(FOO_PC_REQUIRES "zlib")
endif()

# configure_file replaces @VAR@ (and ${VAR} if not using @ONLY)
# @ONLY is recommended — avoids accidentally expanding CMake variables
# that happen to share a name with something in the .pc template.
configure_file(
  config/foo.pc.in
  ${CMAKE_CURRENT_BINARY_DIR}/foo.pc
  @ONLY
)

install(FILES ${CMAKE_CURRENT_BINARY_DIR}/foo.pc
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig
)

# ── Generate the Tcl module file ─────────────────────────────────────────────
configure_file(
    config/foo.module.in
    ${CMAKE_CURRENT_BINARY_DIR}/modulefiles/foo/${PROJECT_VERSION}
    @ONLY
)

# Install destination is configurable — sites vary on where modulefiles live
set(MODULEFILE_INSTALL_DIR
  "${MODULE_PREFIX}"
    CACHE PATH "Directory to install the Tcl module file into")

install(
    FILES ${CMAKE_CURRENT_BINARY_DIR}/modulefiles/foo/${PROJECT_VERSION}
    DESTINATION ${MODULEFILE_INSTALL_DIR}
)
