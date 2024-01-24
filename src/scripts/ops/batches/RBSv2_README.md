# Activation Scripts for RBS v2

## Launch Stages

Deploying and activating RBS v2 will happen in three stages:

1. TRSRY v1.1

    - Installation and activation of TRSRY v1.1 module and TreasuryConfig policy
    - The balances will not be used by other components of Bophades at this stage
    - It offers the opportunity to ensure that balances are correct

2. SPPLY

    - Installation and activation of SPPLY module, SPPLY submodules
      and SupplyConfig policy
    - Installation and activation of the CrossChainBridge v1.1 policy
      (with support for tracking cross-chain supply in SPPLY)
    - Categorises additional supply locations

3. PRICE v2 & RBS v2
    - Installation and activation of PRICE v2 module, PRICE submodules,
      PriceConfig policy, BunniManager policy and the RBS v2 policies
      (Operator, Heart, Appraiser)
    - Configuration of price feeds
    - Migration of Uniswap V3 POL to be owned by the BunniManager policy
    - Activation of RBS v2

## Testing

Prior to launch, developers may wish to conduct testing of the deployment
and activation of the entire RBS v2 stack. The only way to do this is with
a persistent fork, such as with Anvil or Tenderly (recommended).

### Fork Setup

1. On the Tenderly dashboard, create a mainnet fork and copy the RPC url.
2. Ensure that your `.env` file is populated with the required variables.

### Deployment

1. TRSRY
    - `RPC_URL=<RPC_URL> ./shell/deploy.sh src/scripts/deploy/savedDeployments/rbs-v2/rbs_v2_1_trsry.json true`
    - Update the deployment addresses in `src/scripts/env.json`
2. SPPLY
    - `RPC_URL=<RPC_URL> ./shell/deploy.sh src/scripts/deploy/savedDeployments/rbs-v2/rbs_v2_2_spply.json true`
    - Update the deployment addresses in `src/scripts/env.json`
3. PRICE v2 & RBS v2
    - `RPC_URL=<RPC_URL> ./shell/deploy.sh src/scripts/deploy/savedDeployments/rbs-v2/rbs_v2_3_rbs.json true`
    - Update the deployment addresses in `src/scripts/env.json`

Notes:

-   Replace `<RPC_URL>` in the above commands with your Tenderly fork URL.
-   The final argument (`true`) results in the deployment being broadcast to the
    fork. You can set this to `false` if you want to verify it beforehand.

### Activation

The `OlyBatch` scripts and simulation feature have been essential in testing
activation on the fork.

NOTE: As the scripts submit batches to the Safe API for inclusion in a wallet,
it isn't possible to broadcast/publish the batches to a fork.

1. TRSRY
    - `RPC_URL=<RPC_URL> src/scripts/ops/batch.sh RBSv2Install_1_TRSRY RBSv2Install_1_1 false`
    - As this script does not rely on other components of the RBS v2 launch,
      it should work fine
2. SPPLY
    - `RPC_URL=<RPC_URL> src/scripts/ops/batch.sh RBSv2Install_2_SPPLY RBSv2Install_2_1 false`
    - As this script does not rely on other components of the RBS v2 launch,
      it should work fine
3. PRICE v2 & RBS v2
    - As the RBS v2 script relies on TRSRY and SPPLY already being activated,
      this is slightly more complicated.
    - In `src/scripts/ops/batches/RBSv2Install_3_RBS.sol`, uncomment the line
      calling the `_bunniManagerTestSetup()` function. This will set up
      TRSRY and SPPLY in the bare minimum.
    - `RPC_URL=<RPC_URL> src/scripts/ops/batch.sh RBSv2Install_3_RBS RBSv2Install_3_1 false`

Notes:

-   Replace `<RPC_URL>` in the above commands with your Tenderly fork URL.
-   The final argument (`false`) results in the activation NOT being broadcast
    to the fork. Leave it as-is.

## Production

The steps followed in the [Testing](#testing) section can be followed, except
that the activation scripts will be called with a final argument of `true` to
result in broadcasting of the batches to the Safe API.

After each batch is published, it will need to be signed and executed by
the DAO MS.
