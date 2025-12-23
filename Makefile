SOURCES = sources

COMPILER = gcc

CONFIG_SUB_REV = a2287c3041a3
CONFIG_GUESS_REV = a2287c3041a3
LLVM_VER = 21.1.7
GCC_VER = 14.3.0
MUSL_VER = 1.2.5
GLIBC_VER = 2.42
BINUTILS_VER = 2.45.1
GMP_VER = 6.3.0
MPC_VER = 1.3.1
MPFR_VER = 4.2.2
ISL_VER = 0.27
LINUX_VER = 6.12.59
MINGW_VER = v13.0.0
FREEBSD_VER = 14.3
NETBSD_VER = 10.1
ZLIB_VER = 1.3.1
ZSTD_VER = 1.5.7
LIBXML2_VER = 2.15.1
CHINA = 

# curl --progress-bar -Lo <file> <url>
DL_CMD = curl --retry 30 --retry-delay 3 --retry-max-time 600 --connect-timeout 10 --max-time 600 --progress-bar -Lo
SHA1_CMD = sha1sum -c

COWPATCH = $(CURDIR)/cowpatch.sh
# Use -I for symlink mode (faster, less disk usage) or -C for copy mode (default)
COWPATCH_EXTRACT = -C

-include config.mak

HOST ?= $(if $(NATIVE),$(TARGET))
BUILD_DIR ?= build-$(COMPILER)/$(if $(HOST),$(HOST),local)/$(TARGET)
OUTPUT ?= $(CURDIR)/output-$(COMPILER)$(if $(HOST),-$(HOST))

REL_TOP = ../..$(if $(TARGET),/..)

MUSL_REPO = https://git.musl-libc.org/cgit/musl

LINUX_HEADERS_SITE = https://ftp.barfooze.de/pub/sabotage/tarballs

ifneq ($(CHINA),)
GNU_SITE ?= https://mirrors.ustc.edu.cn/gnu

GCC_SNAP ?= https://mirrors.tuna.tsinghua.edu.cn/sourceware/gcc/snapshots

LINUX_SITE ?= https://mirrors.ustc.edu.cn/kernel.org/linux/kernel

LIBXML2_SITE ?= https://mirrors.ustc.edu.cn/gnome/sources/libxml2
else
# GNU_SITE ?= https://ftp.gnu.org/gnu
GNU_SITE ?= https://ftpmirror.gnu.org/gnu

GCC_SNAP ?= https://sourceware.org/pub/gcc/snapshots

LINUX_SITE ?= https://cdn.kernel.org/pub/linux/kernel

LIBXML2_SITE ?= https://download.gnome.org/sources/libxml2
endif

MUSL_SITE ?= https://musl.libc.org/releases
FREEBSD_SITE ?= https://download.freebsd.org/ftp/releases
NETBSD_SITE ?= https://cdn.netbsd.org/pub/NetBSD
GITHUB ?= https://github.com
GCC_SITE ?= $(GNU_SITE)/gcc
BINUTILS_SITE ?= $(GNU_SITE)/binutils
GMP_SITE ?= $(GNU_SITE)/gmp
MPC_SITE ?= $(GNU_SITE)/mpc
MPFR_SITE ?= $(GNU_SITE)/mpfr
GLIBC_SITE ?= $(GNU_SITE)/glibc
SOURCEFORGE_MIRROR ?= https://downloads.sourceforge.net
ISL_SITE ?= $(SOURCEFORGE_MIRROR)/project/libisl
MINGW_SITE ?= $(SOURCEFORGE_MIRROR)/project/mingw-w64/mingw-w64/mingw-w64-release
LLVM_SITE ?= $(GITHUB)/llvm/llvm-project/releases/download
ZLIB_SITE ?= https://zlib.net
ZSTD_SITE ?= $(GITHUB)/facebook/zstd/releases/download

ifeq ($(COMPILER),gcc)

override LLVM_VER =
override ZLIB_VER =
override LIBXML2_VER =

