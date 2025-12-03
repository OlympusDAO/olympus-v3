# Convertible Deposits Installation

## Sepolia

1. Deploy ReserveWrapper
   - Deploy via `./shell/deployV3.sh --account OlympusDeployer --sequence src/scripts/deploy/savedDeployments/reserve_wrapper.json --chain sepolia --env .env.sepolia --broadcast true --verify true`.

2. Deploy ConvertibleDeposits
   - Run `./shell/deployV3.sh --account OlympusDeployer --sequence src/scripts/deploy/savedDeployments/convertible_deposit.json --chain sepolia --env .env.sepolia --broadcast true --verify true`.

3. Install Modules and Policies
   - Execute `./shell/safeBatchV2.sh --contract ConvertibleDepositInstall --function install --chain sepolia --account OlympusDeployer --broadcast true`.
   - Verify the batch installs the modules and activates the policy.

4. Configure EmissionManager Roles
   - Execute `./shell/safeBatchV2.sh --contract ConvertibleDepositInstall --function configureEmissionManagerRoles --chain sepolia --account OlympusDeployer --broadcast true`.

5. Configure ConvertibleDeposit Roles
   - Execute `./shell/safeBatchV2.sh --contract ConvertibleDepositInstall --function grantConvertibleDepositRoles --chain sepolia --account OlympusDeployer --broadcast true`.
   - Confirm the kernel roles are granted as expected.

6. Run Activator Script
   - Execute `./shell/safeBatchV2.sh --contract ConvertibleDepositInstall --function runActivator --chain sepolia --account OlympusDeployer --broadcast true`.
