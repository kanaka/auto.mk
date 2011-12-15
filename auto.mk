#####################################################################
# auto.mk:
# Simpler makefiles: auto.mk without automake.
#
# Include this makefile in software Makefiles. See auto.mk.README for
# more information.
#
# Copyright (c) 2008 SiCortex, Inc
# Created by Joel Martin: <joel.martin@sicortex.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program*; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#
# See the file LICENSE that came with this source file for the full
# terms and conditions of the GNU General Public License.
#####################################################################

#####################################################################
# Global Settings
#####################################################################

STANDALONE_PROGS = $(ANTHRAX_PROGS) $(L2_ANTHRAX_PROGS) $(FPGA_ANTHRAX_PROGS) $(BOOT_PROGS)
_FULLLIST = $(PROGS) $(STANDALONE_PROGS) $(STATIC_LIBS) $(SHARED_LIBS)
_FOR_BUILD_LIST = $(FOR_BUILD_STATIC_LIBS) $(FOR_BUILD_PROGS)
BUILDLIST ?= $(_FULLLIST) $(BINARY_FILES) $(POD_MANPAGES)

# Change 'implicit' values but still allow environment override
setdefault=$(if $(filter default undefined,$(origin $(1))),$(eval $(1)=$(2)))

$(call setdefault,FC,scpathf95)
$(call setdefault,CC,$$(PREFIX)gcc)
$(call setdefault,CXX,$$(PREFIX)g++)
$(call setdefault,AR,$$(PREFIX)ar)
$(call setdefault,RANLIB,$$(PREFIX)ranlib)
$(call setdefault,LD,$$(PREFIX)ld)
$(call setdefault,OBJCOPY,$$(PREFIX)objcopy)
$(call setdefault,OBJDUMP,$$(PREFIX)objdump)

_ASFLAGS += -D__ASSEMBLER__ -D__ASSEMBLY__ -x assembler-with-cpp $(INCDIRS)
ifneq ($(CARP),)
  $(error Do not use CARP. Fix your warnings! Or set warn options per source file)
endif
_CARP ?= -Wall -Werror
_ASFLAGS += $(ASFLAGS)
_FFLAGS += $(FFLAGS) $(_CARP) -MMD $(INCDIRS) $(OPTIMIZE)
_CFLAGS += $(CFLAGS) $(_CARP) -MMD $(INCDIRS) $(OPTIMIZE)
_CXXFLAGS += $(CXXFLAGS) $(_CARP) -MMD $(INCDIRS) $(OPTIMIZE)
_LDFLAGS += $(LDFLAGS)

# The standard GNU names for the native toolchain programs
CC_FOR_BUILD = gcc
LD_FOR_BUILD = ld
AR_FOR_BUILD = ar

#####################################################################
# Architecture Settings
#####################################################################

# Default to mips unless overridden
ARCH ?= x86_64

ifneq ($(filter mips%,$(ARCH)),)
  # MIPS architecture
  PREFIX ?= sc
  _CC = $(CC)
  _FC = $(FC)
  _ROOT = $(firstword $(SYSROOT) $(filter-out /,$(ROOT)))

  # Determine ABI from $(ARCH), $(ABI) or default to 'n64'
  _ABI = $(word 2,$(subst _, ,$(ARCH)) $(ABI) n64)

  OPTIMIZE   ?= -O2 # -g
  ifneq ($(filter %o32,$(_ABI)),)
    STANDALONE += -mabi=32
  else
    ifneq ($(filter %n32,$(_ABI)),)
      STANDALONE += -mabi=n32 -mips64
      _LIBSUFFIX = 32
    else
      STANDALONE += -mabi=64 -mips64
      _LIBSUFFIX = 64
    endif
  endif
  STANDALONE += -EL -fverbose-asm
  _Anthrax_flags += -DANTHRAX  -nostdlib
  _ASFLAGS   += $(STANDALONE) -g
  _FFLAGS    += $(STANDALONE) -g
  _CFLAGS    += $(STANDALONE) -MP -g -std=c99
  _CXXFLAGS  += $(STANDALONE) -MP -g -std=c99
  _LDFLAGS   += -EL -L. -g

  drop-sections = .reginfo .mdebug .comment .note .pdr .options .MIPS.options
  strip-flags   = $(addprefix --remove-section=,$(drop-sections))
