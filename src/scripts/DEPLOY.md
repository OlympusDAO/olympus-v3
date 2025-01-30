# Mainnet Deployment Instructions

## Deployment

1. Update the solidity deployment script `src/scripts/deployment/DeployV2.sol`.
    - If necessary, add external dependencies (e.g. `sdai = ERC20(envAddress("external.tokens.sDAI"));`)
    - Create a function to handle the deployment of the new contracts (e.g. `_deployBLVaultLusd()`)
    - Add the new contracts to the `selectorMap` with their corresponding keys.
2. Create a deployment sequence file using one of the existing sequence files as a template: `src/scripts/deploy/savedDeployments/`
    - Use the corresponding keys for the selectorMap in `#1.3`.
    - Use any necessary configuration parameters.
    - Create a copy the file under `src/scripts/deploy/savedDeployments/` and give it a name that makes sense.
3. If external dependencies are required, add them in `src/scripts/env.json`, so that they can be used in `DeployV2.sol`.
4. If necessary, update your `.env` file. It should, at least, have the same variables as in `.env.deploy.example`.
5. Run `shell/deploy.sh --sequence $DEPLOY_FILE_PATH` to run the deployment shell script. E.g. `shell/deploy.sh --sequence src/scripts/deploy/savedDeployments/rbs_v1_3.json`
    - If you want to broadcast the tx to the network, append `--broadcast true` to the command.
    - If you want to verify the contracts, append `--verify true` to the command.
    - If you want to resume a failed deployment, append `--resume true` to the command.
    - If you want to use a different environment file (for example, one per chain), append `--env <.env file>` to the command.
6. After a successful deployment, update `src/scripts/env.json` with the new contract addresses.
7. Finally, use [olymsig](https://github.com/OlympusDAO/olymsig) (or [olymsig-testnet](https://github.com/OlympusDAO/olymsig-testnet) if testing the deployment) to plug the newly deployed contracts into `olympus-v3`.

## Verification

Verification is handled automatically by the `deploy.sh` script, as long as the `--verify true` flag is passed.

### Manual Verification

Sometimes the automatic etherscan verification fails when deploying a contract. If that's the case, follow the these steps to verify existing contracts:

1. Execute the `shell/verify_etherscan.sh` script with the following arguments:

    - `CONTRACT_ADDRESS`: Address of the target contract to be verified.
    - `CONTRACT_PATH`: Relative path to the target contract.
    - `CONSTRUCTOR_ARGS`: Calldata of the constructor args. The preferred method is to manually encode the data, but `cast abi-encode "constructor(args)" "values"` can also be used.

2. This is an example execution of the shell script:

    ```shell
    shell/verify_etherscan.sh 0x0AE561226896dA978EaDA0Bec4a7d3CfAE04f506 src/policies/Operator.sol:Operator 0x0000000000000000000000002286d7f9639e8158fad1169e76d1fbc38247f54b000000000000000000000000007f7a1cb838a872515c8ebd16be4b14ef43a22200000000000000000000000073df08ce9dcc8d74d22f23282c4d49f13b4c795e00000000000000000000000064aa3364f17a4d01c6f1751fd97c2bd3d7e7f1d50000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea0000000000000000000000000000000000000000000000000000000000000bb8000000000000000000000000000000000000000000000000000000000003f48000000000000000000000000000000000000000000000000000000000000186a0000000000000000000000000000000000000000000000000000000000000384000000000000000000000000000000000000000000000000000000000000003e8000000000000000000000000000000000000000000000000000000000007e90000000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000015
    ```

    Where the `CONSTRUCTOR_ARGS` have been decode in the following way:

    ```hex
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
