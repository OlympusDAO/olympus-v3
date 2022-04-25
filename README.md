# Forge Template

A template for quickly getting started with forge.

## Getting Started

If using bash:

```
mkdir my-project
cd my-project
forge init --template https://github.com/OlympusDAO/forge-template
yarn build
yarn test
```

Otherwise replace `yarn build` with:

```
git submodule update --init --recursive  ## initialize submodule dependencies
npm install ## install development dependencies
forge build
```

## Features

### Preinstalled dependencies

`ds-test` for testing, `test-utils` for more test utils, `forge-std` for better cheatcode UX, and `solmate` for optimized contract implementations.

### Linting

Pre-configured `solhint` and `prettier-plugin-solidity`. Can be run by

```
yarn run solhint
yarn run prettier
```

### CI with Github Actions

Automatically run linting and tests on pull requests.

### Default Configuration

Including `.gitignore`, `.vscode`, `remappings.txt`

## Acknowledgement

Thanks to [Franke](https://github.com/FrankieIsLost) for the initial template.
