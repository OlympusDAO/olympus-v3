# Scoped Solidity nSLOC reports

The metrics command generates a standalone HTML report for an explicit set of Solidity files.
SCC counts the files and generates the report. A Solidity parser identifies function headers.

## Dependencies

- Node.js 24 or newer.
- The pnpm version in `package.json`.
- **SCC 4.1.0**, installed separately from pnpm.

The repository includes an SCC version pin in `mise.toml`.
If you use mise, install SCC with:

```sh
mise trust
mise install
```

Then run metrics commands through `mise exec --` to select that SCC version.
You can also install SCC from its [official releases](https://github.com/boyter/scc/releases/tag/v4.1.0)
and put its executable on `PATH`.
pnpm installs the Solidity parser. It does not install SCC.

## Select the scope

Run these commands from the repository root.
Pass explicit file paths or quoted globs:

```sh
mise exec -- pnpm metrics 'src/policies/price/*.sol' src/libraries/FullMath.sol
```

For a repeatable audit scope, create a text file with one repository-relative path per line.
Blank lines and lines that start with `#` are ignored.
For example:

```text
# Files in scope
src/Kernel.sol
src/policies/cooler/MonoCooler.sol
src/libraries/FullMath.sol
```

Pass that file with `--scope`:

```sh
mise exec -- pnpm metrics --scope audit/example/scope.txt --output audit/example/solidity-metrics.html
```

You can combine a scope file with file arguments and repeat `--exclude`:

```sh
mise exec -- pnpm metrics 'src/policies/price/*.sol' --exclude '**/*Factory.sol'
```

The command counts each selected file once. It does not follow imports or add dependencies.
Interfaces and libraries count when you include them. There are no implicit source exclusions.
An unmatched input, invalid Solidity, or an empty final scope causes an error.
Failed generation preserves an existing report.

The default output is `solidity-metrics.html` in the current directory.
The report lists the exact files that SCC counted.

## Counting method

The adapter creates temporary copies and normalizes each actual `function` declaration to one line.
This includes declarations in interfaces. Function bodies retain their original line breaks.
Constructors, modifiers, and function types retain their original formatting.
The parser prevents text inside strings or comments from becoming a function header.

SCC excludes blank lines and comment-only lines from its code count.
The report labels these normalized counts as **SLOC** or **Code**. They represent nSLOC for this workflow.
Other figures in the report also describe the normalized copies.
The adapter removes the temporary copies after generation. It never changes repository source files.

The old generator used a regular expression that could consume strings and multiple interface declarations.
Counts can differ where the new method corrects those errors.
Historical HTML reports remain unchanged.

## Validation

Run the focused CLI tests with the pinned SCC version:

```sh
mise exec -- pnpm run test:metrics
```
