SUMMARY = "a C library that exports various synchronization primitives"
DESCRIPTION = "sync is a C library that exports various synchronization primitives: \
	locks, condition variables, run-once initialization, waitable counter (useful for barriers) \
	waitable bit (useful for cancellation, or other conditions)"

LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=3b83ef96387f14655fc854ddc3c6bd57"

SRCREV = "2e62e2ac97379cdf288cd716ce124f303f5946d5"
SRC_URI = "\
     git://github.com/google/nsync;branch=master;protocol=git \
"

SRC_URI_append += "file://linux.gcc.Makefile"
SRC_URI_append += "file://linux.gcc.dependfile"


S = "${WORKDIR}/git"

do_configure_prepend() {
  mkdir ${S}/builds/linux.gcc
  cp ${S}/../linux.gcc.Makefile ${S}/builds/linux.gcc/Makefile
  cp ${S}/../linux.gcc.dependfile ${S}/builds/linux.gcc/dependfile
  cd ${S}/builds/linux.gcc
}

do_compile_prepend() {
  cd ${S}/builds/linux.gcc
}

EXTRA_OECONF += "--disable-builddir"
EXTRA_OEMAKE_class-target = "LIBTOOLFLAGS='--tag=CC'"
EXTRA_OEMAKE_do_compile = "depend tests"
inherit autotools texinfo