else

override TARGET = 
override GCC_VER = 
override GMP_VER = 
override MPC_VER =
override MPFR_VER =
override ISL_VER =
override BINUTILS_VER =
override MINGW_VER = 

endif

# Architecture mapping helper function
# Usage: $(call arch_map,OS_NAME,VERSION,ARCH_RULES)
# ARCH_RULES format: "pattern1:dir1 pattern2:dir2 ..."
# Returns: os-version-arch or empty
# Note: Order matters! More specific patterns (e.g., powerpc64le) must come before less specific ones (e.g., powerpc64, powerpc)
arch_map = $(strip $(if $(2),$(foreach rule,$(3),\
  $(if $(findstring $(word 1,$(subst :, ,$(rule))),$(TARGET)),$(1)-$(2)-$(word 2,$(subst :, ,$(rule)))))))

# FreeBSD: x86_64->amd64, aarch64->aarch64, etc.
FREEBSD_ARCH_RULES = x86_64:amd64 aarch64:aarch64 amd64:amd64 powerpc64le:powerpc64le powerpc64:powerpc64 powerpc:powerpc riscv64:riscv64
FREEBSD_ARCH_DIR = $(firstword $(call arch_map,freebsd,$(FREEBSD_VER),$(FREEBSD_ARCH_RULES)))

# NetBSD: x86_64->amd64, aarch64->evbarm-aarch64, mipsel->evbmips-mipsel, powerpc->evbppc, i386/i586/i686->i386, sparc64->sparc64
NETBSD_ARCH_RULES = x86_64:amd64 aarch64:evbarm-aarch64 mipsel:evbmips-mipsel powerpc:evbppc i686:i386 i586:i386 i386:i386 sparc64:sparc64
NETBSD_ARCH_DIR = $(firstword $(call arch_map,netbsd,$(NETBSD_VER),$(NETBSD_ARCH_RULES)))

SRC_DIRS = $(if $(GCC_VER),gcc-$(GCC_VER)) \
	$(if $(BINUTILS_VER),binutils-$(BINUTILS_VER)) \
	$(if $(MUSL_VER),musl-$(MUSL_VER)) \
	$(if $(GLIBC_VER),glibc-$(GLIBC_VER)) \
	$(if $(GMP_VER),gmp-$(GMP_VER)) \
	$(if $(MPC_VER),mpc-$(MPC_VER)) \
	$(if $(MPFR_VER),mpfr-$(MPFR_VER)) \
	$(if $(ISL_VER),isl-$(ISL_VER)) \
	$(if $(LINUX_VER),linux-$(LINUX_VER)) \
	$(if $(MINGW_VER),mingw-w64-$(MINGW_VER)) \
	$(FREEBSD_ARCH_DIR) \
	$(NETBSD_ARCH_DIR) \
	$(if $(LLVM_VER),llvm-project-$(LLVM_VER).src) \
	$(if $(ZLIB_VER),zlib-$(ZLIB_VER)) \
	$(if $(ZSTD_VER),zstd-$(ZSTD_VER)) \
	$(if $(LIBXML2_VER),libxml2-$(LIBXML2_VER))

all:

clean:
	( cd $(CURDIR) && \
	find . -maxdepth 1 \( \
		-name "gcc-*" \
		-o -name "binutils-*" \
		-o -name "musl-*" \
		-o -name "glibc-*" \
		-o -name "gmp-*" \
		-o -name "mpc-*" \
		-o -name "mpfr-*" \
		-o -name "isl-*" \
		-o -name "build" \
		-o -name "build-*" \
		-o -name "linux-*" \
		-o -name "mingw-w64-*" \
		-o -name "freebsd-*" \
		-o -name "netbsd-*" \
		-o -name "llvm-project-*" \
		-o -name "zlib-*" \
		-o -name "zstd-*" \
		-o -name "libxml2-*" \
	\) \
	! -name "*.orig" \
	-type d \
	-exec echo rm -rf {} \; \
	-exec chmod -R u+rwX {} \; \
	-exec rm -rf {} \; )

srcclean:
	( cd $(CURDIR) && ( chmod -R u+rwX netbsd-* 2>/dev/null || true ) && rm -rf sources gcc-* binutils-* musl-* glibc-* gmp-* mpc-* mpfr-* isl-* build build-* linux-* mingw-w64-* freebsd-* netbsd-* llvm-project-* zlib-* zstd-* libxml2-* )

check:
	@echo "check bzip2"
	@which bzip2
	@echo "check xz"
	@which xz
	@echo "check gcc"
	@which gcc
	@echo "check g++"
	@which g++
	@echo "check bison"
	@which bison
	@echo "check rsync"
	@which rsync
	@echo "check sha1sum"
	@which sha1sum

# Rules for downloading and verifying sources.

$(patsubst hashes/%.sha1,$(SOURCES)/%,$(wildcard hashes/gmp*)): SITE = $(GMP_SITE)/$(notdir $@)
$(patsubst hashes/%.sha1,$(SOURCES)/%,$(wildcard hashes/mpc*)): SITE = $(MPC_SITE)/$(notdir $@)
$(patsubst hashes/%.sha1,$(SOURCES)/%,$(wildcard hashes/mpfr*)): SITE = $(MPFR_SITE)/$(notdir $@)
$(patsubst hashes/%.sha1,$(SOURCES)/%,$(wildcard hashes/isl*)): SITE = $(ISL_SITE)/$(notdir $@)
$(patsubst hashes/%.sha1,$(SOURCES)/%,$(wildcard hashes/binutils*)): SITE = $(BINUTILS_SITE)/$(notdir $@)
$(patsubst hashes/%.sha1,$(SOURCES)/%,$(wildcard hashes/gcc-*)): SITE = $(GCC_SITE)/$(basename $(basename $(notdir $@)))/$(notdir $@)
$(patsubst hashes/%.sha1,$(SOURCES)/%,$(wildcard hashes/gcc-*-*)): SITE = $(GCC_SNAP)/$(subst gcc-,,$(basename $(basename $(notdir $@))))/$(notdir $@)
$(patsubst hashes/%.sha1,$(SOURCES)/%,$(wildcard hashes/musl*)): SITE = $(MUSL_SITE)/$(notdir $@)
$(patsubst hashes/%.sha1,$(SOURCES)/%,$(wildcard hashes/glibc*)): SITE = $(GLIBC_SITE)/$(notdir $@)
$(patsubst hashes/%.sha1,$(SOURCES)/%,$(wildcard hashes/linux-6*)): SITE = $(LINUX_SITE)/v6.x/$(notdir $@)
$(patsubst hashes/%.sha1,$(SOURCES)/%,$(wildcard hashes/linux-5*)): SITE = $(LINUX_SITE)/v5.x/$(notdir $@)
$(patsubst hashes/%.sha1,$(SOURCES)/%,$(wildcard hashes/linux-4*)): SITE = $(LINUX_SITE)/v4.x/$(notdir $@)
$(patsubst hashes/%.sha1,$(SOURCES)/%,$(wildcard hashes/linux-3*)): SITE = $(LINUX_SITE)/v3.x/$(notdir $@)
$(patsubst hashes/%.sha1,$(SOURCES)/%,$(wildcard hashes/linux-2.6*)): SITE = $(LINUX_SITE)/v2.6/$(notdir $@)
$(patsubst hashes/%.sha1,$(SOURCES)/%,$(wildcard hashes/linux-headers-*)): SITE = $(LINUX_HEADERS_SITE)/$(notdir $@)
$(patsubst hashes/%.sha1,$(SOURCES)/%,$(wildcard hashes/mingw-w64*)): SITE = $(MINGW_SITE)/$(notdir $@)
$(patsubst hashes/%.sha1,$(SOURCES)/%,$(wildcard hashes/llvm-project-*)): SITE = $(LLVM_SITE)/llvmorg-$(patsubst llvm-project-%.src,%,$(basename $(basename $(notdir $@))))/$(notdir $@)
$(patsubst hashes/%.sha1,$(SOURCES)/%,$(wildcard hashes/zlib-*)): SITE = $(ZLIB_SITE)/$(notdir $@)
$(patsubst hashes/%.sha1,$(SOURCES)/%,$(wildcard hashes/zstd-*)): SITE = $(ZSTD_SITE)/v$(patsubst zstd-%.tar.gz,%,$(notdir $@))/$(notdir $@)
$(patsubst hashes/%.sha1,$(SOURCES)/%,$(wildcard hashes/libxml2-*)): SITE = $(LIBXML2_SITE)/$(shell echo $(patsubst libxml2-%.tar.xz,%,$(notdir $@)) | cut -d. -f1,2)/$(notdir $@)

$(SOURCES):
	mkdir -p $@

$(SOURCES)/config.sub: | $(SOURCES)
	mkdir -p $@.tmp
	cd $@.tmp && $(DL_CMD) $(notdir $@) "https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=$(CONFIG_SUB_REV)"
	cd $@.tmp && touch $(notdir $@)
	cd $@.tmp && $(SHA1_CMD) $(CURDIR)/hashes/$(notdir $@).$(CONFIG_SUB_REV).sha1
	mv $@.tmp/$(notdir $@) $@
	rm -rf $@.tmp

$(SOURCES)/config.guess: | $(SOURCES)
	mkdir -p $@.tmp
	cd $@.tmp && $(DL_CMD) $(notdir $@) "https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=$(CONFIG_GUESS_REV)"
	cd $@.tmp && touch $(notdir $@)
	cd $@.tmp && $(SHA1_CMD) $(CURDIR)/hashes/$(notdir $@).$(CONFIG_GUESS_REV).sha1
	mv $@.tmp/$(notdir $@) $@
	rm -rf $@.tmp

# Define template for FreeBSD base.txz download rules
# $(1) = architecture suffix (e.g., amd64, aarch64, powerpc64le)
# $(2) = download path (e.g., amd64, arm64/aarch64, powerpc/powerpc64le)
define FREEBSD_DOWNLOAD_RULE
$$(SOURCES)/freebsd-%-$(1).tar.xz: hashes/freebsd-%-$(1).tar.xz.sha1 | $$(SOURCES)
	mkdir -p $$@.tmp
	cd $$@.tmp && $$(DL_CMD) $$(notdir $$@) $$(FREEBSD_SITE)/$(2)/$$*-RELEASE/base.txz
	cd $$@.tmp && touch $$(notdir $$@)
	cd $$@.tmp && $$(SHA1_CMD) $$(CURDIR)/hashes/$$(notdir $$@).sha1
	mv $$@.tmp/$$(notdir $$@) $$@
	rm -rf $$@.tmp
endef

# Generate download rules for each FreeBSD architecture
$(eval $(call FREEBSD_DOWNLOAD_RULE,amd64,amd64))
$(eval $(call FREEBSD_DOWNLOAD_RULE,aarch64,arm64/aarch64))
$(eval $(call FREEBSD_DOWNLOAD_RULE,powerpc,powerpc/powerpc))
$(eval $(call FREEBSD_DOWNLOAD_RULE,powerpc64,powerpc/powerpc64))
$(eval $(call FREEBSD_DOWNLOAD_RULE,powerpc64le,powerpc/powerpc64le))
$(eval $(call FREEBSD_DOWNLOAD_RULE,riscv64,riscv/riscv64))

# NetBSD source download rules
# Downloads base.tar.xz and comp.tar.xz separately with hash verification
# $(1) = architecture suffix (e.g., amd64, evbarm-aarch64, i386)
# $(2) = download path (e.g., amd64, evbarm-aarch64, i386)
define NETBSD_DOWNLOAD_RULE
$$(SOURCES)/netbsd-%-$(1)-base.tar.xz: hashes/netbsd-%-$(1)-base.tar.xz.sha1 | $$(SOURCES)
	mkdir -p $$@.tmp
	cd $$@.tmp && $$(DL_CMD) $$(notdir $$@) $$(NETBSD_SITE)/NetBSD-$$*/$(2)/binary/sets/base.tar.xz
	cd $$@.tmp && touch $$(notdir $$@)
	cd $$@.tmp && $$(SHA1_CMD) $$(CURDIR)/hashes/$$(notdir $$@).sha1
	mv $$@.tmp/$$(notdir $$@) $$@
	rm -rf $$@.tmp

$$(SOURCES)/netbsd-%-$(1)-comp.tar.xz: hashes/netbsd-%-$(1)-comp.tar.xz.sha1 | $$(SOURCES)
	mkdir -p $$@.tmp
	cd $$@.tmp && $$(DL_CMD) $$(notdir $$@) $$(NETBSD_SITE)/NetBSD-$$*/$(2)/binary/sets/comp.tar.xz
	cd $$@.tmp && touch $$(notdir $$@)
	cd $$@.tmp && $$(SHA1_CMD) $$(CURDIR)/hashes/$$(notdir $$@).sha1
	mv $$@.tmp/$$(notdir $$@) $$@
	rm -rf $$@.tmp

netbsd-%-$(1): $$(SOURCES)/netbsd-%-$(1)-base.tar.xz $$(SOURCES)/netbsd-%-$(1)-comp.tar.xz
	( chmod -R u+rwX $$@.tmp $$@ 2>/dev/null || true ) && rm -rf $$@.tmp $$@
	mkdir -p $$@.tmp
	cd $$@.tmp && tar -Jxf $$(CURDIR)/$$(SOURCES)/netbsd-$$*-$(1)-base.tar.xz
	cd $$@.tmp && tar -Jxf $$(CURDIR)/$$(SOURCES)/netbsd-$$*-$(1)-comp.tar.xz
	mv $$@.tmp $$@
endef

# NetBSD download rule for .tgz format (i386 uses this)
# $(1) = architecture suffix (e.g., i386)
# $(2) = download path (e.g., i386)
define NETBSD_DOWNLOAD_RULE_TGZ
$$(SOURCES)/netbsd-%-$(1)-base.tgz: hashes/netbsd-%-$(1)-base.tgz.sha1 | $$(SOURCES)
	mkdir -p $$@.tmp
	cd $$@.tmp && $$(DL_CMD) $$(notdir $$@) $$(NETBSD_SITE)/NetBSD-$$*/$(2)/binary/sets/base.tgz
	cd $$@.tmp && touch $$(notdir $$@)
	cd $$@.tmp && $$(SHA1_CMD) $$(CURDIR)/hashes/$$(notdir $$@).sha1
	mv $$@.tmp/$$(notdir $$@) $$@
	rm -rf $$@.tmp

$$(SOURCES)/netbsd-%-$(1)-comp.tgz: hashes/netbsd-%-$(1)-comp.tgz.sha1 | $$(SOURCES)
	mkdir -p $$@.tmp
	cd $$@.tmp && $$(DL_CMD) $$(notdir $$@) $$(NETBSD_SITE)/NetBSD-$$*/$(2)/binary/sets/comp.tgz
	cd $$@.tmp && touch $$(notdir $$@)
	cd $$@.tmp && $$(SHA1_CMD) $$(CURDIR)/hashes/$$(notdir $$@).sha1
	mv $$@.tmp/$$(notdir $$@) $$@
	rm -rf $$@.tmp

