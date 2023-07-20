# Load environment variables
source .env

# Verify modules and policies were correctly installed
forge script ./src/scripts/deploy/DeployV2.sol:OlympusDeploy --sig "verifyKernelInstallation()()" --rpc-url $RPC_URL --slow -vvv