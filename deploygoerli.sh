# Load .env
source .env

# Deploy Authority
forge script script/v2/DeployGdaoAuthority.s.sol:AuthorityDeploy --rpc-url ${GOERLI_INFURA}
forge script script/v2/DeployGdaoAuthority.s.sol:AuthorityDeploy  --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# Deploy GDAO - use authority, store kernel address
forge script script/DeployGDAO.s.sol:GdaoDeploy --rpc-url ${GOERLI_INFURA}
forge script script/DeployGDAO.s.sol:GdaoDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# Deploy sGDAO 
forge script script/v2/DeploysGDAO.s.sol:sGdaoDeploy --rpc-url ${GOERLI_INFURA}
forge script script/v2/DeploysGDAO.s.sol:sGdaoDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# Deploy Migrator - optional?
forge script script/v2/DeployMigrator.s.sol:MigratorDeploy --rpc-url ${GOERLI_INFURA}
forge script script/v2/DeployMigrator.s.sol:MigratorDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# Deploy xGDAO  - update sGDAO x2 
forge script script/v2/DeployxGDAO.s.sol:xGdaoDeploy --rpc-url ${GOERLI_INFURA}
forge script script/v2/DeployxGDAO.s.sol:xGdaoDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# Deploy GDAOStaking - update gdao, sgdao, xgdao, timestamp
forge script script/v2/DeployGoerliStaking.s.sol:GDAOStakingDeploy --rpc-url ${GOERLI_INFURA}
forge script script/v2/DeployGoerliStaking.s.sol:GDAOStakingDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# V2
# Deploy Kernel - update gdao
forge script script/DeployKernel.s.sol:KernelDeploy --rpc-url ${GOERLI_INFURA}
forge script script/DeployKernel.s.sol:KernelDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# -> sGDAO - setIndex, xgdao, initialize

# Update Roles Admin
forge script script/v2/DeployRoles.s.sol:RolesDeploy --rpc-url ${GOERLI_INFURA}
forge script script/v2/DeployRoles.s.sol:RolesDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv
# External
# # Deploy TGD - use authority, store kernel address
# forge script script/DeployTGD.s.sol:TgdDeploy --rpc-url ${GOERLI_INFURA}
# forge script script/DeployTGD.s.sol:TgdDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# Deploy Treasury
forge script script/modules/DeployTreasury.s.sol:DeployTreasury --rpc-url ${GOERLI_INFURA}
forge script script/modules/DeployTreasury.s.sol:DeployTreasury --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# Deploy Bonding Calc?

# Deploy Distributor - update in staking address
forge script script/policies/DeployDistributor.s.sol:DeployDistributor --rpc-url ${GOERLI_INFURA}
forge script script/policies/DeployDistributor.s.sol:DeployDistributor --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# Deploy Forwarder Contract
forge script script/DeployForwarder.s.sol:ForwarderDeploy --rpc-url ${GOERLI_INFURA}
forge script script/DeployForwarder.s.sol:ForwarderDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv
