#!/usr/bin/make -f

# fMakefile - Ready to use Makefile for simple Fortran projects,
#             featuring automatic targets and prerequisites
#
# Copyright (c) 2019 André Chalella
# MIT License - see file LICENSE for full text
#
# fMakefile needs no modification to work with any simple Fortran project.
#
# As long as your project abides to the rules that define "simple" (explained
# below), you can just put this Makefile in your project root and run
#
#     $ make
#
# to compile and link all your programs. You can also run
#
#     $ make myprog
#
# to compile and link a program defined in 'src/myprog.f90'.
#
# Rules needed for fMakefile to work:
#
#     1) Each source file contains one complete program (or module), nothing more.
#     2) Module names are the same as their source file names.
#     3) Programs are statically linked with their dependencies (modules).
#     4) Directory structure:
#
#            PROJECT ROOT      MAKEFILE VARIABLE     DESCRIPTION
#            ├── Makefile      -                     This file (or its parent)
#            ├── src           SRCDIR                Program sources
#            │   ├── mod       MODDIR_SUFFIX         Module sources
#            │   └── test      TESTDIR_SUFFIX        Test program sources
#            ├── build (tree)  BUILDDIR_PREFIX       Binaries and .mod files
#            └── dep   (tree)  DEPDIR                Dependency Makefiles (.d)
#
#        - 'build' and 'dep' are autogenerated.
#        - All names are customizable (vars above).
#        - More details in README.md.
#
# Features:
#
#     - Dependency lookup through static source scan, with support for
#       chained dependencies (a.mod uses b.mod uses c.mod...).
#     - Automatic targets for fully building each individual source file.
#       Examples: 'make main_prog', 'make mod_calculate', 'make test_fourier_8'
#     - Phony targets: 'exes' makes all programs, 'tests' makes all tests.
#     - Default target makes all exes and tests.
#     - Colorized output for each build step.
#     - Two sets of build configs (compiler/linker flags): DEBUG and RELEASE.
#
# Limitations:
#
#     - You must choose one source file extension (variable FEXT) and stick
#       with it. I chose .f90, for instance. This hinders use of automatic
#       preprocessing detection in most compilers, however you can turn it
#       always on (-cpp flag in GFortran).
#
# Feel free to customize this file. Most variables you'll want to change have
# UPPERCASE names. If you wish to modify the file further, make sure you
# understand where each thing fits first.
#
# Run "make stripmakefile" if you grow sick of these comments.

#####################
### CONFIGURATION ###
#####################

MAKEFLAGS += --no-builtin-rules

# We need bash since we use "-o pipefail" in .SHELLFLAGS
SHELL := /bin/bash
.SHELLFLAGS += -e -o pipefail

FC := gfortran
FEXT := f90

# ENV: BUILD=debug|release
BUILD ?= debug

AWK := awk

MKDIR := mkdir -p
RMDIR := rm -rf

# Colors for distinguishing the build steps from the myriad of build commands.
# Google "shell colors" for complete reference of color codes.
# Default is: Light Blue, Light Green, Light Purple (looks great in my setup).