else
  ifneq ($(filter m68k% coldfire%,$(ARCH)),)
    # m68k Coldfire architecture
    PREFIX ?= m68k-elf-

    ifneq ($(strip $(filter-out false no off False No Off 0,$(USE_CXX))),)
      _CC = $(CXX)
    else
      _CC = $(CC)
    endif
    

    _COLDCFLAGS = -m5307 -fno-common -fno-builtin -msep-data
    _COLDLDFLAGS = -m5307 -Wl,-elf2flt -Wl,-move-rodata -msep-data

    _CFLAGS += $(_COLDCFLAGS) -O1 -g -pipe -U__STRICT_ANSI__
    _CXXFLAGS += $(_COLDCFLAGS) -O1 -g -pipe
    _LDFLAGS += $(_COLDLDFLAGS) -lc
  else
    # x86/x86_64 architecture
    ifneq ($(strip $(filter-out false no off False No Off 0,$(USE_CXX))),)
      _CC = $(CXX)
    else
      _CC = $(CC)
      _CFLAGS += -std=c99
    endif
    _FC = $(FC)
    _ROOT = $(firstword $(ROOT))
    
    OPTIMIZE ?= -O3
    _CFLAGS += -MP -g -U__STRICT_ANSI__
    _CFLAGS += -DHAVE_READLINE -DUSE_ADDR64 -DUSE_INT64 -DADDR2LINE -DSYSMAP
    _CXXFLAGS += -MP -g
    _CXXFLAGS += -DHAVE_READLINE -DUSE_ADDR64 -DUSE_INT64 -DADDR2LINE -DSYSMAP
  endif
endif

#####################################################################
# Pathing Magic
#####################################################################

# The core logic that allow us to co-exist in different build
# environments:
# 	- vtest
# 	- cmProject
# 	- in-tree (combined source and build)
# 	- standalone (No /sicortex, no project dir, etc)

srcdir   = .
builddir = .
VPATH += $(builddir) $(srcdir)
_LDdirs += -L$(builddir)
INCDIRS += -I$(builddir) -I$(srcdir)

PROJECT ?= $(shell scmake --loc 2>/dev/null)
ifeq ($(PROJECT),)
  # We were invoked outside a project environment
  $(warning Running outside of a project environment)
  PROJECT = /NO_PROJECT
  PROJECT_builddir = /

  # TODO/FIXME: how should make dependencies find installed stuff?
  VPATH += $(_ROOT)/usr/include $(_ROOT)/usr/lib$(_LIBSUFFIX)
  ifneq ($(_ROOT),)
    INCDIRS += -I$(_ROOT)/usr/include
    _LDdirs += -L$(_ROOT)/usr/lib$(_LIBSUFFIX)
  endif
else
  # we were invoked inside a project environment
  PROJECT_builddir = $(PROJECT)/build
  DESTDIR = $(builddir)/image/

  INCDIRS += $(addprefix -I,$(call findsrc,sw/include))
endif

# Standard install target information
prefix = /usr
exec_prefix = $(prefix)
includedir = ${prefix}/include
bindir = $(exec_prefix)/bin
libdir = $(prefix)/lib$(_LIBSUFFIX)
mandir = ${prefix}/share/man

# Utility routines to find source and object/build directories

# Find a srcdir
findsrc = $(firstword $(wildcard $(PROJECT)/$(1) ))

# Split source and build: find the first matching build directory
findobj = $(firstword $(wildcard $(builddir)/../$(1) $(builddir)/$(1) \
	      $(PROJECT_builddir)/$(1) $(if $(filter /%,$(1)),$(1),) ))

# Set VPATH, INCDIRS and libs based on SRC_DEPS and OBJ_DEPS
VPATH += $(foreach X,$(OBJ_DEPS),$(call findobj,$(X)))
_LDdirs += $(addprefix -L,$(foreach X,$(OBJ_DEPS),$(call findobj,$(X))))
INCDIRS += $(addprefix -I,$(foreach X,$(OBJ_DEPS),$(call findobj,$(X))))

VPATH += $(foreach X,$(SRC_DEPS),$(call findsrc,$(X)))
INCDIRS += $(addprefix -I,$(foreach X,$(SRC_DEPS),$(call findsrc,$(X))))

#####################################################################
# Populate *_OBJS lists based on *_SRCS and *_LIBS
#####################################################################

# Build list of sources used more than once
ALL_SRCS = $(foreach X,$(_FULLLIST) $(_FOR_BUILD_LIST),$($(X)_SRCS))
define _sieveSRCS
  $$(if $$(filter-out 0 1,$$(words $$(filter $(1),$(2)))), \
     $$(eval SHARED_SRCS += $(1)))