netbsd-%-$(1): $$(SOURCES)/netbsd-%-$(1)-base.tgz $$(SOURCES)/netbsd-%-$(1)-comp.tgz
	( chmod -R u+rwX $$@.tmp $$@ 2>/dev/null || true ) && rm -rf $$@.tmp $$@
	mkdir -p $$@.tmp
	cd $$@.tmp && tar -xzf $$(CURDIR)/$$(SOURCES)/netbsd-$$*-$(1)-base.tgz
	cd $$@.tmp && tar -xzf $$(CURDIR)/$$(SOURCES)/netbsd-$$*-$(1)-comp.tgz
	mv $$@.tmp $$@
endef

# Generate download rules for each NetBSD architecture
$(eval $(call NETBSD_DOWNLOAD_RULE,amd64,amd64))
$(eval $(call NETBSD_DOWNLOAD_RULE,evbarm-aarch64,evbarm-aarch64))
$(eval $(call NETBSD_DOWNLOAD_RULE_TGZ,evbmips-mipsel,evbmips-mipsel))
$(eval $(call NETBSD_DOWNLOAD_RULE_TGZ,evbppc,evbppc))
$(eval $(call NETBSD_DOWNLOAD_RULE_TGZ,i386,i386))
$(eval $(call NETBSD_DOWNLOAD_RULE,sparc64,sparc64))

$(SOURCES)/%: hashes/%.sha1 | $(SOURCES)
	mkdir -p $@.tmp
	cd $@.tmp && $(DL_CMD) $(notdir $@) $(SITE)
	cd $@.tmp && touch $(notdir $@)
	cd $@.tmp && $(SHA1_CMD) $(CURDIR)/hashes/$(notdir $@).sha1
	mv $@.tmp/$(notdir $@) $@
	rm -rf $@.tmp

# Rules for extracting and patching sources, or checking them out from git.

musl-git-%:
	rm -rf $@.tmp
	git clone $(MUSL_REPO) $@.tmp
	cd $@.tmp && git reset --hard $(patsubst musl-git-%,%,$@) && git fsck
	test ! -d patches/$@ || cat $(wildcard patches/$@/*) | ( cd $@.tmp && patch -p1 )
	mv $@.tmp $@

%.orig: $(SOURCES)/%.tar.gz
	case "$@" in */*) exit 1 ;; esac
	rm -rf $@.tmp
	mkdir -p $@.tmp/$(patsubst %.orig,%,$@)
	( tar -zxf - --strip-components 1 -C $@.tmp/$(patsubst %.orig,%,$@) ) < $<
	rm -rf $@
	mv $@.tmp/$(patsubst %.orig,%,$@) $@
	rm -rf $@.tmp

%.orig: $(SOURCES)/%.tar.bz2
	case "$@" in */*) exit 1 ;; esac
	rm -rf $@.tmp
	mkdir -p $@.tmp/$(patsubst %.orig,%,$@)
	( tar -jxf - --strip-components 1 -C $@.tmp/$(patsubst %.orig,%,$@) ) < $<
	rm -rf $@
	mv $@.tmp/$(patsubst %.orig,%,$@) $@
	rm -rf $@.tmp

%.orig: $(SOURCES)/%.tar.xz
	case "$@" in */*) exit 1 ;; esac
	rm -rf $@.tmp
	mkdir -p $@.tmp/$(patsubst %.orig,%,$@)
	( tar -Jxf - --strip-components 1 -C $@.tmp/$(patsubst %.orig,%,$@) ) < $<
	rm -rf $@
	mv $@.tmp/$(patsubst %.orig,%,$@) $@
	rm -rf $@.tmp

define find_and_prefix
$(addprefix $(SOURCES)/,$(notdir $(wildcard hashes/\$1*.sha1)))
endef

