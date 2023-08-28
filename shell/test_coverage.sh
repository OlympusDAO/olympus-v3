#!/bin/sh

# Run the tests
# Prints the summary to the CLI and generates the lcov.info file
forge coverage --ir-minimum --report lcov --report summary

# Exclude libraries, tests and scripts from the output
lcov -o lcov.info --remove lcov.info 'src/test/' --remove lcov.info 'src/scripts/' --remove lcov.info 'src/external/' --remove lcov.info 'src/libraries' --remove lcov.info 'lib/'

# Generate the code coverage report
genhtml --output-directory coverage lcov.info
