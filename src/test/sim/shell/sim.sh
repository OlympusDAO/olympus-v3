#!/bin/sh
# Range simulation - Creates and runs simulations for the provided input files (in/params.json and in/netflows.json). Results are generated are saved in the output folder.

# 1. Generate simulation test files for provided seeds
sh ./src/test/sim/generator.sh

# 2. Run the simulations and store results
forge test -ffi --match-path ./src/test/sim/

# 3. Compile results into single file and delete the individual results files
FILES=$(find ./src/test/sim/out/ -name "*.json")
RESULTS=$(jq '[inputs.[]]' FILES)
rm ./src/test/sim/out/*.json
echo $RESULTS > ./src/test/sim/out/results.json