COLOR_COMPILE := \e[1;49;34m
COLOR_LINK := \e[1;49;32m
COLOR_DONE := \e[1;49;35m
COLOR_NONE := \e[0m

MSG_DONE = 'Finished making $@'

# DIRECTORY STRUCTURE
#
# .                     CUSTOMIZABLE VAR     FULL PATH VARIABLE  AUTOGENERATED?
# ├─ build              BUILDDIR_PREFIX      -                        yes
# │  └─ debug|release   BUILD [env]          builddir                 yes
# │      ├─ mod          see 'src' tree      moddir                   yes
# │      └─ test         see 'src' tree      testdir                  yes
# ├─ dep                DEPDIR               -                        yes
# │  ├─ mod              see 'src' tree      depmoddir                yes
# │  └─ test             see 'src' tree      -                        yes
# └─ src                SRCDIR               srcexedir                 -
#    ├─ mod             MODDIR_SUFFIX        srcmoddir                 -
#    └─ test            TESTDIR_SUFFIX       srctestdir                -
#
#  More details in README.md.

SRCDIR := src
DEPDIR := dep
BUILDDIR_PREFIX := build
MODDIR_SUFFIX := mod
TESTDIR_SUFFIX := test

srcexedir := $(SRCDIR)
srcmoddir := $(SRCDIR)/$(MODDIR_SUFFIX)
srctestdir := $(SRCDIR)/$(TESTDIR_SUFFIX)

depmoddir := $(DEPDIR)/$(MODDIR_SUFFIX)

builddir := $(BUILDDIR_PREFIX)/$(BUILD)
moddir := $(builddir)/$(MODDIR_SUFFIX)
testdir := $(builddir)/$(TESTDIR_SUFFIX)

# All source files, with directories and extensions.

src_exes := $(wildcard $(srcexedir)/*.$(FEXT))
src_mods := $(wildcard $(srcmoddir)/*.$(FEXT))
src_tests := $(wildcard $(srctestdir)/*.$(FEXT))

# All source files, without directories or extensions ("basenames")
#
# "Basename" here means "filename without directories or suffixes (extensions)",
# that is: 'dir/dir/dir/basename.suffix.suffix' => 'basename'.
#
# I make that clear because the word has different meanings in different Unix
# contexts. For instance, in GNU make, the $(basename args) function only strips
# the last suffix, while in GNU coreutils the basename command by default strips
# only directories.

real_basename = $(basename $(notdir $(1)))

basename_exes := $(call real_basename,$(src_exes))
basename_mods := $(call real_basename,$(src_mods))
basename_tests := $(call real_basename,$(src_tests))

basename_exes_o := $(addsuffix .o,$(basename_exes))
basename_mods_o := $(addsuffix .o,$(basename_mods))
basename_tests_o := $(addsuffix .o,$(basename_tests))

basenames := $(basename_exes) $(basename_mods) $(basename_tests) \
             $(basename_exes_o) $(basename_mods_o)  $(basename_tests_o)

# All dependency Makefiles (.d files), with directories and extensions.

dep_exes := $(subst $(SRCDIR),$(DEPDIR),$(src_exes:.$(FEXT)=.d))
dep_mods := $(subst $(SRCDIR),$(DEPDIR),$(src_mods:.$(FEXT)=.d))
dep_tests := $(subst $(SRCDIR),$(DEPDIR),$(src_tests:.$(FEXT)=.d))

deps := $(dep_exes) $(dep_tests)
deps += $(addsuffix .d,$(deps))
deps += $(dep_mods)

# ENV: FFLAGS  = flags to give to the compiler (e.g -g, -O, -std, -fdec)
#      LDFLAGS = flags to give to the linker (e.g -L, -r)
#      LDLIBS  = library flags to give to the linker (i.e -l...)
#
# These flags are built in such a way that the user can either ADD TO THEM or
# OVERRIDE THEM without editing the Makefile, if that is desired.
#
# - To ADD to them, have the desired variables exported to make.
# - To OVERRIDE them, put them in the make command as the first argument.
#
# Examples:
#
#     - Add to:           $ FFLAGS='-g -O' make exes
#     - Override them:    $ make FFLAGS='-g -O' exes

FFLAGS_ := -Wall -Wextra -Wconversion-extra -pedantic \
           -std=f2018 -fimplicit-none -J$(moddir)

FFLAGS.debug := -g3 -Og -fcheck=all \
                -ffpe-trap=invalid,zero,overflow,underflow,denormal

FFLAGS.release := -O2

FFLAGS := $(FFLAGS_) $(FFLAGS.$(BUILD)) $(FFLAGS)

LDFLAGS_ :=
LDLIBS_ :=

LDFLAGS := $(LDFLAGS_) $(LDFLAGS)
LDLIBS := $(LDLIBS_) $(LDLIBS)

# Final command lines.

compile_cmd = $(FC) $(CFLAGS) $(FFLAGS) -c $< -o $@
link_cmd = $(FC) $(CFLAGS) $(FFLAGS) -o $@ $(LDFLAGS) $^ $(LDLIBS)
copy_cmd = cp -f $< $@
symlink_cmd = ln -sf $< $@
done_cmd = echo -e '$(COLOR_DONE)$(MSG_DONE)$(COLOR_NONE)'
basename_done_cmd = echo '$(copy_cmd)' && $(copy_cmd) && $(done_cmd)
basename_done_cmd_o = echo '$(symlink_cmd)' && $(symlink_cmd) && $(done_cmd)
mkdir_this = $(MKDIR) $(@D)

#####################
###     RULES     ###
#####################

# Main phony rules.

.DEFAULT_GOAL := all
all:   exes tests
exes:  $(basename_exes)
tests: $(basename_tests)
mods:  $(basename_mods)
deps:  $(deps)

# Static pattern rules for directly making individual programs and modules.
#
# Although fMakefile builds things into the BUILDDIR_PREFIX directory, we
# like to use 'make myprog2' better than 'make build/debug/bin/myprog2'. This is
# what these rules do. By copying the binary into the project root, 'myprog2'
# becomes a real target.
#
# Note: when building a module individually, the .o is copied into project root,
# and a symlink is made to it. That means, basically, that 'make mymod1' does:
#
#     cp build/debug/obj/mod/mymod1.o mymod1.o
#     ln -s mymod1.o mymod
#
# 'make cleancopies' will remove all these from the project root. All (relevant)
# cleaning targets include it though, so you'll rarely need to call it directly.

$(basename_exes)    : % : $(builddir)/% ; @ $(basename_done_cmd)
$(basename_exes_o)  : % : $(builddir)/% ; @ $(basename_done_cmd)
$(basename_tests)   : % : $(testdir)/%  ; @ $(basename_done_cmd)
$(basename_tests_o) : % : $(testdir)/%  ; @ $(basename_done_cmd)
$(basename_mods)    : % : %.o           ; @ $(basename_done_cmd_o)
$(basename_mods_o)  : % : $(moddir)/%   ;   $(copy_cmd)

# Pattern rule for linking program binaries.

$(builddir)/% : $(builddir)/%.o
	@ echo -en '$(COLOR_LINK)Linking $*:$(COLOR_NONE) '
	$(mkdir_this)
	echo '$(link_cmd)' && $(link_cmd)

# Pattern rule for compiling.
# Applies to all sources (programs and modules).
# When compiling modules, gfortran automatically puts the resulting .mod file
# (byproduct) in the correct directory (specified with -J).

$(builddir)/%.o : $(SRCDIR)/%.$(FEXT)
	@ echo -en '$(COLOR_COMPILE)Compiling $*.$(FEXT):$(COLOR_NONE) '
	$(MKDIR) $(moddir)
	$(mkdir_this)
	echo '$(compile_cmd)' && $(compile_cmd)

# Pattern rules for the dependency (.d) Makefiles.
#
# Each source file shall have one corresponding .d file. They go in DEPDIR
# ('dep' dir in project root). The recipes below run the source file through our
# awk script to extract the module dependencies from its USE statements.
#
# The awk script is embedded in this Makefile, at the very end.
#
# Program source files have one additional dependency Makefile with extension
# .d.d. This file ensures all chain dependencies are ready before making the .d
# file.
#
# Module source files have one additional intermediate file with extension
# .chain. This file contains all dependencies (direct and chained) of the
# module, and is built by recursively traversing all the dependencies .use
# files.
#
# Examples:
#
# For src/program.f90:
#     - dep/program.use       <= output of AWK with USE statements
#     - dep/program.d.d       <= program.d as target and .chains as prereqs
#     - dep/program.d         <= prereqs for compiling* and linking**
#
# For src/mod/mod1.f90:
#     - dep/mod/mod1.use      <= same as above
#     - dep/mod/mod1.chain    <= all direct and chained deps of mod1
#     - dep/mod/mod1.d        <= prerequisites for compiling* mod1
#
# * only direct dependencies
# ** direct and chained dependencies
#
# Guard file is used to force waiting until all included Makefiles are rebuilt
# and reread before proceeding to chain resolution. Every time a dependency
# Makefile that may affect other Makefiles is modified, the guard is put up so
# that the affected Makefiles forfeit the execution of their recipes, deferring
# until the next restart of make (which always occurs when Makefiles change).
#
# I don't expect this section to be easy to understand, although I did my best
# to tidy it up.

guardfile := $(DEPDIR)/guard

ifneq ($(MAKE_RESTARTS),)
$(info $(shell \
        echo -n "Restarting make ($(MAKE_RESTARTS))" && \
        if [[ -n "$$(rm -fv $(guardfile))" ]]; then \
            echo -n ' (removed guard)'; fi && echo \
    ))
endif

$(depmoddir)/%.d : $(depmoddir)/%.use
	$(dr_start)
	$(dr_truncate_target)
	
	# build/debug/program.o : build/debug/mod/mod1.o [...]
	
	$(call dr_rule_from_use,$(moddir)/$(@F:.d=.o),$(moddir),.o)
	
	# dep/mod/mod1.chain : dep/mod/mod2.chain [...]
	
	$(call dr_rule_from_use,$(@:.d=.chain),$(depmoddir),.chain)
	
	$(dr_create_guard)

%.d : %.use | %.d.d
	$(dr_start)
	$(dr_check_guard)
	
	$(dr_truncate_target)
	target=$(subst $(DEPDIR),$(builddir),$(@:.d=))
	
	# build/debug/program.o : build/debug/mod/mod1.o [...]
	
	$(call dr_rule_from_use,$$target.o,$(moddir),.o)
	
	# build/debug/program.o : build/debug/mod/mod1.o [...]
	
	echo -n "$$target :" >> $@
	for dep in $$(cat $<); do
	    echo $$dep
	    cat $(depmoddir)/$$dep.chain
	done | sort | uniq | $(call dr_sed_tr,$(moddir),.o) >> $@
	echo >> $@
	
	echo

%.d.d : %.use
	$(dr_start)
	$(call dr_rule_from_use,$(basename $@),$(depmoddir),.chain)
	$(dr_create_guard)

$(DEPDIR)/%.use : $(SRCDIR)/%.$(FEXT)
	$(dr_start)
	echo -n " => "
	$(AWK) '$(call awk_make_dep)' $< > $@

$(depmoddir)/%.chain : $(srcmoddir)/%.$(FEXT) | $(depmoddir)/%.d
	$(dr_start)
	
	$(dr_check_guard)
	
	depchains="$(filter %.chain,$^)"
	basenames="$$(sed -E 's/[^ ]*\/([^.]*)[^ ]*/\1/g' <<< $$depchains)"
	
	{ echo $$basenames; cat $$depchains /dev/null; } | sed '/^$$/d' |
	    sort | uniq > $@
	
	echo -n ', '

# Helper functions for dep recipes

dr_start = @ $(mkdir_this); echo -n $@
dr_truncate_target = : > $@
dr_create_guard = : > $(guardfile); echo ' (created guard)'
dr_echo_skipped = echo ' skipped (guard found)'
dr_sed_tr = { sed 's|.*| $(1)/&$(2)|' | tr -d '\n'; }

define dr_check_guard
	if [[ -e $(guardfile) ]]; then
	    echo ' skipped (guard found)'
	    exit
	fi
endef

define dr_rule_from_use
	{
	    echo -n "$(1) :"
	    $(call dr_sed_tr,$(2),$(3)) < $<
	    echo
	} >> $@
endef

# Cleaning rules.
#
# Cleaning targets are:
#     - clean: entire build dir (BUILDDIR_PREFIX) plus binary copies in
#       project root (see note below).
#     - cleanbuild: individual build dir (build/debug or build/release).
#     - cleandeps: dependency directory ('dep' dir containing .d files).
#     - distclean: everything, that is, 'clean' + 'cleandeps'.

clean_targets := clean cleanbuild cleandeps cleancopies finalclean distclean

clean:      cleancopies ; $(RMDIR) $(BUILDDIR_PREFIX)
cleanbuild: cleancopies ; $(RMDIR) $(builddir)
cleandeps:              ; $(RMDIR) $(DEPDIR)

finalclean: cleandeps   ; $(RMDIR) $(BUILDDIR_PREFIX)

distclean: clean cleandeps

cleancopies:
	@ for copy in $(basenames); do
	    if [[ -f $$copy ]]; then echo "rm $$copy" && rm $$copy; fi; done

# Current Makefile invocation path. This is a deferred variable, so any Makefile
# can use it -- but this only works until an 'include' directive is executed.

THIS_MAKEFILE = $(lastword $(MAKEFILE_LIST))

# Target to remove all the comments from this Makefile.
#
# We use a target-specific variable to fix the THIS_MAKEFILE value, since inside
# the recipe its expansion is deferred.

stripmakefile : THIS_MAKEFILE := $(THIS_MAKEFILE)
stripmakefile :
	sed -i -E '/^#($$|[^!])/d' $(THIS_MAKEFILE)

.PHONY: all exes tests mods deps $(clean_targets) stripmakefile

# Optimize by telling make it doesn't know how to make our original files --
# that is, it's not supposed to search for implicit rules for them.

$(THIS_MAKEFILE) $(src_exes) $(src_mods) $(src_tests) : ;

# Prevent deletion of .use, .chain and any other intermediate file.

.SECONDARY:

# Have each recipe run entirely in one shell, as opposed to launching each line
# in a different shell, which would force us to join all commands with &&.

.ONESHELL:

# "So generally the right thing to do is to delete the target file if the
# recipe fails after beginning to change the file. make will do this if
# .DELETE_ON_ERROR appears as a target. This is almost always what you want make
# to do, but it is not historical practice; so for compatibility, you must
# explicitly request it." -- GNU make manual

.DELETE_ON_ERROR:

# Include all dependency Makefiles (.d files)
#
# The complicated logical test prevents the inclusion when make's goal is not
# about building. That is, when goal is one of: clean*, deps and stripmakefile.
# 'deps' is in that list only because, if it isn't, when 'make deps' is called,
# all deps will already be built when make gets to the deps target, prompting a
# bizarre "Nothing to be done for 'deps'" to show right after building all deps.

ifneq "$(or \
        $(if $(MAKECMDGOALS),,true), \
        $(filter-out $(clean_targets) deps stripmakefile, $(MAKECMDGOALS)) \
    )" ""

    include $(deps)

endif

####################
###  AWK SCRIPT  ###
####################

# awk script for generating dependency prerequisites.
#
# This scans a Fortran source file looking for USE statements. Both Fortran's
# valid forms are considered:
#
#     USE [::] <mod-name>[, only: ...]                     (first block)
#     USE, NON_INTRINSIC :: <mod-name>[, only: ...]        (second block)
#
# "USE, INTRINSIC" is ignored since it's the compiler's job to provide for it.
#
# Upon finding a match, it returns only the module name.
#
# Obvious limitations of this tool:
#     - This tool needs the USE statement to be in one line up until <mod-name>.
#     - This tool will be fooled by a USE statement that's part of a multi-line
#       string, or something as contrived.

define awk_make_dep
BEGIN {                                          \
    intrinsics["ISO_C_BINDING"];                 \
    intrinsics["ISO_FORTRAN_ENV"];               \
    intrinsics["IEEE_EXCEPTIONS"];               \
    intrinsics["IEEE_ARITHMETIC"];               \
    intrinsics["IEEE_FEATURES"];                 \
};                                               \
                                                 \
toupper($$0) ~ /^\s*USE[: \t]+[A-Z]/ {           \
    gsub(/[,:]/, " ");                           \
    if ( ! (toupper($$2) in intrinsics) ) {      \
        print $$2;                               \
    }                                            \
};                                               \
                                                 \
toupper($$0) ~ /^\s*USE\s*,\s*NON_INTRINSIC/ {   \
    gsub(/[,:]/, " ");                           \
    print $$3;                                   \
}
endef