endef
$(foreach X,$(sort $(ALL_SRCS)),$(eval $(call _sieveSRCS,$(X),$(ALL_SRCS))))

# Split sources up and build object lists
define _doOBJS
  # pathf95 recognizes six types of fortran suffices: .f90/.F90/.f95/.F95/.f/.F
  $(1)_fort_f90_OBJS   = $$(foreach Y,$$(filter %.f90,$$($(1)_SRCS)), \
                     $$(if $$(filter $$(Y),$$(SHARED_SRCS)), \
		        $$(patsubst %.f90,%__$(1).o,$$(Y)), \
		        $$(patsubst %.f90,%.o,$$(Y)) ) )
  $(1)_fort_F90_OBJS  += $$(foreach Y,$$(filter %.F90,$$($(1)_SRCS)), \
                     $$(if $$(filter $$(Y),$$(SHARED_SRCS)), \
		        $$(patsubst %.F90,%__$(1).o,$$(Y)), \
		        $$(patsubst %.F90,%.o,$$(Y)) ) )
  $(1)_fort_f95_OBJS  += $$(foreach Y,$$(filter %.f95,$$($(1)_SRCS)), \
                     $$(if $$(filter $$(Y),$$(SHARED_SRCS)), \
		        $$(patsubst %.f95,%__$(1).o,$$(Y)), \
		        $$(patsubst %.f95,%.o,$$(Y)) ) )
  $(1)_fort_F95_OBJS  += $$(foreach Y,$$(filter %.F95,$$($(1)_SRCS)), \
                     $$(if $$(filter $$(Y),$$(SHARED_SRCS)), \
		        $$(patsubst %.F95,%__$(1).o,$$(Y)), \
		        $$(patsubst %.F95,%.o,$$(Y)) ) )
  $(1)_fort_f_OBJS  += $$(foreach Y,$$(filter %.f,$$($(1)_SRCS)), \
                     $$(if $$(filter $$(Y),$$(SHARED_SRCS)), \
		        $$(patsubst %.f,%__$(1).o,$$(Y)), \
		        $$(patsubst %.f,%.o,$$(Y)) ) )
  $(1)_fort_F_OBJS  += $$(foreach Y,$$(filter %.F,$$($(1)_SRCS)), \
                     $$(if $$(filter $$(Y),$$(SHARED_SRCS)), \
		        $$(patsubst %.F,%__$(1).o,$$(Y)), \
		        $$(patsubst %.F,%.o,$$(Y)) ) )
  $(1)_c_OBJS   = $$(foreach Y,$$(filter %.c,$$($(1)_SRCS)), \
                     $$(if $$(filter $$(Y),$$(SHARED_SRCS)), \
		        $$(patsubst %.c,%__$(1).o,$$(Y)), \
		        $$(patsubst %.c,%.o,$$(Y)) ) )
  $(1)_cpp_OBJS = $$(foreach Y,$$(filter %.cpp,$$($(1)_SRCS)), \
                       $$(if $$(filter $$(Y),$$(SHARED_SRCS)), \
		          $$(patsubst %.cpp,%__$(1).o,$$(Y)), \
		          $$(patsubst %.cpp,%.o,$$(Y)) ) )
  $(1)_s_OBJS   = $$(foreach Y,$$(filter %.s,$$($(1)_SRCS)), \
                     $$(if $$(filter $$(Y),$$(SHARED_SRCS)), \
		        $$(patsubst %.s,%__$(1).o,$$(Y)), \
		        $$(patsubst %.s,%.o,$$(Y)) ) )
  $(1)_OBJS     = $$(sort $$($(1)_c_OBJS) \
	$$($(1)_fort_f90_OBJS) $$($(1)_fort_F90_OBJS) \
	$$($(1)_fort_f95_OBJS) $$($(1)_fort_F95_OBJS) \
	$$($(1)_fort_f_OBJS) $$($(1)_fort_F_OBJS) \
	$$($(1)_cpp_OBJS) $$($(1)_s_OBJS))
  $(1)_LOBJS    = $$(addsuffix .a,$$(addprefix lib,$$($(1)_LIBS)))
  $(1)_lflags  += $$(addprefix -l,$$($(1)_LIBS))
  _tOBJS       += $$($(1)_OBJS)
endef
$(foreach X,$(_FULLLIST) $(_FOR_BUILD_LIST),$(eval $(call _doOBJS,$(X))))

