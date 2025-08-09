#!/bin/bash

if [ -n "$1" ] && [ -n "$2" ] 
then
	writefile="$1"
	writestr="$2"
	echo "$writestr" > "$writefile"
else 
	echo "Not a directory or not a string"
	exit 1
fi

exit 0
