# Olympus Bophades

## Development Environment

Use `pnpm run build` to refresh deps.

### Global Dependencies

This requires the following to be installed:

-   jq: `brew install jq`
-   foundry: [instructions](https://book.getfoundry.sh/getting-started/installation)

### Local Dependencies

-   Use `pnpm run build` to install all project dependencies

### Environment Variables

Add `FORK_TEST_RPC_URL`, `ETH_MAINNET_RPC_URL` and `POLYGON_MAINNET_RPC_URL` to the .env file in order to run fork tests

## SRC Directory Structure

```ml
├─ external - "External contracts needed for core functionality"
├─ interfaces - "Standard interfaces"
├─ libraries - "Libraries"
├─ modules - "Default framework modules"
│  ├─ AUTHR
│  ├─ INSTR
│  ├─ MINTR
│  ├─ PRICE
│  ├─ RANGE
│  ├─ TRSRY
│  ├─ BLREG
├─ policies - "Default framework policies"
├─ test - "General test utilities and mocks/larps"
```

### Function Selectors

If the hexadecimal version of a function selector is required (e.g. see `OlympusSupply.sol`), the following Replit can be used to generate it: [https://replit.com/@0xJem/SolidityFunctionSelector?v=1](https://replit.com/@0xJem/SolidityFunctionSelector?v=1)

## Deployments

Up-to-date addresses of all the deployments can be found in:

-   the olymsig repos: [mainnet](https://github.com/OlympusDAO/olymsig) and [testnet](https://github.com/OlympusDAO/olymsig-testnet)
-   [the official docs](https://docs.olympusdao.finance/main/technical/addresses)

#### Privileged Testnet Accounts (Multi-sigs)

-   Executor - 0x84C0C005cF574D0e5C602EA7b366aE9c707381E0
-   Guardian - 0x84C0C005cF574D0e5C602EA7b366aE9c707381E0
-   Policy - 0x3dC18017cf8d8F4219dB7A8B93315fEC2d15B8a7
-   Emergency - 0x3dC18017cf8d8F4219dB7A8B93315fEC2d15B8a7

## Documentation

To generate documentation, run `forge doc`

## Solidity Code Metrics

When preparing the codebase for an audit, it is necessary to generate code metrics.

A script has been prepared to generate the metrics in a relatively easy manner - easier than using the standard CLI or VSCode extension.

Here is an example for the `SPPLY` module:

`pnpm run metrics src/modules/SPPLY/**/*.sol`

The report will be written to `/metrics.html` and can be moved into place after that.

Pass `--exclude=<FILE>` to ignore specific files from the analysis. For example:

`pnpm run metrics --exclude=src/modules/SPPLY/submodules/BunniSupply.sol src/modules/SPPLY/**/*.sol src/scripts/deploy/DeployV2.sol`

## Deployment

### Environment

Copy the `.env.deploy.example` file into one file per chain, e.g. `.env_deploy_goerli` and set the appropriate variables. This chain-specific environment file can then be called during deployment, e.g. `env $(cat .env_deploy_goerli | xargs) PRIVATE_KEY=<PRIVATE KEY> ./shell/deploy.sh`

### Steps

1. Update the solidity deployment script `src/scripts/deployment/DeployV2.sol`.
    - If necessary, add external dependencies (e.g. `sdai = ERC20(envAddress("external.tokens.sDAI"));`)
    - Create a function to handle the deployment of the new contracts (e.g. `_deployBLVaultLusd()`)
    - Add the new contracts to the `selectorMap` with their corresponding keys.
2. Update the configuration-input JSON file `src/scripts/deployment/deploy.json`
    - Use the corresponding keys for the selectorMap in `#1.3`.
    - Use any necessary configuration parameters.
    - Create a copy the file under `src/scripts/deploy/savedDeployments/` and give it the same name as internal function created in `#1.2`.
3. If external dependencies are required, add them in `src/scripts/env.json`, so that they can be used in `DeployV2.sol`.
4. If necessary, update your `.env` file. It should, at least, have the same variables as in `.env.deploy.example`.
5. Run `shell/deploy.sh $DEPLOY_FILE_PATH` to run the deployment shell script (e.g. `shell/deploy.sh src/scripts/deploy/savedDeployments/rbs_v1_3.json`).
    - If you want to broadcast the tx to the network, uncomment the line of the script containing `--broadcast`. Only do so after having tested the deployment.
6. After a successful deployment, update `src/scripts/env.json` with the new contract addresses.
7. Finally, use [olymsig](https://github.com/OlympusDAO/olymsig) (or [olymsig-testnet](https://github.com/OlympusDAO/olymsig-testnet) if testing the deployment) to plug the newly deployed contracts into `olympus-v3`.

## How To Verify

Sometimes the automatic etherscan verification fails when deploying a contract. If that's the case, follow the these steps to verify existing contracts:

1. Execute the `shell/verify_etherscan.sh` script with the following arguments:

    - `CONTRACT_ADDRESS`: Address of the target contract to be verified.
    - `CONTRACT_PATH`: Relative path to the target contract.
    - `CONSTRUCTOR_ARGS`: Calldata of the constructor args. The preferred method is to manually encode the data, but `cast abi-encode "constructor(args)" "values"` can also be used.

2. This is an example execution of the shell script:

    ```
    shell/verify_etherscan.sh 0x0AE561226896dA978EaDA0Bec4a7d3CfAE04f506 src/policies/Operator.sol:Operator 0x0000000000000000000000002286d7f9639e8158fad1169e76d1fbc38247f54b000000000000000000000000007f7a1cb838a872515c8ebd16be4b14ef43a22200000000000000000000000073df08ce9dcc8d74d22f23282c4d49f13b4c795e00000000000000000000000064aa3364f17a4d01c6f1751fd97c2bd3d7e7f1d50000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea0000000000000000000000000000000000000000000000000000000000000bb8000000000000000000000000000000000000000000000000000000000003f48000000000000000000000000000000000000000000000000000000000000186a0000000000000000000000000000000000000000000000000000000000000384000000000000000000000000000000000000000000000000000000000000003e8000000000000000000000000000000000000000000000000000000000007e90000000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000015
    ```

    Where the `CONSTRUCTOR_ARGS` have been decode in the following way:

    ```
    constructor(address,address,address,uint256,uint256[2],uint256[2])"

    0x
    0000000000000000000000002286d7f9639e8158fad1169e76d1fbc38247f54b  # address1
    00000000000000000000000064aa3364f17a4d01c6f1751fd97c2bd3d7e7f1d5  # address2
    0000000000000000000000006b175474e89094c44da98b954eedeac495271d0f  # address3
    0000000000000000000000000000000000000000000000000000000000000064  # uint256
    00000000000000000000000000000000000000000000000000000000000003e8  # array1[0]
    00000000000000000000000000000000000000000000000000000000000007d0  # array1[1]
    00000000000000000000000000000000000000000000000000000000000003e8  # array2[0]
    00000000000000000000000000000000000000000000000000000000000007d0  # array2[1]
    ```

    Remember that you can use `chisel` to easily convert from decimals to hex

## Boosted Liquidity Vault Setup

-   Deploy any dependencies (if on testnet)
-   Deploy BLV contracts
-   Activate BLV contracts with the BLV registry (using an olymsig script)
