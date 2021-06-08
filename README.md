# fMakefile

_Ready-to-use makefile for simple Fortran projects,
featuring **automatic targets** and **dependency resolution**._

<sub>Copyright (c) 2019-2021 André Chalella</sub> \
<sup>MIT License - see file LICENSE for full text</sup>

## Overview

**fMakefile** is a makefile for **GNU make** that needs no modification to work
with any simple Fortran project, where you have a few programs, a few modules
and need everything statically linked.

As long as your project abides to the rules below, you can just put this
makefile in your project root and run

    $ make

to compile and link all your programs. You can also run

    $ make myprog

to compile and link a program defined in `src/myprog.f90`. There are many other
possibilites (see the **Examples** section).

**fMakefile** accomplishes the correct prerequisite resolution through static
source code scanning via a small embedded **awk** script. Prerequisites are then
stored in small auxiliary makefiles in the `dep/` tree, and are read and updated
automatically by **fMakefile** as needed.

Compilation order is then resolved naturally by **make**.  There is no magic,
just plain **GNU make**.

**fMakefile** builds everything into a `build` directory tree, and later copies
binaries into the project root. Upon *clean*ing, all these are done away with.

_For details, read the heavily commented makefile._

### Features

- Dependency resolution that supports chained dependencies (*program* uses
  *mod1* which uses *mod2* which uses *mod3* -- and everything just works!)
- Automatic targets for fully building each individual source file -- and much
  more.
- Submodules are supported and compiled correctly (linking requires an extra
  step).
- Colorized output for each build step.
- Two sets of build configs (compiler/linker flags): DEBUG and RELEASE.
- Variable `THIS_MAKEFILE` (deferred) provided so any other included makefile
  can find its own invocation path (note: it must be used before any
  `include` statement).
- Customizable build flags, directory names etc.

_Read the sections below for a better understanding (with examples) of all the
features._

### Requirements

- **GNU make**
- **GNU awk** (`gawk`)
- **GNU coreutils** (`grep`, `sort`, `uniq`...)
- **bash**

### Rules

1. Each source file must contain one complete program, module or submodule.
2. Module names must be the same as their source file names.
3. Directory structure below must be observed.

**fMakefile** required directory structure:

    PROJECT ROOT     MAKEFILE VARIABLE     DESCRIPTION
    ├── Makefile     -                     This file (or its parent)
    ├── src          SRCDIR                Program sources
    │   └── mod      MODDIR_SUFFIX         Module sources
    ├── build        BUILDDIR_PREFIX       Binaries and .mod files
    └── dep          DEPDIR                Dependency makefiles (.d)

- `build` and `dep` are autogenerated.
- All modules must be in `mod`.
  - Subdirectories in `mod` are for submodules.
- Programs must be directly in `src` (or any subdir thereof, except `mod`).
- All names are customizable (vars above).
- All source files must use the same suffix (extension), by default `.f90`
  (customizable in the `FEXT` variable).

### Examples

Assume the following project tree:

    proj
    ├── Makefile
    └── src
        ├── mod
        │   ├── mod1.f90
        │   └── mod2.f90
        └── program.f90

*Makefile* is **fMakefile** (simplest approach) *or* a Makefile that *includes*
**fMakefile** (recommended approach, since this way you can extend **fMakefile**
without directly modifying it).

Run `make` from the project root:

    $ cd /path/to/proj
    $ make

And an executable named `program` will show up in your project root:

    proj
    ├── build/
    ├── dep/
    ├── src/
    ├── Makefile
    └── program

### Many programs

Assume the following project tree:

    proj
    ├── Makefile
    └── src
        ├── mod
        │   ├── mod1.f90
        │   └── mod2.f90
        ├── test
        │   ├── test1.f90
        │   └── test2.f90
        ├── program1.f90
        └── program2.f90

Running `make` will build **all programs** and put them in your project root:

    $ make

    proj
    ├── build/
    ├── dep/
    ├── src/
    ├── Makefile
    ├── program1
    ├── program2
    ├── test1
    └── test2

**fMakefile** can also build only specific targets:

    $ make program1         # 'program1' is built and copied into project root
    $ make test2            # 'test2' is built and copied into project root
    $ make program1 test1   # 'program1' and 'test1' show up in project root

### Subdirectories

For convenience, you can make all programs in one source subdirectory --
recursively or not. Consider:

    proj
    ├── Makefile
    └── src
        ├── mod
        │   ├── mod1.f90
        │   └── mod2.f90
        ├── program1.f90
        ├── program2.f90
        └── test
            ├── test_sub_1
            │   ├── ts1a.f90
            │   └── ts1b.f90
            ├── test_sub_2
            │   ├── ts2a.f90
            │   └── ts2b.f90
            ├── test1.f90
            └── test2.f90

