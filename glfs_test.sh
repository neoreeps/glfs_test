#!/bin/bash

# Author: Kenny Speer
# Copyright: Copyright 2016
# Credits: [Kenny Speer]
# License: GPL
# Maintainer: Kenny Speer
# eMail: kenny.speer@gmail.com
# Status: Production

# Installation: 
#   1. Install this file in /opt
#   2. Set cron to run either via /etc/cron.d or crontab -e
#   3. Edit email Recipients to include any additional folks
#   4. Edit bricks and hosts lists accordingly
#   5. Ensure root has passwordless ssh to hosts
#   6. Ensure each gluster node has gluster volume mounted locally
#   7. For email ensure that postfix (easy) and mutt are installed

# Description:
# Validate gluster configuration

# Example:
# To mount gluster volume and clean before running test:
#   ./glfs_test.sh clean mount
#
# To clean test dir but keep previous mount: (recommended)
#   ./glfs_test.sh clean

################################################################################
#
# C O N S T A N T S
#
################################################################################

ACTION=$1
OPTION=$2

TIMEOUT=300  # 5 min to cover heavily loaded system
VOLNAME="gv0"
TEST_MOUNT="/mnt/${VOLNAME}"
TEST_DIR="glfs_test"
TEST_PATH="${TEST_MOUNT}/${TEST_DIR}"
SEED="${TEST_PATH}/seed"
COUNT=100  # 100 is sufficient
SUBJECT="GlusterFS Test FAIL"
RECIPIENTS="kenny.speer@gmail.com"
BRICKS="brick-01 brick-02 brick-03 brick-04 brick-05"
BRICK_PATH="/glfs"
HOSTS="glfs-01 glfs-02"

#notify
PROGNAME=$(basename $0)
USER="`hostname`:$PROGNAME"
ICON=":bangbang:"
CHANNEL="storage"

################################################################################
#
# F U N C T I O N S
#
################################################################################

dprint() {
    echo "--->  ${@}" >&2
}

send_mail() {
    echo "$MESSAGE" | mutt -s "${SUBJECT}" -- $RECIPIENTS
}

slack_notify() {
    # curl -X POST --data-urlencode 'payload={"channel": "#'$CHANNEL'", "username": "'$USER'", "text": "'"$MESSAGE"'", "icon_emoji": "'$ICON'"}' https://your.slack.url
    echo "... add your own slack URL here ... "
}

notify() {
    MESSAGE=$1
    send_mail
    slack_notify
    exit 9
}

################################################################################
#
# M A I N
#
################################################################################

# test notifications
if [ "$ACTION" == "test" ]; then
    notify "This is a test, this is only a test.  BEEEEEEEP!"
fi

# prep test log
echo '' >> /tmp/glfs_test.log
echo `date` >> /tmp/glfs_test.log

# mount gluster
if [ "$OPTION" == "mount" ]; then
    dprint "Mounting gluster filesystem at ${TEST_MOUNT} w/ ${TIMEOUT}s timeout"
    timeout -k 1s ${TIMEOUT}s mount ${TEST_MOUNT}
    if [ $? -ne 0 ]; then
        notify "Failed to mount storage at ${TEST_MOUNT}"
    fi
fi

# remove directory before running test
if [ "$ACTION" == "clean" ]; then
    # cleanup
    dprint "Cleaning up test directory before test"
    timeout -k 1s ${TIMEOUT}s rm -rf ${TEST_PATH}
    if [ $? -ne 0 ]; then
        notify "Failed to cleanup test directory before test"
    fi
fi

# make testdir if it doesn't exist
if [ ! -d $TEST_PATH ]; then
    dprint "Creating test directory"
    timeout -k 1s ${TIMEOUT}s mkdir $TEST_PATH
    if [ $? -ne 0 ]; then
        notify "Failed to create test directory"
    fi
fi

# create seed file to start test
dprint "Creating seed file"
if [ ! -f $SEED ]; then echo `date` > $SEED; fi

# create the files so each is unique by updating the seed file first
dprint "Creating test files and md5sums"
for i in $(seq 1 $COUNT); do
    fname="${TEST_PATH}/FILE_${i}"
    echo `md5sum ${SEED}` > $fname 
    if [ $? -ne 0 ]; then
        notify "Failed to create file: ${fname}"
    fi
    echo `md5sum ${fname}` >> $SEED
done

# wait a few seconds for systems to sync
dprint "Force heal and replication via dir listing."
ls -la ${TEST_PATH} >> /dev/null 2>&1
sleep 30

# clean out local logs
for host in $HOSTS; do
    echo `date` > /tmp/glfs_test_${host}.log
done

# check each brick for the files
for brick in $BRICKS; do
    for host in $HOSTS; do
        dprint "Checking file integrity in $brick on $host"
        # check if test dir exists (not all bricks may contain based on dispersion algo
        # for each file named FILE* md5sum, then grep the result in seed file
        ssh $host "if [ -d ${BRICK_PATH}/${brick}/${VOLNAME}/${TEST_DIR} ]; then
                       for file in ${BRICK_PATH}/${brick}/${VOLNAME}/${TEST_DIR}/FILE*; do
                           grep "'`md5sum $file`'" ${SEED};"'
                           if [ $? -ne 0 ]; then echo "MD5 FAIL: $file"; fi;
                       done;
                   fi' >> /tmp/glfs_test_${host}.log

        grep FAIL /tmp/glfs_test_${host}.log
        if [ $? -eq 0 ]; then
            notify "MD5 SUM Failure in $brick on $host"
        fi
    done
done

# validate that all files were present during comparison
for host in $HOSTS; do
    log="/tmp/glfs_test_${host}.log"
    num=`grep FILE $log |wc | awk '{print $1}'`
    if [ $COUNT -ne $num ]; then
        notify "FAIL: not all files found in $log: ${num} of ${COUNT}"
    fi
    dprint "Validated $log: $num files found of $COUNT"
done

# cleanup
dprint "Cleaning up test directory"
timeout -k 1s ${TIMEOUT}s rm -rf ${TEST_PATH}
if [ $? -ne 0 ]; then
    notify "Failed to remove test directory within ${TIMEOUT}s"
fi

# umount gluster
if [ "$OPTION" == "mount" ]; then
    dprint "Unmounting gluster filesystem at ${TEST_MOUNT} w/ ${TIMEOUT}s timeout"
    timeout -k 1s ${TIMEOUT}s umount ${TEST_MOUNT}
    if [ "$?" -ne 0 ]; then
        notify "Failed to unmount storage at ${TEST_MOUNT}"
    fi

    if [ -d "$TEST_PATH" ]; then
        notify "Mount still exists.  Failed to unmount storage at ${TEST_MOUNT}"
    fi
fi
