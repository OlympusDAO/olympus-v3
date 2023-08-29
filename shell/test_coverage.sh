#!/bin/sh

# Run the tests
# Prints the summary to the CLI and generates the lcov.info file
echo "Running code coverage"
forge coverage --ir-minimum --report lcov --report summary

# Exclude libraries, tests and scripts from the output
echo "Removing unnecessary files from lcov.info"
lcov --output-file lcov.info --ignore-errors unused --remove lcov.info 'src/test/**/*.sol' --remove lcov.info 'src/scripts/**/*.sol' --remove lcov.info 'src/external/**/*.sol' --remove lcov.info 'src/libraries/**/*.sol' --remove lcov.info 'lib/**/*.sol'

# Generate the code coverage report
echo "Generating code coverage report"
genhtml --output-directory coverage lcov.info
