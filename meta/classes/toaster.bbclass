#
# Toaster helper class
#
# Copyright (C) 2013 Intel Corporation
#
# Released under the MIT license (see COPYING.MIT)
#
# This bbclass is designed to extract data used by OE-Core during the build process,
# for recording in the Toaster system.
# The data access is synchronous, preserving the build data integrity across
# different builds.
#
# The data is transferred through the event system, using the MetadataEvent objects.
#
# The model is to enable the datadump functions as postfuncs, and have the dump
# executed after the real taskfunc has been executed. This prevents task signature changing
# is toaster is enabled or not. Build performance is not affected if Toaster is not enabled.
#
# To enable, use INHERIT in local.conf:
#
#       INHERIT += "toaster"
#
#
#
#

# Find and dump layer info when we got the layers parsed



python toaster_layerinfo_dumpdata() {
    import subprocess

    def _get_git_branch(layer_path):
        branch = subprocess.Popen("git symbolic-ref HEAD 2>/dev/null ", cwd=layer_path, shell=True, stdout=subprocess.PIPE).communicate()[0]
        branch = branch.replace('refs/heads/', '').rstrip()
        return branch

    def _get_git_revision(layer_path):
        revision = subprocess.Popen("git rev-parse HEAD 2>/dev/null ", cwd=layer_path, shell=True, stdout=subprocess.PIPE).communicate()[0].rstrip()
        return revision

    def _get_url_map_name(layer_name):
        """ Some layers have a different name on openembedded.org site,
            this method returns the correct name to use in the URL
        """

        url_name = layer_name
        url_mapping = {'meta': 'openembedded-core'}

        for key in url_mapping.keys():
            if key == layer_name:
                url_name = url_mapping[key]

        return url_name

    def _get_layer_version_information(layer_path):

        layer_version_info = {}
        layer_version_info['branch'] = _get_git_branch(layer_path)
        layer_version_info['commit'] = _get_git_revision(layer_path)
        layer_version_info['priority'] = 0

        return layer_version_info


    def _get_layer_dict(layer_path):

        layer_info = {}
        layer_name = layer_path.split('/')[-1]
        layer_url = 'http://layers.openembedded.org/layerindex/layer/{layer}/'
        layer_url_name = _get_url_map_name(layer_name)

        layer_info['name'] = layer_url_name
        layer_info['local_path'] = layer_path
        layer_info['layer_index_url'] = layer_url.format(layer=layer_url_name)
        layer_info['version'] = _get_layer_version_information(layer_path)

        return layer_info


    bblayers = e.data.getVar("BBLAYERS", True)

    llayerinfo = {}

    for layer in { l for l in bblayers.strip().split(" ") if len(l) }:
        llayerinfo[layer] = _get_layer_dict(layer)


    bb.event.fire(bb.event.MetadataEvent("LayerInfo", llayerinfo), e.data)
}

# Dump package file info data

def _toaster_load_pkgdatafile(dirpath, filepath):
    import json
    import re
    pkgdata = {}
    with open(os.path.join(dirpath, filepath), "r") as fin:
        for line in fin:
            try:
                kn, kv = line.strip().split(": ", 1)
                m = re.match(r"^PKG_([^A-Z:]*)", kn)
                if m:
                    pkgdata['OPKGN'] = m.group(1)
                kn = "_".join([x for x in kn.split("_") if x.isupper()])
                pkgdata[kn] = kv.strip()
                if kn == 'FILES_INFO':
                    pkgdata[kn] = json.loads(kv)

            except ValueError:
                pass    # ignore lines without valid key: value pairs
    return pkgdata


python toaster_package_dumpdata() {
    """
    Dumps the data created by emit_pkgdata
    """
    # replicate variables from the package.bbclass

    packages = d.getVar('PACKAGES', True)
    pkgdest = d.getVar('PKGDEST', True)

    pkgdatadir = d.getVar('PKGDESTWORK', True)

    # scan and send data for each package

    lpkgdata = {}
    for pkg in packages.split():

        lpkgdata = _toaster_load_pkgdatafile(pkgdatadir + "/runtime/", pkg)

        # Fire an event containing the pkg data
        bb.event.fire(bb.event.MetadataEvent("SinglePackageInfo", lpkgdata), d)
}

# 2. Dump output image files information

