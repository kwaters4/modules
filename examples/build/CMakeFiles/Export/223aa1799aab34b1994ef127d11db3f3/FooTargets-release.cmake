#----------------------------------------------------------------
# Generated CMake target import file for configuration "Release".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "Foo::foo_shared" for configuration "Release"
set_property(TARGET Foo::foo_shared APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)
set_target_properties(Foo::foo_shared PROPERTIES
  IMPORTED_LOCATION_RELEASE "${_IMPORT_PREFIX}/lib64/libfoo.so.1.0.0"
  IMPORTED_SONAME_RELEASE "libfoo.so.1"
  )

list(APPEND _cmake_import_check_targets Foo::foo_shared )
list(APPEND _cmake_import_check_files_for_Foo::foo_shared "${_IMPORT_PREFIX}/lib64/libfoo.so.1.0.0" )

# Import target "Foo::foo_static" for configuration "Release"
set_property(TARGET Foo::foo_static APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)
set_target_properties(Foo::foo_static PROPERTIES
  IMPORTED_LINK_INTERFACE_LANGUAGES_RELEASE "C"
  IMPORTED_LOCATION_RELEASE "${_IMPORT_PREFIX}/lib64/libfoo.a"
  )

list(APPEND _cmake_import_check_targets Foo::foo_static )
list(APPEND _cmake_import_check_files_for_Foo::foo_static "${_IMPORT_PREFIX}/lib64/libfoo.a" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
