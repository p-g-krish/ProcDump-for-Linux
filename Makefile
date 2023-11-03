ROOT=.
CC ?= clang
CFLAGS ?= -Wall

# ProcDump implements .NET triggers via a .NET Profiler. .NET has a set of
# architectures that it supports and we have to make sure we're building on
# one of the supported ones below.
HOST := $(shell uname -p)

ifeq ($(HOST), $(filter $(HOST), x86_64 amd64))
	CLRHOSTDEF := -DHOST_AMD64 -DHOST_64BIT
else ifeq ($(HOST), $(filter $(HOST), x86 i686))
	CLRHOSTDEF := -DHOST_X86
else ifeq ($(HOST), $(filter $(HOST), armv6 armv6l))
	CLRHOSTDEF := -DHOST_ARM -DHOST_ARMV6
else ifeq ($(HOST), $(filter $(HOST), arm armv7-a))
	CLRHOSTDEF := -DHOST_ARM
else ifeq ($(HOST), $(filter $(HOST), aarch64 arm64))
	CLRHOSTDEF := -DHOST_ARM64 -DHOST_64BIT
else ifeq ($(HOST), loongarch64)
	CLRHOSTDEF := -DHOST_LOONGARCH64 -DHOST_64BIT
else ifeq ($(HOST), riscv64)
	CLRHOSTDEF := -DHOST_RISCV64 -DHOST_64BIT
else ifeq ($(HOST), s390x)
	CLRHOSTDEF := -DHOST_S390X -DHOST_64BIT -DBIGENDIAN
else ifeq ($(HOST), mips64)
	CLRHOSTDEF := -DHOST_MIPS64 -DHOST_64BIT=1
else ifeq ($(HOST), ppc64le)
	CLRHOSTDEF := -DHOST_POWERPC64 -DHOST_64BIT
else
	$(error Unsupported architecture: $(HOST))
endif

CCFLAGS=$(CFLAGS) -I ./include -pthread -std=gnu99 -fstack-protector-all -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=2 -O2 -Werror
LIBDIR=lib
OBJDIR=obj
SRCDIR=src
INCDIR=include
BINDIR=bin
TESTDIR=tests/integration
DEPS=$(wildcard $(INCDIR)/*.h)
SRC=$(wildcard $(SRCDIR)/*.c)
TESTSRC=$(wildcard $(TESTDIR)/*.c)
OBJS=$(patsubst $(SRCDIR)/%.c, $(OBJDIR)/%.o, $(SRC))
TESTOBJS=$(patsubst $(TESTDIR)/%.c, $(OBJDIR)/%.o, $(TESTSRC))
OUT=$(BINDIR)/procdump
TESTOUT=$(BINDIR)/ProcDumpTestApplication

# Profiler
PROFSRCDIR=profiler/src
PROFINCDIR=profiler/inc
PROFCXXFLAGS ?= -DELPP_NO_DEFAULT_LOG_FILE -DELPP_THREAD_SAFE -g -pthread -shared --no-undefined -Wno-invalid-noreturn -Wno-pragma-pack -Wno-writable-strings -Wno-format-security -fPIC -fms-extensions $(CLRHOSTDEF) -DPAL_STDCPP_COMPAT -DPLATFORM_UNIX -std=c++11
PROFCLANG=clang++

# Revision value from build pipeline
REVISION:=$(if $(REVISION),$(REVISION),'99999')

# installation directory
DESTDIR ?= /
INSTALLDIR=/usr/bin
MANDIR=/usr/share/man/man1

# package creation directories
BUILDDIR := $(CURDIR)/pkgbuild

# Flags to pass to debbuild/rpmbuild
PKGBUILDFLAGS := --define "_topdir $(BUILDDIR)" -bb

# Command to create the build directory structure
PKGBUILDROOT_CREATE_CMD = mkdir -p $(BUILDDIR)/DEBS $(BUILDDIR)/SDEBS $(BUILDDIR)/RPMS $(BUILDDIR)/SRPMS \
			$(BUILDDIR)/SOURCES $(BUILDDIR)/SPECS $(BUILDDIR)/BUILD $(BUILDDIR)/BUILDROOT

# package details
PKG_VERSION:=$(if $(VERSION),$(VERSION),0.0.0)

all: clean build

build: $(OBJDIR)/ProcDumpProfiler.so $(OBJDIR) $(BINDIR) $(OUT) $(TESTOUT)

install:
	mkdir -p $(DESTDIR)$(INSTALLDIR)
	cp $(BINDIR)/procdump $(DESTDIR)$(INSTALLDIR)
	mkdir -p $(DESTDIR)$(MANDIR)
	cp procdump.1 $(DESTDIR)$(MANDIR)

$(OBJDIR)/ProcDumpProfiler.so: $(PROFSRCDIR)/ClassFactory.cpp $(PROFSRCDIR)/ProcDumpProfiler.cpp $(PROFSRCDIR)/dllmain.cpp $(PROFSRCDIR)/corprof_i.cpp $(PROFSRCDIR)/easylogging++.cc | $(OBJDIR)
	$(PROFCLANG) -o $@ $(PROFCXXFLAGS) -I $(PROFINCDIR) -I $(INCDIR) $^
	ld -r -b binary -o $(OBJDIR)/ProcDumpProfiler.o $(OBJDIR)/ProcDumpProfiler.so

$(OBJDIR)/%.o: $(SRCDIR)/%.c | $(OBJDIR)
	$(CC) -c -g -o $@ $< $(CCFLAGS) $(OPT_CCFLAGS)

$(OBJDIR)/%.o: $(TESTDIR)/%.c | $(OBJDIR)
	$(CC) -c -g -o $@ $< $(CCFLAGS)

$(OUT): $(OBJS) | $(BINDIR) $(OBJDIR)/ProcDumpProfiler.so
	$(CC) -o $@ $^ $(OBJDIR)/ProcDumpProfiler.o $(CCFLAGS) $(OPT_CCFLAGS)

$(TESTOUT): $(TESTOBJS) | $(BINDIR)
	$(CC) -o $@ $^ $(CCFLAGS)

$(OBJDIR): clean
	-mkdir -p $(OBJDIR)

$(BINDIR): clean
	-mkdir -p $(BINDIR)

.PHONY: clean
clean:
	-rm -rf $(OBJDIR)
	-rm -rf $(BINDIR)
	-rm -rf $(BUILDDIR)

test: build
	./tests/integration/run.sh

release: clean tarball

.PHONY: tarball
tarball: clean
	$(PKGBUILDROOT_CREATE_CMD)
	tar --exclude=./pkgbuild --exclude=./.git --transform 's,^\.,procdump-$(PKG_VERSION),' -czf $(BUILDDIR)/SOURCES/procdump-$(PKG_VERSION).tar.gz .
	sed -e "s/@PKG_VERSION@/$(PKG_VERSION)/g" dist/procdump.spec.in > $(BUILDDIR)/SPECS/procdump.spec

.PHONY: deb
deb: tarball
	debbuild --define='_Revision ${REVISION}' $(PKGBUILDFLAGS) $(BUILDDIR)/SPECS/procdump.spec

.PHONY: rpm
rpm: tarball
	rpmbuild --define='_Revision ${REVISION}' $(PKGBUILDFLAGS) $(BUILDDIR)/SPECS/procdump.spec
