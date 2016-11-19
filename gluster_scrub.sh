#!/bin/bash

bricks=`ls /glfs`

find_orphan(){
    vols=`ls ${1}`
    for vol in $vols; do
        find ${1}/$vol/.glusterfs -type f -links -2 \
            \( ! -iname "*.db" ! -iname "*.db-*" ! -iname "health_check" \) \
            -print -exec rm {} \;
    done
}

for brick in $bricks; do
    find_orphan $brick &
done