%: %.orig | $(SOURCES)/config.sub $(SOURCES)/config.guess
	case "$@" in */*) exit 1 ;; esac
	rm -rf $@.tmp
	mkdir $@.tmp
	( cd $@.tmp && $(COWPATCH) $(COWPATCH_EXTRACT) ../$< )
	if [ -d patches/$@ ] && [ -n "$(shell find patches/$@ -type f)" ]; then \
		if [ -n "$(findstring mingw,$(TARGET))" ]; then \
			cat $(filter-out %-musl.diff %-gnu.diff %-freebsd.diff %-netbsd.diff %-nonmingw.diff,$(wildcard patches/$@/*)) | ( cd $@.tmp && $(COWPATCH) -p1 ); \
		elif [ -n "$(findstring freebsd,$(TARGET))" ]; then \
			cat $(filter-out %-mingw.diff %-gnu.diff %-musl.diff %-netbsd.diff %-nofreebsd.diff,$(wildcard patches/$@/*)) | ( cd $@.tmp && $(COWPATCH) -p1 ); \
		elif [ -n "$(findstring netbsd,$(TARGET))" ]; then \
			cat $(filter-out %-mingw.diff %-gnu.diff %-musl.diff %-freebsd.diff %-nonetbsd.diff,$(wildcard patches/$@/*)) | ( cd $@.tmp && $(COWPATCH) -p1 ); \
		elif [ -n "$(findstring musl,$(TARGET))" ]; then \
			cat $(filter-out %-mingw.diff %-gnu.diff %-freebsd.diff %-netbsd.diff %-nonmusl.diff,$(wildcard patches/$@/*)) | ( cd $@.tmp && $(COWPATCH) -p1 ); \
		else \
			cat $(filter-out %-mingw.diff %-musl.diff %-freebsd.diff %-netbsd.diff %-nongnu.diff,$(wildcard patches/$@/*)) | ( cd $@.tmp && $(COWPATCH) -p1 ); \
		fi \
	fi
	( cd $@.tmp && find -L . -name config.sub -type f -exec cp -f $(CURDIR)/$(SOURCES)/config.sub {} \; -exec chmod +x {} \; )
	( cd $@.tmp && find -L . -name configfsf.sub -type f -exec cp -f $(CURDIR)/$(SOURCES)/config.sub {} \; -exec chmod +x {} \; )
	( cd $@.tmp && find -L . -name config.guess -type f -exec cp -f $(CURDIR)/$(SOURCES)/config.guess {} \; -exec chmod +x {} \; )
	( cd $@.tmp && find -L . -name configfsf.guess -type f -exec cp -f $(CURDIR)/$(SOURCES)/config.guess {} \; -exec chmod +x {} \; )
	rm -rf $@
	mv $@.tmp $@

ifeq ($(COMPILER),clang)
extract_all: | $(filter-out mingw-w64-% glibc-% freebsd-% netbsd-%,$(SRC_DIRS))
else ifneq ($(findstring mingw,$(TARGET)),)
extract_all: | $(filter-out linux-% musl-% glibc-% freebsd-% netbsd-%,$(SRC_DIRS))
else ifneq ($(findstring freebsd,$(TARGET)),)
extract_all: | $(filter-out mingw-w64-% musl-% glibc-% linux-% netbsd-%,$(SRC_DIRS))
else ifneq ($(findstring netbsd,$(TARGET)),)
extract_all: | $(filter-out mingw-w64-% musl-% glibc-% linux-% freebsd-%,$(SRC_DIRS))
else ifneq ($(findstring musl,$(TARGET)),)
extract_all: | $(filter-out mingw-w64-% glibc-% freebsd-% netbsd-%,$(SRC_DIRS))
else ifneq ($(findstring gnu,$(TARGET))$(findstring glibc,$(TARGET)),)
extract_all: | $(filter-out mingw-w64-% musl-% freebsd-% netbsd-%,$(SRC_DIRS))
else
# Default to glibc for standard Linux targets
extract_all: | $(filter-out mingw-w64-% musl-% freebsd-% netbsd-%,$(SRC_DIRS))
endif

extract_all: | $(patsubst %.sha1,%, $(foreach item,$(SRC_DIRS),$(call find_and_prefix,$(item)))) $(SOURCES)/config.sub $(SOURCES)/config.guess
# Add deps for all patched source dirs on their patchsets
$(foreach dir,$(notdir $(basename $(basename $(basename $(wildcard hashes/*))))),$(eval $(dir): $(wildcard patches/$(dir) patches/$(dir)/*)))

# Rules for building.

$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/Makefile: | $(BUILD_DIR)
	ln -sf $(REL_TOP)/litecross/Makefile.$(COMPILER) $@

$(BUILD_DIR)/config.mak: | $(BUILD_DIR)
	printf >$@ '%s\n' \
	"HOST = $(HOST)" \
	$(if $(TARGET),"TARGET = $(TARGET)") \
	$(if $(GCC_VER),"GCC_SRCDIR = $(REL_TOP)/gcc-$(GCC_VER)") \
	$(if $(BINUTILS_VER),"BINUTILS_SRCDIR = $(REL_TOP)/binutils-$(BINUTILS_VER)") \
	$(if $(MUSL_VER),"MUSL_SRCDIR = $(REL_TOP)/musl-$(MUSL_VER)") \
	$(if $(MUSL_VER),"SSP_SRCDIR = $(REL_TOP)/extra/ssp") \
	$(if $(GLIBC_VER),"GLIBC_SRCDIR = $(REL_TOP)/glibc-$(GLIBC_VER)") \
	$(if $(FREEBSD_ARCH_DIR),"FREEBSD_SRCDIR = $(REL_TOP)/$(FREEBSD_ARCH_DIR)") \
	$(if $(NETBSD_ARCH_DIR),"NETBSD_SRCDIR = $(REL_TOP)/$(NETBSD_ARCH_DIR)") \
	$(if $(GMP_VER),"GMP_SRCDIR = $(REL_TOP)/gmp-$(GMP_VER)") \
	$(if $(MPC_VER),"MPC_SRCDIR = $(REL_TOP)/mpc-$(MPC_VER)") \
	$(if $(MPFR_VER),"MPFR_SRCDIR = $(REL_TOP)/mpfr-$(MPFR_VER)") \
	$(if $(ISL_VER),"ISL_SRCDIR = $(REL_TOP)/isl-$(ISL_VER)") \
	$(if $(LINUX_VER),"LINUX_SRCDIR = $(REL_TOP)/linux-$(LINUX_VER)") \
	$(if $(MINGW_VER),"MINGW_SRCDIR = $(REL_TOP)/mingw-w64-$(MINGW_VER)") \
	$(if $(LLVM_VER),"LLVM_SRCDIR = $(REL_TOP)/llvm-project-$(LLVM_VER).src") \
	$(if $(LLVM_VER),"LLVM_VER = $(LLVM_VER)") \
	$(if $(ZLIB_VER),"ZLIB_SRCDIR = $(REL_TOP)/zlib-$(ZLIB_VER)") \
	$(if $(ZSTD_VER),"ZSTD_VER = $(ZSTD_VER)") \
	$(if $(ZSTD_VER),"ZSTD_SRCDIR = $(REL_TOP)/zstd-$(ZSTD_VER)") \
	$(if $(LIBXML2_VER),"LIBXML2_SRCDIR = $(REL_TOP)/libxml2-$(LIBXML2_VER)") \
	"-include $(REL_TOP)/config.mak"

ifeq ($(COMPILER),)

all:
	@echo COMPILER must be set via config.mak or command line.
	@exit 1

else ifeq ($(COMPILER)$(TARGET),gcc)

all:
	@echo TARGET must be set for gcc build via config.mak or command line.
	@exit 1

else

all: | extract_all $(BUILD_DIR) $(BUILD_DIR)/Makefile $(BUILD_DIR)/config.mak
	cd $(BUILD_DIR) && $(MAKE) $@

install: | extract_all $(BUILD_DIR) $(BUILD_DIR)/Makefile $(BUILD_DIR)/config.mak
	cd $(BUILD_DIR) && $(MAKE) OUTPUT=$(OUTPUT) $@

endif

.SECONDARY:
