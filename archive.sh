#!/bin/bash

# Author: Kenny Speer
# Copyright: Copyright 2016
# Credits: [Kenny Speer]
# License: GPL
# Maintainer: Kenny Speer
# eMail: kenny.speer@gmail.com
# Status: Production

# Prerequisites:
#   if using snowball, snowball must be connected and started from account
#   running this script this script uses 'sb' which is a symlink to the
#   snowball executable

# Description
# Gets a list of files or directories in the directory, first tars the object, then touches
# a tar.done file, then syncs to destination and touches tar.copied file
# remove source or tar as specified

USAGE="USAGE: ./archive.sh --src_dir [directory] --dst_dir [directory] --purge ['source'|'tar'] --filter [regex]\n
    \n\t--src_dir\ttop level source directory of flow cells
    \n\t--dst_dir\tthe destination, can be folder or server (s3://gh.snowball/kenny or /mnt/snowball)
    \n\t--purge  \t'source' deletes the source flow cell directory and 'tar' removes the tar after successfully copying to dst_dir
    \n\t--filter \ta regex filter for the soource dir, i.e. ^1511 to capture all the flowcells from november 2015"

########################################################################
#
# C O N S T A N T S
#
########################################################################

SRC_DIR=/dev/null
DST_DIR=""
FILTER=^0000
PURGE='NONE'

########################################################################
#
# F U N C T I O N S
#
########################################################################

dprint() {
    echo -e "---> ${@}" 2>&1
}

sync_fc() {
	dir=$1

    # continue if we already copied the tar; used to purge source
    if [ ! -e ${dir}.tar.copied ] && [ ! -e ${dir}.tar.cp.snowball ]; then

        # exit if no destination is specified
        if [ "${DST_DIR}" == "" ]; then
            dprint "... no destination specified, skipping copy ..."
            return
        fi

        dprint "... syncing ${dir}.tar to $DST_DIR ..."
        chown _svc_biodata:BioData ${dir}.tar

        echo $DST_DIR | grep "s3:" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            sb -v -w 10 cp ${dir}.tar $DST_DIR && echo "`date` $DST_DIR" > ${dir}.tar.cp.snowball
        else
            rsync -av ${dir}.tar $DST_DIR && echo "`date` $DST_DIR" > ${dir}.tar.copied
        fi
    else
        dprint "found completed tarball already ..."
    fi
       

	if [ $? -eq 0 ]; then
        if [ "$PURGE" == "tar" ]; then
		    dprint "... removing tar file $dir.tar ..."
		    sync && rm -rf ${dir}.tar
        elif [ "$PURGE" == "source" ]; then
            dprint "... removing source dir $dir ..."
            sync && rm -rf $dir
        fi
	fi
}


########################################################################
#
# M A I N 
#
########################################################################

while test $# -gt 0; do
    case "$1" in
        --src_dir)
            SRC_DIR=${2}
            shift
            ;;
        --dst_dir)
            DST_DIR=${2}
            shift
            ;;
        --purge)
            PURGE=${2}
            if [ "$PURGE" != "source" ] && [ "$PURGE" != "tar" ]; then
                dprint "--purge must be either source or tar"
                exit 1
            fi
            shift
            ;;
        --filter)
            FILTER=${2}
            shift
            ;;
        --help)
            echo -e $USAGE
            exit 0
            ;;
    esac
    shift
done

if [ "$SRC_DIR" == "/dev/null" ] || [ "$FILTER" == "^0000" ]; then
    dprint "Must specify at least --src_dir and --filter"
    dprint "Example:\n\t./archive.sh --src_dir /mnt/archive/raw --filter ^1601"
    exit 1
fi

cd $SRC_DIR
DIRS=`ls |egrep ${FILTER}`
for dir in $DIRS; do
	# skip files and the keep dir
	if [ ! -d $dir ]; then continue; fi

	dprint "STARTING: $dir"
		
	if [ -e ${dir}.tar ]; then
		if [ -e ${dir}.tar.done ]; then
			dprint "... already tarred ... skipping"
			sync_fc $dir
			continue
		else
			dprint "... removing ${dir}.tar ..."
			rm -rf ${dir}.tar
		fi
	fi
    
    dprint "... fixing up permissions on $dir ..."
    chmod 755 -R $dir
    chown 4242:4242 -R $dir

	dprint "... tarring $dir ..."

	# return 0 for both 0 and 1 where 1==warning; suppress specific warning
	tar --warning=no-file-changed -cf ${dir}.tar $dir || [[ $? -eq 1 ]]

	if [ $? -eq 0 ]; then
		touch ${dir}.tar.done && sync_fc $dir
	else
		dprint "... tar failed w/ status $?"
	fi

done
