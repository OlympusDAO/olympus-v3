# Deployment Instructions
1. Update the solidity deployment script `src/scripts/deployment/DeployV2.sol`.
  - If necessary, add external dependencies (e.g. `sdai = ERC20(envAddress("external.tokens.sDAI"));`)
  - Create a function to handle the deployment of the new contracts (e.g. `_deployBLVaultLusd()`)
  - Add the new contracts to the selectorMap with their corresponding keys.
2. Update the configuration-input JSON file `src/scripts/deployment/deploy.json`
  - Use the corresponding keys for the selectorMap in `#1.3`.
  - Use any necessary configuration parameters.
  - Create a copy the file under `src/scripts/deploy/savedDeployments/` and give it the same name as internal function created in `#1.2`.
3. If external dependencies are required, add them in `src/scripts/env.json`, so that they can be used in `DeployV2.sol`.
4. If necessary, update your `.env` file. It should, at least, have the same variables as in `.env.deploy.example`.
5. Run `./src/scripts/deploy/deployV2.sh` to run the deployment shell script.
 - If you want to broadcast the tx to the network, uncomment the last line.
6. After a successful deployment, update `src/scripts/env.json` with the new contract addresses.

# DeployV2 Instructions for CrossChain

- Need to deploy OHM token separately.
- `env.json` is a dependency file.
- Within `env.json`, make new top-level structure for arbitrum.
- Change `deploy.json` to list only contracts to deploy.
- Make a separate `deploy.json` for mainnet for bridge and one with kernel, minter, and bridge for L2s.