Then you have some options:

    $ make test/            # all directly under test (test1 and test2)
    $ make test//           # two slashes means RECURSIVE, so this makes:
                            #     test1 test2 ts1a ts1b ts2a ts2b
    $ make test/test_sub_1/ # sure enough, this will make ts1a and ts1b
    $ make test/test_sub_2/ # sure enough, this will make ts2a and ts2b
    $ make .                # the dot is special syntax for 'only source root',
                            # so this will make program1 and program2.

Note: the dot syntax recursive counterpart is, obviously, simply `make` with no
arguments.

### Object files

You can tell **fMakefile** to only compile a specific source file, _be it a
program or a module:_

    $ make program.o        # program.o shows up in your project root
    $ make test1.o
    $ make mod1.o
    $ make mod2.o
    $ make mod/             # compiles and copies all modules

### Submodules

Consider the following project tree, which has submodules:

    proj
    ├── Makefile
    └── src
        ├── mod
        │   ├── mod1.f90
        │   ├── mod_parent.f90
        │   └── mod_parent
        │       ├── mod_sub1.f90
        │       └── mod_sub1
        │           └── mod_sub2.f90
        └── program.f90

For clarity, the modules and submodules are:

- `mod1`
- `mod_parent`
- `mod_parent:mod_sub1`
- `mod_parent:mod_sub1:mod_sub2`

Suppose `program` USEs both `mod1` and `mod_parent`, and the latter has parts
defined in both submodules `mod_sub1` and `mod_sub2`. Below you'll find source
code that illustrates such arrangement, but for now consider it to be true.

Simply running `make` will not work yet. **fMakefile** can compile each part
correctly, but it doesn't know that `program` needs `mod_sub1` and `mod_sub2`.
You need to give it a little hand in your project makefile:

    $ cat Makefile
    include /path/to/fMakefile/Makefile
    $(builddir)/program : $(moddir)/mod_parent/mod_sub1.o \
                          $(moddir)/mod_parent/mod_sub1/mod_sub2.o

Notice we use the `builddir` and `moddir` helper variables, which are defined by
**fMakefile**.

Now you can run `make` (or any other invocation described here), and `program`
will be correctly built.

As promised, here is example source code for our example project tree:

    $ cat src/program.f90
    program prog
    use mod1
    use mod_parent
    print *, func_mod1(), func_modp1(), func_modp2()
    end program

    $ cat src/mod/mod1.f90
    module mod1
    contains
    integer function func_mod1()
        func_mod1 = 1
    end function
    end module

    $ cat src/mod/mod_parent.f90
    module mod_parent
    interface
        module integer function func_modp1()
        end function
        module integer function func_modp2()
        end function
    end interface
    end module

    $ cat src/mod/mod_parent/mod_sub1.f90
    submodule (mod_parent) mod_sub1
    contains
    module procedure func_modp1
        func_modp1 = 2
    end procedure
    end submodule

    $ cat src/mod/mod_parent/mod_sub1/mod_sub2.f90
    submodule (mod_parent:mod_sub1) mod_sub2
    contains
    module procedure func_modp2
        func_modp2 = 3
    end procedure
    end submodule

### Making a RELEASE build

By default, **fMakefile** will make a _debug_ build, with debug compiler flags
and into the `build/debug/` tree. To change the build type, just set the `BUILD`
variable:

    $ BUILD=release make            # option 1 (shell variable)
    $ export BUILD=release; make    # option 2 (shell variable)
    $ make BUILD=release            # option 3 (make variable)

Note: you may need to run `make cleancopies` for **fMakefile** to start a
different build type if your project root contains built files from the old
build type, else you may get the `Nothing to be done for '...'` message.

### Cleaning

**fMakefile** has quite a number of phony goals for cleaning:

    $ make clean            # removes all files built and copied into the
                            # project root, plus the build/ dir
    $ make cleancopies      # removes all files copied into the project root
    $ make distclean        # removes EVERYTHING fMakefile has put in your
                            # project root, that is: copies, build/ and dep/
    $ make finalclean       # removes build/ and dep/ (leaves copies)

There's even more, but these are for debugging mostly:

    $ make cleanbuild       # removes build/(debug|release)/ + copies
    $ make cleandeps        # removes dep/

### Ambiguous names

If your source tree has source files with the same name in different
directories, you won't be able to specify the correct one with the basename
syntax (`make program`).

In this case, use this alternative syntax:

    $ make path/to/program          # compile and link src/path/to/program.f90
    $ make path/to/other/program.o  # same name, different subdir, just compile

This way the full path is specified.

Note: when this syntax is used, the result file is not copied to project root
(that is, it stays in the `build/` tree).
