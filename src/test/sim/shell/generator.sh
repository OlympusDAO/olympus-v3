#!/bin/sh
# Simulation test file generator script

# Load environment variables
source .env

# Load the test file template into a variable
BASELINE=$(cat ./src/test/sim/SimTemplate.sol.x)
# Set IFS to empty so that we can use line breaks in the test file template
IFS=' '

# Determine the test files that need to be created by extracting the unique seeds from the params.json file
SEEDS=$(jq -c '[.[] | .seed] | unique' ./src/test/sim/in/params.json)

# Convert the seeds to a shell array
SEEDS=(`echo $SEEDS | tr -d '"[]' | tr ',' ' ' `)

for SEED in ${SEEDS[@]}; do
    # Create a new test file for each seed
    echo "$BASELINE" > ./src/test/sim/sims/seed-$SEED.t.sol
    
    # Edit the baseline with the data for this seed
    sed -i '' -e "s/{SEED}/$SEED/g" ./src/test/sim/sims/seed-$SEED.t.sol

    # Append a test to the file for each key
    for (( k=1; k <= $KEYS; k++)); do
        echo "\n    function test_Seed_${SEED}_Key_${k}() public {\n        simulate($k);\n    }" >> ./src/test/sim/sims/seed-$SEED.t.sol
    done
    # Append a closing bracket to the file
    echo "\n}" >> ./src/test/sim/sims/seed-$SEED.t.sol
done