python toaster_image_dumpdata() {
    """
    Image filename for output images is not standardized.
    image_types.bbclass will spell out IMAGE_CMD_xxx variables that actually
    have hardcoded ways to create image file names in them.
    So we look for files starting with the set name.
    """

    deploy_dir_image = d.getVar('DEPLOY_DIR_IMAGE', True);
    image_name = d.getVar('IMAGE_NAME', True);
    image_info_data = {}

    # collect all images
    for dirpath, dirnames, filenames in os.walk(deploy_dir_image):
        for fn in filenames:
            try:
                if fn.startswith(image_name):
                    image_output = os.path.join(dirpath, fn)
                    image_info_data[image_output] = os.stat(image_output).st_size
            except OSError as e:
                bb.event.fire(bb.event.MetadataEvent("OSErrorException", e), d)

    bb.event.fire(bb.event.MetadataEvent("ImageFileSize",image_info_data), d)
}

python toaster_artifact_dumpdata() {
    """
    Dump data about artifacts in the SDK_DEPLOY directory
    """

    artifact_dir = d.getVar("SDK_DEPLOY", True)
    artifact_info_data = {}

    # collect all artifacts
    for dirpath, dirnames, filenames in os.walk(artifact_dir):
        for fn in filenames:
            try:
                artifact_path = os.path.join(dirpath, fn)
                filestat = os.stat(artifact_path)
                if not os.path.islink(artifact_path):
                    artifact_info_data[artifact_path] = filestat.st_size
            except OSError as e:
                import sys
                bb.event.fire(bb.event.MetadataEvent("OSErrorException", e), d)

    bb.event.fire(bb.event.MetadataEvent("ArtifactFileSize",artifact_info_data), d)
}

# collect list of buildstats files based on fired events; when the build completes, collect all stats and fire an event with collected data

python toaster_collect_task_stats() {
    import bb.build
    import bb.event
    import bb.data
    import bb.utils
    import os

    if not e.data.getVar('BUILDSTATS_BASE', True):
        return  # if we don't have buildstats, we cannot collect stats

    def _append_read_list(v):
        lock = bb.utils.lockfile(e.data.expand("${TOPDIR}/toaster.lock"), False, True)

        with open(os.path.join(e.data.getVar('BUILDSTATS_BASE', True), "toasterstatlist"), "a") as fout:
            taskdir = e.data.expand("${BUILDSTATS_BASE}/${BUILDNAME}/${PF}")
            fout.write("%s::%s::%s::%s\n" % (e.taskfile, e.taskname, os.path.join(taskdir, e.task), e.data.expand("${PN}")))

        bb.utils.unlockfile(lock)

    def _read_stats(filename):
        cpu_usage = 0
        disk_io = 0
        started = '0'
        ended = '0'
        pn = ''
        taskname = ''
        statinfo = {}

        with open(filename, 'r') as task_bs:
            for line in task_bs.readlines():
                k,v = line.strip().split(": ", 1)
                statinfo[k] = v

        if "CPU usage" in statinfo:
            cpu_usage = str(statinfo["CPU usage"]).strip('% \n\r')

        if "IO write_bytes" in statinfo:
            disk_io = disk_io + int(statinfo["IO write_bytes"].strip('% \n\r'))

        if "IO read_bytes" in statinfo:
            disk_io = disk_io + int(statinfo["IO read_bytes"].strip('% \n\r'))

        if "Started" in statinfo:
            started = str(statinfo["Started"]).strip('% \n\r')

        if "Ended" in statinfo:
            ended = str(statinfo["Ended"]).strip('% \n\r')

        elapsed_time = float(ended) - float(started)

        cpu_usage = float(cpu_usage)

        return {'cpu_usage': cpu_usage, 'disk_io': disk_io, 'elapsed_time': elapsed_time}


    if isinstance(e, (bb.build.TaskSucceeded, bb.build.TaskFailed)):
        _append_read_list(e)
        pass


    if isinstance(e, bb.event.BuildCompleted) and os.path.exists(os.path.join(e.data.getVar('BUILDSTATS_BASE', True), "toasterstatlist")):
        events = []
        with open(os.path.join(e.data.getVar('BUILDSTATS_BASE', True), "toasterstatlist"), "r") as fin:
            for line in fin:
                (taskfile, taskname, filename, recipename) = line.strip().split("::")
                events.append((taskfile, taskname, _read_stats(filename), recipename))
        bb.event.fire(bb.event.MetadataEvent("BuildStatsList", events), e.data)
        os.unlink(os.path.join(e.data.getVar('BUILDSTATS_BASE', True), "toasterstatlist"))
}

# dump relevant build history data as an event when the build is completed

