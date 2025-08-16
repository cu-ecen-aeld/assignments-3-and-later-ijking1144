#!/bin/sh

if [ -d "$1" ] && [ -n "$2" ]
then
	filesdir="$1"
	searchstr="$2"
	
	X=$(grep -rl $searchstr $filesdir | wc -l)
	Y=$(grep -r $searchstr $filesdir | wc -l)
	echo "The number of files are $X and the number of matching lines are $Y"
else
	echo "Directory invalid or String invalid"
	exit 1
fi

exit 0
