# Deploying on a Testnet

OHM (and associated contracts) may need to be deployed on testnets. If so, this document can help with the steps.

## Deploying OHM

1. Check out the [olympus-contracts](https://github.com/OlympusDAO/olympus-contracts/) repo.
2. In the `olympus-contracts` repo:

    1. Install dependencies: `yarn install`
    2. Compile contracts: `yarn run compile`
    3. Set up the environment (using `.env.sample`)
    4. Ensure that `hardhat.config.ts` has the testnet defined
    5. Run `yarn run deploy:<network>` to deploy
    6. Run `yarn run etherscan:<network>` to verify on Etherscan

3. Record the addresses in `scripts/env.json`

## Deploying Bophades

After this, the Bophades stack can be deployed (e.g. using `shell/L2/deploy.sh`).

Then run `./shell/L2/grantRoles.sh`.

## Minting OHM

Run `./shell/roles/grantRole.sh --role "minter_admin"`.

Run `./shell/mint/mint.sh --category test`.

## Wrapping OHM to gOHM

Run `./shell/mint/stakeToGOhm.sh`.