python toaster_buildhistory_dump() {
    import re
    BUILDHISTORY_DIR = e.data.expand("${TOPDIR}/buildhistory")
    BUILDHISTORY_DIR_IMAGE_BASE = e.data.expand("%s/images/${MACHINE_ARCH}/${TCLIBC}/"% BUILDHISTORY_DIR)
    pkgdata_dir = e.data.getVar("PKGDATA_DIR", True)


    # scan the build targets for this build
    images = {}
    allpkgs = {}
    files = {}
    for target in e._pkgs:
        installed_img_path = e.data.expand(os.path.join(BUILDHISTORY_DIR_IMAGE_BASE, target))
        if os.path.exists(installed_img_path):
            images[target] = {}
            files[target] = {}
            files[target]['dirs'] = []
            files[target]['syms'] = []
            files[target]['files'] = []
            with open("%s/installed-package-sizes.txt" % installed_img_path, "r") as fin:
                for line in fin:
                    line = line.rstrip(";")
                    psize, px = line.split("\t")
                    punit, pname = px.split(" ")
                    # this size is "installed-size" as it measures how much space it takes on disk
                    images[target][pname.strip()] = {'size':int(psize)*1024, 'depends' : []}

            with open("%s/depends.dot" % installed_img_path, "r") as fin:
                p = re.compile(r' -> ')
                dot = re.compile(r'.*style=dotted')
                for line in fin:
                    line = line.rstrip(';')
                    linesplit = p.split(line)
                    if len(linesplit) == 2:
                        pname = linesplit[0].rstrip('"').strip('"')
                        dependsname = linesplit[1].split(" ")[0].strip().strip(";").strip('"').rstrip('"')
                        deptype = "depends"
                        if dot.match(line):
                            deptype = "recommends"
                        if not pname in images[target]:
                            images[target][pname] = {'size': 0, 'depends' : []}
                        if not dependsname in images[target]:
                            images[target][dependsname] = {'size': 0, 'depends' : []}
                        images[target][pname]['depends'].append((dependsname, deptype))

            with open("%s/files-in-image.txt" % installed_img_path, "r") as fin:
                for line in fin:
                    lc = [ x for x in line.strip().split(" ") if len(x) > 0 ]
                    if lc[0].startswith("l"):
                        files[target]['syms'].append(lc)
                    elif lc[0].startswith("d"):
                        files[target]['dirs'].append(lc)
                    else:
                        files[target]['files'].append(lc)

            for pname in images[target]:
                if not pname in allpkgs:
                    try:
                        pkgdata = _toaster_load_pkgdatafile("%s/runtime-reverse/" % pkgdata_dir, pname)
                    except IOError as err:
                        if err.errno == 2:
                            # We expect this e.g. for RRECOMMENDS that are unsatisfied at runtime
                            continue
                        else:
                            raise
                    allpkgs[pname] = pkgdata


    data = { 'pkgdata' : allpkgs, 'imgdata' : images, 'filedata' : files }

    bb.event.fire(bb.event.MetadataEvent("ImagePkgList", data), e.data)

}

# dump information related to license manifest path

python toaster_licensemanifest_dump() {
    deploy_dir = d.getVar('DEPLOY_DIR', True);
    image_name = d.getVar('IMAGE_NAME', True);

    data = { 'deploy_dir' : deploy_dir, 'image_name' : image_name }

    bb.event.fire(bb.event.MetadataEvent("LicenseManifestPath", data), d)
}

# set event handlers
addhandler toaster_layerinfo_dumpdata
toaster_layerinfo_dumpdata[eventmask] = "bb.event.TreeDataPreparationCompleted"

addhandler toaster_collect_task_stats
toaster_collect_task_stats[eventmask] = "bb.event.BuildCompleted bb.build.TaskSucceeded bb.build.TaskFailed"

addhandler toaster_buildhistory_dump
toaster_buildhistory_dump[eventmask] = "bb.event.BuildCompleted"

do_package[postfuncs] += "toaster_package_dumpdata "
do_package[vardepsexclude] += "toaster_package_dumpdata "

do_rootfs[postfuncs] += "toaster_image_dumpdata "
do_rootfs[postfuncs] += "toaster_licensemanifest_dump "
do_rootfs[vardepsexclude] += "toaster_image_dumpdata toaster_licensemanifest_dump "

do_populate_sdk[postfuncs] += "toaster_artifact_dumpdata "
do_populate_sdk[vardepsexclude] += "toaster_artifact_dumpdata "
