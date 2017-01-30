#!/bin/bash

################################################################################
# LICENSE
################################################################################
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the
# Free Software Foundation, Inc.,
# 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
################################################################################

################################################################################
# ABOUT
################################################################################
#
# Author: John Hobbs
# Home: http://www.velvetcache.org/
#
# This is a script to cross load subversion repositories (kind of) keeping history
# intact without access to svnadmin.  Import into a FRESH repository only, and
# be sure to do a comprehensive diff at the end.
#
# Also be sure to do this in an empty directory. Temp files get added and removed
# without sincere thought put into them.
#
# Log messages get eaten and re-inserted as shown below. Edit to taste.
#   $ svn log -r 1
#   ------------------------------------------------------------------------
#   r1 | jmhobbs | 2008-11-12 18:19:43 -0600 (Wed, 12 Nov 2008) | 7 lines
#
#   Imported from file:///srv/svn/scs using svncrossload
#
#     |r1 | jmhobbs | 2008-10-27 17:32:44 -0500 (Mon, 27 Oct 2008) | 2 lines
#     |
#     |Initial import.
#     |
#
#   ------------------------------------------------------------------------
#   $

usage()
{
		echo "$0 -- cross load subversion repos, preserving history"
		echo
		echo " $0 [-s|--source-repo] SRC_URL    [-d|--dest-repo] DST_URI"
		echo
		echo "          Options:"
		echo "                       --source-username  username"
		echo "                       --dest-username  username"
		echo "                       [-r|--rev-start] StartingRevision"
		echo "                       [-R|--rev-end] EndingRevision"
		echo
		echo $*
		exit 1
}

while [ "X$1" != "X" ]
do
	case $1 in
			-s|--source-repo)
					shift
					SRC=$1
					shift
					;;

			-d|--dest-repo)
					shift
					DST=$1
					shift
					;;

			-r|--rev-start)
					shift
					REV_START=$1
					shift
					;;

			-R|--rev-end)
					shift
					REV_END=$1
					shift
					;;

			--source-username)
					shift
					SRC_USERNAME=$1
					shift
					;;

			--dest-username)
					shift
					DST_USERNAME=$1
					shift
					;;

			*)
					usage "Invalid argument: \"$1\""
					exit 1
					;;
	esac
done


if [ "X$SRC" = "X" ] ; then
	usage "Missing source repo URI"
fi
if [ "X$DST" = "X" ] ; then
	usage "Missing destination repo URI"
fi

if [ "X$SRC_USERNAME" != "X" ] ; then
	SRC="$SRC --username $SRC_USERNAME"
fi
if [ "X$DST_USERNAME" != "X" ] ; then
	DST="$DST --username $DST_USERNAME"
fi

if [ "X$REV_START" = "X" ] ; then
	# use the first revision as the end point
	REV_START=$(svn log $SRC |grep "^r[0-9][0-9]*" | tail -1 |sed -e "s/^r//" -e "s/ .*//")
fi

if [ "X$REV_END" = "X" ] ; then
	# use the last revision as the end point
	REV_END=$(svn info $SRC | grep Revision | sed 's/^Revision: *\([0-9]*\)/\1/')
fi
echo "Checking out initial revisions"
svn co $DST importing > /dev/null
svn co -r $REV_START $SRC updateme > /dev/null

if [ ! -d $updateme ] ; then
	mkdir $updateme 
	if [ $? != 0 ] ; then
		echo "Error making temp dir \"updateme\""
		exit 1
	fi
fi

for i in $(seq $REV_START $REV_END); do
  echo -e "\nCopying revision $i"
  
  cd updateme
  svn update -r $i | tee ../_update
  echo -e "Imported from $SRC using svncrossload\n" > ../_log
  # The '\-\-\-\-\...' looks ridiculous, but it works.
  svn log -r $i | grep -v '\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-' | sed 's/\(.*\)/   |\1/'  >> ../_log
  svn log -r $i
  username=$(svn log -r $i | grep -v '\-\-\-\-\-\-\-' | head -n 1 | cut -d\| -f 2 | sed -e 's/^\s\+//' -e 's/\s\+$//')  
  cd ..

  cat _update | grep -E '^A ' | sed 's/^A *//' > _update_add
  cat _update | grep -E '^D ' | sed 's/^D *//' > _update_del
  cat _update | grep -E '^U ' | sed 's/^U *//' > _update_mod

  echo "$(wc -l _update_add | sed 's/^\([0-9]*\).*/\1/') Files To Add"
  echo "$(wc -l _update_mod | sed 's/^\([0-9]*\).*/\1/') Files To Modify"
  echo "$(wc -l _update_del | sed 's/^\([0-9]*\).*/\1/') Files To Delete"

  # Copy
  for j in $(cat _update_add | tr ' ' '@'); do
    if [ -d "updateme/${j//@/ }" ]; then
      mkdir "importing/${j//@/ }"
    else
      cp -f "updateme/${j//@/ }" "importing/${j//@/ }"
    fi
    cd importing
    # We send stderr to null because it warns when we add existing stuff
    svn add "${j//@/ }" 2> /dev/null
    cd ..
  done

  # Modify
  for j in $(cat _update_mod | tr ' ' '@'); do
    if [ -f "updateme/${j//@/ }" ]; then
      cp -f "updateme/${j//@/ }" "importing/${j//@/ }"
    fi
  done

  # Delete
  for j in $(cat _update_del | tr ' ' '@'); do
    cd importing
    svn rm "${j//@/ }"
    cd ..
  done

  echo "Committing"
  cd importing
  if [ "X$DST_USERNAME" = "X" ] ; then
  	username_param=""
  	if [ "x$username" != "x" ]; then
		username_param="--username $username"  
  	fi
  else
	  username_param="--username $DST_USERNAME"
  fi
  svn commit --force-log -F ../_log $username_param
  
  cd ..

done

echo "Cleaning up"
rm -rf importing _log _update _update_add _update_del updateme _update_mod
echo "Done!"
