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
4. Use `.env.example` as the template for `.env` and set the variables required by your deployment and verification providers.
5. Run `shell/deploy.sh --sequence $DEPLOY_FILE_PATH` to run the deployment shell script. E.g. `shell/deploy.sh --sequence src/scripts/deploy/savedDeployments/rbs_v1_3.json`
    - If you want to broadcast the tx to the network, append `--broadcast true` to the command.
    - If you want to verify the contracts, append `--verify true` to the command.
    - If you want to resume a failed deployment, append `--resume true` to the command.
    - If you want to use a different environment file (for example, one per chain), append `--env <.env file>` to the command.
6. After a successful deployment, update `src/scripts/env.json` with the new contract addresses.
7. Finally, use [olymsig](https://github.com/OlympusDAO/olymsig) (or [olymsig-testnet](https://github.com/OlympusDAO/olymsig-testnet) if testing the deployment) to plug the newly deployed contracts into `olympus-v3`.

## Verification

`shell/deploy.sh` and `shell/deployV3.sh` verify with **Etherscan, Sourcify and Blockscout** when `--verify true` is passed.
`shell/L2/deploy.sh` verifies during deployment with Etherscan only, using `ETHERSCAN_KEY` (or a custom verifier at `VERIFIER_URL`).
Set `ETHERSCAN_API_KEY` in the environment or deployment env file. The legacy `ETHERSCAN_KEY` name is also accepted.
Use `--verifier etherscan`, `--verifier sourcify`, or `--verifier blockscout` to select one provider.
The default is `all`; `--verifier both` selects only Etherscan and Sourcify.
Sourcify-only verification requires no Etherscan API key.

Blockscout verification requires `BLOCKSCOUT_API_KEY` from [the Blockscout developer portal](https://dev.blockscout.com).
The wrappers use `https://api.blockscout.com/v2/api?chain_id=<chain-id>` so verification does not depend on the explorer site's Cloudflare challenge.
The Blockscout call uses its own key; the Etherscan call retains its original key. Blockscout-only verification requires no Etherscan key.
Missing required keys stop the wrapper before deployment. See [Blockscout's Forge instructions](https://docs.blockscout.com/devs/verification/foundry-verification).

Verification runs from saved receipts after deployment succeeds. Every selected provider is attempted even if one fails.
The command exits nonzero if any selected provider fails, while retaining the deployment records.
Retry the failed provider with the original command plus `--resume true --verify true --verifier <provider>`.
Resume uses the saved deployment; confirmed transactions are not sent again.

The wrappers pass the RPC chain ID and use Foundry's explorer configuration.
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
