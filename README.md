# Linux Environment Variables & Modules

**The overarching principle:** the more a build variable is scoped (target-level > tool-level > global), the more reproducible and portable your builds will be. `PKG_CONFIG_PATH` and `CMAKE_PREFIX_PATH` operate at the tool level; CMake imported targets bring everything down to the target level which is where it belongs.

## Table of Contents

* [Overview](#overview)
* [Environmental Variables](#environmental-variables)
* [Best Practices for Environment Modules](#best-practices-for-environment-modules)
* [Accessing Module Libraries with CMake](#accessing-module-libraries-with-cmake)
* [Accessing Module Libraries with Make](#accessing-module-libraries-with-make)
* [Accessing Module Libraries with Autotools](#accessing-module-libraries-with-autotools)
* [Debugging Path Problems](#debugging-path-problems)
* [Summary of Recommendations](#summary-of-recommendations)

### A Developer & HPC Reference Guide

>**Variables covered:** `PATH` · `CPATH` · `C_INCLUDE_PATH` · `CPLUS_INCLUDE_PATH` · `LIBRARY_PATH` · `LD_RUN_PATH` · `LD_LIBRARY_PATH` · `PKG_CONFIG_PATH` · `CMAKE_PREFIX_PATH`\
>**Tools covered:** `Modules` · `CMake` · `Make` · `pkg-config` · `auto-tools`

## Overview

Linux uses a set of environment variables to tell compilers, linkers, and the dynamic loader where to find executables, header files, and libraries. These variables operate at different stages of the software lifecycle. Confusing them and/or setting them carelessly may lead to builds that work on one machine and fail on another.

```
Source Code (i.e. foo.c)
    │
    ▼
Compiler (gcc/clang)       ← PATH (finds the compiler executable itself)
    │                         CPATH, C_INCLUDE_PATH, CPLUS_INCLUDE_PATH
    │  (finds headers)
    ▼
Linker (ld)                ← LIBRARY_PATH, LD_RUN_PATH
    │  (finds .so/.a, optionally embeds RPATH/RUNPATH into binary)
    ▼
Compiled binary is on disk
    │
    ▼
Dynamic Linker (ld.so)     ← LD_LIBRARY_PATH, embedded RPATH/RUNPATH
    │  (loads shared libraries at runtime)
    ▼
Running Process
```

## Environmental Variables

| Variable | Used by | Stage | Effect | Persists in binary? |
| --- | --- | --- | --- | --- |
| `PATH` | Shell | Command resolution | Finds compiler & tool executables | No |
| `CPATH` | Compiler | Compile time | Finds headers (`-I`) | No |
| `C_INCLUDE_PATH` | C compiler | Compile time | Finds C headers | No |
| `CPLUS_INCLUDE_PATH` | C++ compiler | Compile time | Finds C++ headers | No |
| `LIBRARY_PATH` | Linker (`ld`) | Link time | Finds `.so`/`.a` to link (`-L`) | No |
| `LD_RUN_PATH` | Linker (`ld`) | Link time | **Embeds RPATH into binary** | **YES**(Danger) |
| `LD_LIBRARY_PATH` | Dynamic linker | Runtime | Finds `.so` to load | No |
| `PKG_CONFIG_PATH` | `pkg-config` | Build tool | Finds `.pc` files | No |
| `CMAKE_PREFIX_PATH` | CMake | Configure time | Finds `*Config.cmake` | No |

### Variable Descriptions

#### `PATH`

The shell searches each directory in `PATH` left-to-right when you type a command. It has **no effect on headers or libraries** — only on finding executables. The linker (`ld`) is invoked by the compiler driver internally and does **not** use `PATH`.

```bash
export PATH=/opt/gcc/13/bin:$PATH

which gcc          # /opt/gcc/13/bin/gcc
cmake --version    # found via PATH
```

- Always prepend `bin/` so newer tool versions shadow system defaults.
- Putting a library's `lib/` in `PATH` is harmless but does nothing for compilation or linking.
- `PATH` does influence which alternative linker is picked up if you use `-fuse-ld=lld` or `-fuse-ld=gold`, since the compiler driver searches `PATH` for those wrappers. But the default `ld` is resolved at GCC/Clang build time, not through `PATH`.

---

#### `CPATH`, `C_INCLUDE_PATH`, `CPLUS_INCLUDE_PATH`

`CPATH` is a colon-separated list of directories the compiler searches for header files. It is equivalent to adding `-I` flags, but applies **globally to every compiler invocation in the session**, regardless of whether the code being compiled uses that library.

```bash
export CPATH=/opt/mylib/include:$CPATH

# Equivalent to:
gcc -I/opt/mylib/include -c main.c
```

**Language-specific variants:**

| Variable | Applies to |
|---|---|
| `CPATH` | C, C++, and Fortran (all languages) |
| `C_INCLUDE_PATH` | C only |
| `CPLUS_INCLUDE_PATH` | C++ only |

**Avoid `CPATH` in module files.**
CPATH is a global, indiscriminate override. When you set it, every compiler invocation in your entire shell session picks up those include paths.
This causes:

- **Version conflicts** — two libraries with a header of the same name (e.g. config.h, version.h) silently shadow each other depending on the order in CPATH
- **Invisible dependencies** — a project compiles successfully only because of an accident of your environment, then breaks on a clean machine or CI
- **Non-reproducible builds** — two developers with different CPATH values get different build results from identical source

Use `PKG_CONFIG_PATH` and `CMAKE_PREFIX_PATH`, their scope include paths to individual build targets, not the entire session.

---

#### `LIBRARY_PATH`

A colon-separated list of directories the linker searches for libraries when building a binary. Equivalent to passing `-L` flags. Once linking is complete, `LIBRARY_PATH` plays **no further role** — it is not consulted at runtime.

```bash
export LIBRARY_PATH=/opt/mylib/lib:$LIBRARY_PATH

# Equivalent to:
gcc main.o -L/opt/mylib/lib -lmylib -o myapp
```

- `LIBRARY_PATH` and `LD_LIBRARY_PATH` are often set to the same directory, but serve different phases: `LIBRARY_PATH` is for the build, `LD_LIBRARY_PATH` is for the run.
- CMake generates explicit `-L` flags from `target_link_libraries()`. A `LIBRARY_PATH` set in the environment is picked up silently in addition — normally harmless, but can introduce unexpected transitive dependencies.

---

#### `LD_RUN_PATH`

`LD_RUN_PATH` tells the linker to embed the listed directories as an RPATH entry **directly inside the binary being built**. This is the one variable in this list whose effect persists after the build — the paths are tattooed into the ELF binary and consulted by the dynamic linker on every subsequent execution, on every machine the binary runs on.

```bash
export LD_RUN_PATH=/opt/mylib/lib

gcc main.o -lmylib -o myapp
# /opt/mylib/lib is now permanently embedded in myapp

# Verify:
readelf -d myapp | grep -E 'RPATH|RUNPATH'
# → (RUNPATH)  Library runpath: [/opt/mylib/lib]
```

**Never set `LD_RUN_PATH` in a module file.** If it is set when you invoke CMake, it bypasses CMake's RPATH management entirely. The result is binaries containing build-host paths that may not exist on other machines.

**TIP**: If a module outside your control sets it, neutralise it in `CMakeLists.txt`:

```cmake
unset(ENV{LD_RUN_PATH})
```

---

#### `LD_LIBRARY_PATH`

Searched by the dynamic linker (`ld.so`) at runtime, **every time a binary executes**. It is re-evaluated fresh on each run, making it easy to override which shared library version gets loaded without relinking.

```bash
export LD_LIBRARY_PATH=/opt/mylib/lib:$LD_LIBRARY_PATH

./myapp    # ld.so finds libmylib.so here at load time
```

**Runtime search order (`ld.so`):**

1. `RPATH` embedded in the binary (if no `RUNPATH` present)
2. `LD_LIBRARY_PATH`
3. `RUNPATH` embedded in the binary
4. `/etc/ld.so.cache` (built from `/etc/ld.so.conf`)
5. Default paths: `/lib`, `/usr/lib`, `/lib64`, `/usr/lib64`

**`LD_LIBRARY_PATH` affects every process in the shell**, including ones unrelated to your library. A stale value can silently swap in the wrong library version. Use it for development and testing; for production, embed correct RPATHs at install time instead.

---

#### `PKG_CONFIG_PATH`

Not a compiler or linker variable — read by the `pkg-config` tool, which build systems (CMake, Autotools, Meson, Make) invoke to discover where a library's headers and link flags live. Libraries install `.pc` files that describe themselves; `pkg-config` emits the correct `-I` and `-l` flags for that library only.

```bash
export PKG_CONFIG_PATH=/opt/mylib/lib/pkgconfig:$PKG_CONFIG_PATH

pkg-config --cflags --libs mylib
# → -I/opt/mylib/include -L/opt/mylib/lib -lmylib
```

> `PKG_CONFIG_PATH` is the preferred alternative to `CPATH` and `LIBRARY_PATH` in module files. Include and link paths are scoped to the requesting library and only injected into targets that explicitly ask for them.

---

#### `CMAKE_PREFIX_PATH`

A CMake-specific variable (also honored as an environment variable) that tells `find_package()` where to search for `FooConfig.cmake` or `FindFoo.cmake` files. Setting it to a library's installation prefix is the cleanest way to make a module-provided library visible to CMake.

```bash
export CMAKE_PREFIX_PATH=/opt/mylib/1.0:$CMAKE_PREFIX_PATH

# CMake searches:
#   /opt/mylib/1.0/lib/cmake/mylib/FooConfig.cmake
#   /opt/mylib/1.0/share/cmake/mylib/FooConfig.cmake
```

- No header or library paths leak globally — everything travels through imported target properties on a per-target basis.
- Works alongside `PKG_CONFIG_PATH`, both can and should be set when possible.

---

## Best Practices for Environment Modules

### What to Set and What to Avoid

| Variable | Recommendation | Reasoning |
|---|---|---|
| `PATH` | Always set | Essential — exposes executables |
| `PKG_CONFIG_PATH` | Always set | Correct scoped mechanism for build discovery |
| `CMAKE_PREFIX_PATH` | Always set | Correct scoped mechanism for CMake discovery |
| `LD_LIBRARY_PATH` | Dev modules only | Fine for interactive use; **remove from production** |
| `LIBRARY_PATH` | Avoid | Only needed when no `.pc` / `Config.cmake` exists |
| `CPATH` | Avoid | Global header injection, may cause shadowing bugs |
| `LD_RUN_PATH` | Never | Permanently embeds build-host paths in binaries |

Additional variables can be set, but should be prefixed with the library name.
For example `FOO_PREFIX` can be used to let the user know where the library is installed.
These are out of scope and do not pollute the standard" Linux environmental variables.

### 3.2 Module Files

This files should be configured along with your library a configure time.
They should provide the paths needed to use the library, version number, contact information, and any details in the `what-is` section.
Lua can be used if the local module version installed supports it. (`$ module --version$` will provide more information)
The newer Lua based module system is backwards compatible and can use TCL modules.

#### TCL Module Template

``` tcl
#%Module1.0
## /opt/modulefiles/mylib/1.0

proc ModulesHelp { } {
    puts stderr "  mylib 1.0.0 — loads headers, libraries, and build system discovery."
    puts stderr "  Uses PKG_CONFIG_PATH and CMAKE_PREFIX_PATH; does not set CPATH or LD_RUN_PATH."
}

module-whatis "Name:        mylib"
module-whatis "Version:     1.0.0"
module-whatis "Description: Example library"

conflict mylib

set root /opt/mylib/1.0

# executables
prepend-path PATH               $root/bin


# build system discovery (the correct approach)
prepend-path PKG_CONFIG_PATH    $root/lib/pkgconfig
prepend-path CMAKE_PREFIX_PATH  $root
```

#### Lmod Module Template

```lua
-- /opt/modulefiles/mylib/1.0.lua

whatis("Name:        mylib")
whatis("Version:     1.0.0")
whatis("Description: Example library")

help([[
  mylib 1.0.0 — loads headers, libraries, and build system discovery.
  Uses PKG_CONFIG_PATH and CMAKE_PREFIX_PATH; does not set CPATH or LD_RUN_PATH.
]])

conflict("mylib")   -- prevent two versions loading simultaneously

local root = "/opt/mylib/1.0"

-- executables
prepend_path("PATH",              pathJoin(root, "bin"))

-- build system discovery (the correct approach)
prepend_path("PKG_CONFIG_PATH",   pathJoin(root, "lib/pkgconfig"))
prepend_path("CMAKE_PREFIX_PATH", root)
```

### Module Loading Workflow

```bash
#!/bin/bash

module purge                         # always start clean
module load gcc/13                   # compiler
module load cmake/3.28               # build system
module load mylib/1.0                # sets PKG_CONFIG_PATH, CMAKE_PREFIX_PATH

module list                          # verify what is loaded

cmake -S . -B build
cmake --build build -j
cmake --install build --prefix /opt/myproject/1.0
```

Purging is best practices when building software, pinning to a version is as well. If noted pinned the default set by the `/opt/modulefiles/mylib/.version` file will automatically be loaded.
This can cause issue in the future when using or maintaining the module. The default version of a dependency may cause breaks in the provided library.

---

## Accessing Module Libraries with CMake

### Via pkg-config (`.pc` files)

Use `find_package(PkgConfig)` and then `pkg_check_modules()`. The `IMPORTED_TARGET` form (CMake 3.6+) is preferred because it wraps all flags in a single target, relieving the need to place `-I` or `-L` anywhere.

```cmake
cmake_minimum_required(VERSION 3.20)
project(MyApp)

find_package(PkgConfig REQUIRED)

# IMPORTED_TARGET creates PkgConfig::mylib with include dirs
# and link flags attached — no CPATH needed anywhere
pkg_check_modules(MYLIB REQUIRED IMPORTED_TARGET mylib)

add_executable(myapp src/main.cpp)

# Single line gives -I, -L, -l, and any compile definitions
target_link_libraries(myapp PRIVATE PkgConfig::MYLIB)
```

Requires `PKG_CONFIG_PATH` to point at the library's `lib/pkgconfig/` — set by the module file.

### Via CMake Config files (`*Config.cmake`)

When a library ships its own `FooConfig.cmake`, use `find_package()` directly. This is the most idiomatic CMake approach and gives the richest target information.

```cmake
cmake_minimum_required(VERSION 3.20)
project(MyApp)

# Requires CMAKE_PREFIX_PATH=/opt/mylib/1.0 (set by module)
find_package(MyLib 1.0 REQUIRED)

add_executable(myapp src/main.cpp)

# MyLib::mylib carries INTERFACE_INCLUDE_DIRECTORIES,
# INTERFACE_LINK_LIBRARIES, INTERFACE_COMPILE_DEFINITIONS
# — everything propagates transitively, no CPATH or LIBRARY_PATH needed
target_link_libraries(myapp PRIVATE MyLib::mylib)
```

### RPATH Management

Never rely on `LD_RUN_PATH` to set RPATH. Use CMake's built-in RPATH variables. The `$ORIGIN` token makes binaries relocatable regardless of install prefix.

```cmake
include(GNUInstallDirs)

# Unsets any LD_RUN_PATH set by a loaded module
unset(ENV{LD_RUN_PATH})

# CMake RPATH policy
set(CMAKE_SKIP_RPATH                  OFF)
set(CMAKE_BUILD_WITH_INSTALL_RPATH    OFF)
set(CMAKE_INSTALL_RPATH               "$ORIGIN/../${CMAKE_INSTALL_LIBDIR}")
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH ON)  # auto-include non-system lib dirs

add_executable(myapp src/main.cpp)
target_link_libraries(myapp PRIVATE MyLib::mylib)

install(TARGETS myapp
  RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
```

Verify after installing:

```bash
readelf -d install/bin/myapp | grep RUNPATH
# → [$ORIGIN/../lib]  — not any /opt/... build-host path
```

---

## Accessing Module Libraries with Make

Plain Makefiles have no built-in package discovery. The standard approach is to call `pkg-config` inside the Makefile, or accept `CFLAGS`/`LDFLAGS` from the environment.

### Using pkg-config in a Makefile

```makefile
CC      = gcc
CFLAGS  = $(shell pkg-config --cflags mylib)
LDFLAGS = $(shell pkg-config --libs   mylib)

myapp: main.o
	$(CC) -o $@ $^ $(LDFLAGS)

main.o: main.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f myapp main.o
```

`PKG_CONFIG_PATH` must be set (by the module) before `make` is invoked. The `pkg-config` call expands to the correct `-I` and `-L` flags scoped to `mylib` only.

### Accepting CFLAGS and LDFLAGS from the Environment

A more portable pattern lets the caller pass flags explicitly:

```makefile
CC      ?= gcc
CFLAGS  += -Wall -O2
LDFLAGS +=

myapp: main.o
	$(CC) -o $@ $^ $(LDFLAGS)

main.o: main.c
	$(CC) $(CFLAGS) -c -o $@ $<
```

```bash
# Caller provides flags via pkg-config
module load mylib/1.0
make CFLAGS="$(pkg-config --cflags mylib)" \
     LDFLAGS="$(pkg-config --libs   mylib)"
```

---

## Accessing Module Libraries with Autotools

Autotools (`configure` / `make` / `make install`) uses M4 macros to detect libraries. The two most common mechanisms are `PKG_CHECK_MODULES` (for libraries with `.pc` files) and `AC_CHECK_LIB` (for libraries without).

### `PKG_CHECK_MODULES` (recommended)

**`configure.ac`:**

```m4
AC_INIT([myapp], [1.0])
AM_INIT_AUTOMAKE
AC_PROG_CC

# Requires m4/pkg.m4 (provided by the pkg-config dev package)
PKG_CHECK_MODULES([MYLIB], [mylib >= 1.0],
  [AC_MSG_NOTICE([mylib found])],
  [AC_MSG_ERROR([mylib not found — load the module first])])

AC_CONFIG_FILES([Makefile])
AC_OUTPUT
```

**`Makefile.am`:**

```makefile
AM_CFLAGS  = $(MYLIB_CFLAGS)   # expands to -I/opt/mylib/include
AM_LDFLAGS = $(MYLIB_LIBS)     # expands to -L/opt/mylib/lib -lmylib

bin_PROGRAMS = myapp
myapp_SOURCES = main.c
```

**Build workflow:**

```bash
module load mylib/1.0      # sets PKG_CONFIG_PATH

autoreconf -fi             # regenerate configure script
./configure --prefix=/opt/myapp/1.0
make -j
make install
```

### `AC_CHECK_LIB` (fallback when no `.pc` file exists)

When a library does not ship a `.pc` file, Autotools probes for it directly. The module must set `CPATH` and `LIBRARY_PATH` in this case — the one legitimate use for those variables.

**`configure.ac`:**

```m4
AC_CHECK_HEADERS([mylib/mylib.h], [],
  [AC_MSG_ERROR([mylib header not found])])

AC_CHECK_LIB([mylib], [mylib_init], [],
  [AC_MSG_ERROR([libmylib not found])])
```

**Module fallback (only when no `.pc` file exists):**

```lua
-- In the .lua modulefile — fallback only, prefer .pc files
prepend_path("CPATH",        pathJoin(root, "include"))
prepend_path("LIBRARY_PATH", pathJoin(root, "lib"))
```

> `CPATH` and `LIBRARY_PATH` are acceptable here precisely because `AC_CHECK_LIB` has no other discovery mechanism. This is the one scenario where setting them in a module is justified. The correct long-term fix is to ship a `.pc` file with the library.

---

## Debugging Path Problems

### Inspecting the Current Environment

```bash
# Print all relevant variables (`$ printenv PATH` would work here as well)
echo $PATH
echo $CPATH
echo $LIBRARY_PATH
echo $LD_RUN_PATH
echo $LD_LIBRARY_PATH
echo $PKG_CONFIG_PATH
echo $CMAKE_PREFIX_PATH

# Pretty-print any colon-separated path
echo $PKG_CONFIG_PATH | tr ':' '\n'

# Check for LD_RUN_PATH contamination
env | grep LD_
```

### Inspecting a Built Binary

```bash
# Show embedded RPATH / RUNPATH
readelf -d mybinary | grep -E 'RPATH|RUNPATH'

# Alternative
objdump -x mybinary | grep -E 'RPATH|RUNPATH'

# Show all shared library dependencies and where they resolve
ldd mybinary
```

### Debugging pkg-config

```bash
# Check if a library is visible
pkg-config --exists mylib && echo found || echo not found

# Print resolved flags
pkg-config --cflags --libs mylib

# Verbose search trace
PKG_CONFIG_DEBUG_SPEW=1 pkg-config --libs mylib

# List all visible packages
pkg-config --list-all
```

**Note**: The newer `pkgconf` and older `pkg-config` have mostly similar behavior.
However, there are some version of `pkg-config` that will not produce the needed `--cflags` for the header if they already exist in the `CPATH`.

### Debugging CMake

```bash
# Print all find_package search paths
cmake -S . -B build --debug-find

# Print compiler and linker commands verbosely
cmake --build build -- VERBOSE=1

# Generate compile_commands.json (useful for IDEs and clangd)
cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
```

## Summary of Recommendations

- **Set `PATH`** in every module to expose executables.
- **Set `PKG_CONFIG_PATH` and `CMAKE_PREFIX_PATH`** — these are the correct, scoped mechanisms for build system package discovery. They are the primary reason `CPATH` and `LIBRARY_PATH` are unnecessary in well-written modules.
- **Set `LD_LIBRARY_PATH`** Do not set this variable globally in a module file. Use it only for development and test modules. Remove it from production or deployment modules and rely on embedded RPATH instead.
- **Avoid `CPATH`** unless the library has no `.pc` file and you are using Autotools' `AC_CHECK_LIB`. It is a global blunt instrument that causes silent header-shadowing bugs.
- **Avoid `LIBRARY_PATH`** for the same reasons as `CPATH`. A `.pc` or `Config.cmake` file makes it unnecessary.
- **Never set `LD_RUN_PATH`**. It permanently embeds build-host paths into binaries. Let CMake manage RPATH via `CMAKE_INSTALL_RPATH` and `$ORIGIN`.
- If a module outside your control sets `LD_RUN_PATH`, unset it immediately with `unset(ENV{LD_RUN_PATH})` at the top of `CMakeLists.txt`.