ALL_OBJS = $(sort $(_tOBJS)) $(EXTRA_OBJS)
_DEPFILES = $(ALL_OBJS:.o=.d)

# Force sources to local directory or include locations
ifneq ($(filter /%,$(ALL_OBJS)),)
  $(error Absolute source paths forbidden: $(filter /%,$(ALL_OBJS)))
endif

#####################################################################
# Global build targets
#####################################################################

.DEFAULT: all
.PHONY: all clean

all: $(BUILDLIST) $(_FOR_BUILD_LIST)

# Vtest wants this target
for_vtest : all
	echo "*-* All Finished *-*"

# Debug and help
showVars : 
	@echo "_FULLLIST: $(foreach X,$(_FULLLIST),$(X))"

help:
	@$${PAGER:-less} $(filter %auto.mk,$(MAKEFILE_LIST)).README

clean:
	rm -f $(ALL_OBJS) $(_DEPFILES) $(foreach X,$(STATIC_LIBS),lib$(X).a) \
	      $(foreach X,$(FOR_BUILD_STATIC_LIBS),lib$(X).a) \
	      $(foreach X,$(SHARED_LIBS),lib$(X).so) \
	      $(foreach X,$(STANDALONE_PROGS),$(X).elf $(X).dis) \
	      $(PROGS) $(FOR_BUILD_PROGS) $(BINARY_FILES)

-include $(_DEPFILES)  # Rebuild when include files change

# Create leading build directories
$(foreach X,$(sort $(dir $(PROGS) $(ALL_OBJS))),$(shell mkdir -p $(X)))

#####################################################################
# Object specific compile flags and build targets
#####################################################################

# Standalone specific flags
$(foreach X,$(ANTHRAX_PROGS), \
  $(eval $(X)_flags ?= $$(_Anthrax_flags) ) \
  $(eval $(X)_LOBJS += libanthrax.a ) \
  $(eval $(X)_OBJDUMPFLAGS += -M reg-names=numeric -D) \
  $(eval $(X)_LN ?= anthrax.ln ))
$(foreach X,$(L2_ANTHRAX_PROGS), \
  $(eval $(X)_flags ?= $$(_Anthrax_flags) ) \
  $(eval $(X)_LOBJS += libl2_anthrax.a ) \
  $(eval $(X)_OBJDUMPFLAGS += -M reg-names=numeric -D) \
  $(eval $(X)_LN ?= l2_anthrax.ln ))
$(foreach X,$(FPGA_ANTHRAX_PROGS), \
  $(eval $(X)_flags ?= $$(_Anthrax_flags) ) \
  $(eval $(X)_LOBJS += libfpga_anthrax.a ) \
  $(eval $(X)_OBJDUMPFLAGS += -M reg-names=numeric -D) \
  $(eval $(X)_LN ?= fpga_anthrax.ln ))
$(foreach X,$(BOOT_PROGS), \
  $(eval $(X)_OBJDUMPFLAGS += -M reg-names=numeric -D -z) \
  $(eval $(X)_LN ?= $(X).ln ))
$(foreach X,$(PROGS) $(FOR_BUILD_PROGS) $(STATIC_LIBS) $(FOR_BUILD_STATIC_LIBS) $(SHARED_LIBS), \
  $(if $(filter -DANTHRAX,$(CFLAGS) $(CXXFLAGS) $($(X)_CFLAGS) $($(X)_FFLAGS) $($(X)_CXXFLAGS)), \
    $(eval $(X)_flags ?= $$(_Anthrax_flags) ),))

# Compile flag list:
#   global (CFLAGS):       _CFLAGS
#   per program:           $($(1))_CFLAGS
#   per program (anthrax): $($(1))_flags
#   per object:            $($(2))_CFLAGS
#   per source:            $($(2):.o=.c)_CFLAGS
define _objRULE
  $(2): %$$(if $$(filter %__$(1).o,$(2)),__$(1),).o : %.$(3)
	$$(_CC) $$(_$(4)FLAGS) $$($(1)_$(4)FLAGS) $$($(1)_flags) \
		 $$($$(subst __$(1),,$(2))_$(4)FLAGS) \
		 $$($$(patsubst %.o,%.$(3),$$(subst __$(1),,$(2)))_$(4)FLAGS) \
		 -c $$< -o $$@
endef

