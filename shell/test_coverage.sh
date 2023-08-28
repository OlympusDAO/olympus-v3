#!/bin/sh

# Run the tests
# Prints the summary to the CLI and generates the lcov.info file
echo "Running code coverage"
forge coverage --ir-minimum --report lcov --report summary

# Exclude libraries, tests and scripts from the output
echo "Removing unnecessary files from lcov.info"
lcov -o lcov-pruned.info --ignore-errors unused --remove lcov.info 'src/test/' --remove lcov.info 'src/scripts/' --remove lcov.info 'src/external/' --remove lcov.info 'src/libraries' --remove lcov.info 'lib/'

# Generate the code coverage report
echo "Generating code coverage report"
genhtml --output-directory coverage lcov-pruned.info
