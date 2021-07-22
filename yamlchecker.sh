#!/bin/bash
# Created by @srepac
#
# Quick and dirty script to check yaml file for:
#
# 1.  spacing errors in yaml file   7/11/21
# 2.  duplicate top-level and first-level indent entries  7/12/21
#
usage() {
        echo "usage:  $0 <yamlfilename>"
        exit 1
}

if [[ "$1" == "" || "$1" == "-help" || "$1" == "--help" ]]; then
        usage
fi

FILETOCHECK="$1"
if [[ ! -e $FILETOCHECK ]]; then
        echo "File to check does not exist."
        usage
fi

count=0

ERRORS=$( egrep -vn "^    [a-z#]|^        [a-z]*|^#|^[a-z]|^$" $FILETOCHECK )

errcount=$( egrep -vn "^    [a-z#]|^        [a-z]*|^#|^[a-z]|^$" $FILETOCHECK | wc -l )
if [[ $errcount -gt 0 ]]; then
        let count=count+1
        echo "-> $errors Spacing errors found at line numbers below:"
        echo
        echo "$ERRORS"
        echo
        echo "*** HINT:  Use 4 spaces for each indent.  DO NOT use TABS ***"
        echo
fi

# check top-level for duplicate entries (another major cause of errors)
for i in $( awk -F':' '{print $1}' $FILETOCHECK | grep -v '^#' | grep -v '-' | grep '^[a-z]' | sort -u ); do
        if [[ $( grep -w ^${i}: $FILETOCHECK | wc -l ) -gt 1 ]]; then
                let count=count+1
                echo "Remove top-level duplicate entries for '${i}:' at following lines below:"
                grep -n ^${i}: $FILETOCHECK
                echo
        fi
done

# check first level indent for duplicate entries (another major cause of errors)
for i in $( awk -F':' '{print $1}' $FILETOCHECK | grep -v '^#' | grep -v '-' | grep '^    [a-z]' | sort -u ); do
        if [[ $( grep -w "^    ${i}:" $FILETOCHECK | wc -l ) -gt 1 ]]; then
                let count=count+1
                echo "Remove first-level duplicate entries for '    ${i}:' at following lines below:"
                grep -n "^    ${i}:" $FILETOCHECK
                echo
        fi
done

if [[ $count -gt 0 ]]; then
        echo "*** Please fix all the errors found above. ***"
else
        echo "No spacing errors found."
        echo "No top-level and first-level indent duplicate entries found."
fi
