#!/bin/bash
FILE="$1"

hidden_file_path=$(getfattr -m gfid -d -e hex "$FILE" | sed -n '2s/.*0x\(..\)\(..\)\(....\)\(....\)\(....\)\(....\)\(............\)/\1\/\2\/\1\2\3-\4-\5-\6-\7/p')

NOOP=$2

if [ "x$NOOP" = "x" ] ; then
  rm -v .glusterfs/$hidden_file_path "$FILE"
else
  echo "Would remove the following:"
  echo .glusterfs/$hidden_file_path
  echo "$FILE"
fi
