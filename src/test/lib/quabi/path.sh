#!/bin/bash

for FOLDER in ./out/*; do
    for FILE in $FOLDER/*; do
        NAME=$(basename $FILE)
        if [ $NAME == $1 ]
        then
            cast abi-encode "result(string)" $FILE
            FOUND=1
            break
        fi
    done
    if [ $FOUND ]
    then
        break
    fi
done