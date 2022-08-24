#!/bin/sh
# Range simulation - Creates and runs simulations for the provided input files (in/params.json and in/netflows.json). Results are generated are saved in the output folder.
source .env

# 1. Generate simulation test files for provided seeds
sh ./src/test/sim/shell/generator.sh

# 2. Run the simulations and store results
forge test --match-path ./src/test/sim/sims/*.t.sol -vvv

# 3. Compile results into single file and delete the individual results files
# FILES=$(find ./src/test/sim/out/ -name "*.json")
# RESULTS=$(jq -c '[inputs.[] | . ]' $FILES)
# rm ./src/test/sim/out/*.json
# echo $RESULTS > ./src/test/sim/out/results.json