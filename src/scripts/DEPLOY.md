# Deployment Instructions - Mainnet

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

`shell/deploy.sh`, `shell/deployV3.sh`, and `shell/L2/deploy.sh` verify with **Etherscan and Sourcify** when `--verify true` is passed.
Set `ETHERSCAN_API_KEY` in the environment or deployment env file. The legacy `ETHERSCAN_KEY` name is also accepted.
Use `--verifier etherscan` or `--verifier sourcify` to select one provider; the default is `both`.
Sourcify-only verification requires no Etherscan API key.

Verification runs from saved receipts after deployment succeeds. Both providers are attempted even if one fails.
The command exits nonzero if either provider fails, while retaining the deployment records.
Retry the failed provider with the original command plus `--resume true --verify true --verifier <provider>`.
Resume uses the saved deployment; confirmed transactions are not sent again.

Etherscan uses the explicit V2 endpoint and RPC chain ID, including Robinhood (4663).
See [Etherscan's custom-chain instructions](https://docs.etherscan.io/contract-verification/verify-with-foundry#custom-chains).

### Manual Verification

To verify one contract on Sourcify, use the original deployment profile and contract source:

```bash
FOUNDRY_PROFILE=deploy forge verify-contract \
    <contract-address> <source-path:contract-name> \
    --chain <chain-id> --verifier sourcify --watch
```

Keep the original compiler settings and source files.
For individual Etherscan verification, `shell/verify_etherscan.sh` remains available and requires an API key.
