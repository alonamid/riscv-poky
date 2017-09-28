FILESEXTRAPATHS_prepend := "${THISDIR}/init-ifupdown-1.0:"

SRC_URI_append += "file://init-ifupdown-firesim.patch \
                   file://init-interfaces-firesim.patch \
"