define _objfRULE
  $(2): %$$(if $$(filter %__$(1).o,$(2)),__$(1),).o : %.$(3)
	$$(_FC) $$(_$(4)FLAGS) $$($(1)_$(4)FLAGS) $$($(1)_flags) \
		 $$($$(subst __$(1),,$(2))_$(4)FLAGS) \
		 $$($$(patsubst %.o,%.$(3),$$(subst __$(1),,$(2)))_$(4)FLAGS) \
		 -c $$< -o $$@
endef

define _objFOR_BUILD_RULE
  $(2): %$$(if $$(filter %__$(1).o,$(2)),__$(1),).o : %.$(3)
	$$(CC_FOR_BUILD) $$($(1)_$(4)FLAGS) $$($(1)_flags) \
		 $$($$(subst __$(1),,$(2))_$(4)FLAGS) \
		 $$($$(patsubst %.o,%.$(3),$$(subst __$(1),,$(2)))_$(4)FLAGS) \
		 -c $$< -o $$@
endef

#  Variables:
#  1: program, 2: object, 3: extension, 4: FLAG prefix
$(foreach X,$(_FULLLIST), \
  $(foreach Y,$($(X)_fort_f90_OBJS), $(eval $(call _objfRULE,$(X),$(Y),f90,F))) \
  $(foreach Y,$($(X)_fort_F90_OBJS), $(eval $(call _objfRULE,$(X),$(Y),F90,F))) \
  $(foreach Y,$($(X)_fort_f95_OBJS), $(eval $(call _objfRULE,$(X),$(Y),f95,F))) \
  $(foreach Y,$($(X)_fort_F95_OBJS), $(eval $(call _objfRULE,$(X),$(Y),F95,F))) \
  $(foreach Y,$($(X)_fort_f_OBJS),   $(eval $(call _objfRULE,$(X),$(Y),f,F))) \
  $(foreach Y,$($(X)_fort_F_OBJS),   $(eval $(call _objfRULE,$(X),$(Y),F,F))) \
  $(foreach Y,$($(X)_c_OBJS), $(eval $(call _objRULE,$(X),$(Y),c,C))) \
  $(foreach Y,$($(X)_cpp_OBJS), $(eval $(call _objRULE,$(X),$(Y),cpp,CXX))) \
  $(foreach Y,$($(X)_s_OBJS), $(eval $(call _objRULE,$(X),$(Y),s,AS))))

$(foreach X,$(_FOR_BUILD_LIST), \
  $(foreach Y,$($(X)_c_OBJS), $(eval $(call _objFOR_BUILD_RULE,$(X),$(Y),c,C))) \
  $(foreach Y,$($(X)_cpp_OBJS), $(eval $(call _objFOR_BUILD_RULE,$(X),$(Y),cpp,CXX))) \
  $(foreach Y,$($(X)_s_OBJS), $(eval $(call _objFOR_BUILD_RULE,$(X),$(Y),s,AS))))

#####################################################################
# Program specific build targets
#####################################################################

define _doPROGS
  $(1): $$($(1)_OBJS) $$($(1)_LOBJS)
	$(_CC) $(_CFLAGS) $$($(1)_OBJS) $(_LDdirs) $$($(1)_lflags) $$($(1)_LDFLAGS) $(_LDFLAGS) -o $$@
endef
$(foreach X,$(PROGS),$(eval $(call _doPROGS,$(X))))

define _doFOR_BUILD_PROGS
  $(1): $$($(1)_OBJS) $$($(1)_LOBJS)
	$(CC_FOR_BUILD) $$($(1)_OBJS) $(_LDdirs) $$($(1)_lflags) $$($(1)_LDFLAGS) -o $$@
endef
$(foreach X,$(FOR_BUILD_PROGS),$(eval $(call _doFOR_BUILD_PROGS,$(X))))

define _doFOR_BUILD_STATIC_LIBS
  .PHONY: $(1)
  $(1): lib$(1).a
  lib$(1).a:  $$($(1)_OBJS) $$($(1)_LOBJS)
	$$(AR_FOR_BUILD) r $$@ $$^
endef
$(foreach X,$(FOR_BUILD_STATIC_LIBS),$(eval $(call _doFOR_BUILD_STATIC_LIBS,$(X))))

define _doSTANDALONE_PROGS
  .PHONY: $(1)
  $(1): $(1).elf $(if $(USE_DIS),$(1).dis,)
  $(1).elf: $$($(1)_LN) $$($(1)_OBJS) $$($(1)_LOBJS)
	$(LD) $$($(1)_OBJS) $(_LDdirs) $$($(1)_lflags) $$($(1)_LDFLAGS) $(_LDFLAGS) $$(if $$<,-T $$<,) -o $$@
  $(1).dis: $(1).elf
	$(OBJDUMP) $$($(1)_OBJDUMPFLAGS) $$^ > $$@
