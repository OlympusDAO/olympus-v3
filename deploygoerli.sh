# Load .env
source .env

# Mocks

# V2
# Deploy Kernel
forge script script/Deploy.s.sol:KernelDeploy --rpc-url ${GOERLI_INFURA}
forge script script/Deploy.s.sol:KernelDeploy --rpc-url ${GOERLI_INFURA} --private-key ${PRIV_KEY} --broadcast --optimize --optimizer-runs 20000 -vvvv

# Deploy Authority
forge script script/v2/DeployGdaoAuthority.s.sol:AuthorityDeploy --rpc-url ${GOERLI_INFURA}
forge script script/v2/DeployGdaoAuthority.s.sol:AuthorityDeploy --broadcast --rpc-url ${GOERLI_INFURA}

# External
# Deploy GDAO - use authority, store kernel address
forge script script/DeployGDAO.s.sol:GdaoDeploy --rpc-url ${GOERLI_INFURA}
forge script script/DeployGDAO.s.sol:GdaoDeploy --broadcast --rpc-url ${GOERLI_INFURA} --optimize --optimizer-runs 20000 -vvvv


# Kernel

# Authority

# Modules

# Policies

