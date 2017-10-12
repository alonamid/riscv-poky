SUMMARY = "A small image just capable of allowing a device to boot."

DEPENDS += "riscv-pk riscv-spike-native"

#IMAGE_FEATURES += "package-management"

inherit core-image

IMAGE_INSTALL = "packagegroup-core-boot ${ROOTFS_BOOTSTRAP_INSTALL} ${CORE_IMAGE_EXTRA_INSTALL}"

# Basic packages
IMAGE_INSTALL += "apt libffi libffi-dev"

# Python
IMAGE_INSTALL += "python-numpy python-subprocess python-ctypes python-html python-netserver python-compile"

# Basic toolchain on target
IMAGE_INSTALL += "gcc binutils glibc glibc-dev libgcc libgcc-dev libstdc++ libstdc++-dev"

# Networking
IMAGE_INSTALL += "openssh"

# Advanced packages
IMAGE_INSTALL += "cmake boost python-pip python-setuptools python-cython python-six python-pytest python-pandas jemalloc apache-arrow python-pyarrow"

IMAGE_LINGUAS = " "

LICENSE = "MIT"

IMAGE_ROOTFS_SIZE ?= "8192"
