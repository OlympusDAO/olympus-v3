#!/bin/bash

if [[ "$1" == "--versioned" ]]; then
    CONTRACT_NAME="$2"

    # Foundry omits the profile suffix for default compiler settings, so prefer that artifact.
    for INCLUDE_PROFILE in false true; do
        for FOLDER in ./out/*; do
            for FILE in "$FOLDER"/*; do
                [[ -f "$FILE" ]] || continue

                NAME=$(basename "$FILE")
                if [[ "$INCLUDE_PROFILE" == "false" ]]; then
                    [[ "$NAME" =~ ^${CONTRACT_NAME}\.[0-9]+\.[0-9]+\.[0-9]+\.json$ ]] || continue
                else
                    # Additional compiler profiles may omit the compiler-version segment.
                    [[ "$NAME" =~ ^${CONTRACT_NAME}(\.[0-9]+\.[0-9]+\.[0-9]+)?\..+\.json$ ]] || continue
                fi

                cast abi-encode "result(string)" "$FILE"
                exit 0
            done
        done
    done

    exit 0
fi

for FOLDER in ./out/*; do
    for FILE in "$FOLDER"/*; do
        [[ -f "$FILE" ]] || continue

        NAME=$(basename "$FILE")
        if [[ "$NAME" == "$1" ]]; then
            cast abi-encode "result(string)" "$FILE"
            exit 0
        fi
    done
done