endef
$(foreach X,$(STANDALONE_PROGS),$(eval $(call _doSTANDALONE_PROGS,$(X))))

define _doSTATIC_LIBS
  .PHONY: $(1)
  $(1): lib$(1).a
  lib$(1).a:  $$($(1)_OBJS) $$($(1)_LOBJS)
	$$(AR) r $$@ $$^
endef
$(foreach X,$(STATIC_LIBS),$(eval $(call _doSTATIC_LIBS,$(X))))

define _doSHARED_LIBS
  .PHONY: $(1)
  $(1): lib$(1).so
  lib$(1).so:  $$($(1)_OBJS) $$($(1)_LOBJS)
	$$(_CC) -shared $$^ $$($(1)_LDFLAGS) -o $$@
endef
$(foreach X,$(SHARED_LIBS),$(eval $(call _doSHARED_LIBS,$(X))))

define _doBINARY_FILES
$(1): % : %.bin
	cp $$< $$@
endef
$(foreach X,$(BINARY_FILES),$(eval $(call _doBINARY_FILES,$(X))))

#####################################################################
# Manpages
#####################################################################

# ls /usr/share/man/ | grep man
MAN_SECTIONS = 0p 1 1p 2 3 3p 4 5 6 7 8 9 n

# rules for making manpages from .pod
define _doPOD2MAN
%.$(1) : %.pod
	pod2man -c "SiCortex Manual" --section $(1) -r "" $$< > $$@
endef
$(foreach X,$(MAN_SECTIONS),$(eval $(call _doPOD2MAN,$(X))))


#####################################################################
# Program specific install targets
#####################################################################
install: install-PROGS install-STANDALONE_PROGS \
         install-STATIC_LIBS install-SHARED_LIBS \
         install-BINARY_FILES install-HEADERS \
         install-MANPAGES

install-PROGS: $(filter $(PROGS),$(BUILDLIST))
	@list='$^'; for p in $$list; do \
	  mkdir -p $(DESTDIR)$(bindir); \
	  echo "install -m 755 $$p $(DESTDIR)$(bindir)"; \
	        install -m 755 $$p $(DESTDIR)$(bindir); \
	done

install-STANDALONE_PROGS: $(filter $(STANDALONE_PROGS),$(BUILDLIST))
	@list='$^'; for p in $$list; do \
	  mkdir -p $(DESTDIR)$(bindir); \
	  echo "install -m 755 $$p $(DESTDIR)$(bindir)"; \
	        install -m 755 $$p $(DESTDIR)$(bindir); \
	done

install-STATIC_LIBS: $(filter $(STATIC_LIBS),$(BUILDLIST))
	@list='$^'; for p in $$list; do \
	  mkdir -p $(DESTDIR)$(libdir); \
	  echo "install -m 755 lib$${p}.a $(DESTDIR)$(libdir)"; \
	        install -m 755 lib$${p}.a $(DESTDIR)$(libdir); \
	done

install-SHARED_LIBS: $(filter $(SHARED_LIBS),$(BUILDLIST))
	@list='$^'; for p in $$list; do \
	  mkdir -p $(DESTDIR)$(libdir); \
	  echo "install -m 755 lib$${p}.so $(DESTDIR)$(libdir)"; \
	        install -m 755 lib$${p}.so $(DESTDIR)$(libdir); \
	done

install-BINARY_FILES: $(filter $(BINARY_FILES),$(BUILDLIST))
	@list='$^'; for p in $$list; do \
	  echo What to do with binary file $${p}; \
	done

install-HEADERS: $(inst_HEADERS)
	@list='$^'; for p in $$list; do \
	  mkdir -p $(DESTDIR)$(includedir); \
	  echo "install -m 644 $${p} $(DESTDIR)$(includedir)"; \
	        install -m 644 $${p} $(DESTDIR)$(includedir); \
	done


# foreach section, install any manpages found in the appropriate place
install-MANPAGES: $(inst_MANPAGES) $(POD_MANPAGES)
	@list='$^'; for p in $$list; do \
	  ext=$${p##*.}; \
	  mkdir -p $(DESTDIR)$(mandir)/man$${ext}; \
	  echo "install -m 644 $${p} $(DESTDIR)$(mandir)/man$${ext}"; \
	        install -m 644 $${p} $(DESTDIR)$(mandir)/man$${ext}; \
	done
