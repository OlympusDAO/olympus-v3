# Load .env
source .env

# Deploy Authority - DONE
# forge script script/v2/DeployGdaoAuthority.s.sol:AuthorityDeploy --rpc-url ${GOERLI_INFURA}
# forge script script/v2/DeployGdaoAuthority.s.sol:AuthorityDeploy  --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# Deploy V2
forge script script/v2/DeployV2.s.sol:V2Deploy --rpc-url ${GOERLI_INFURA}
forge script script/v2/DeployV2.s.sol:V2Deploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv


# Deploy GDAO - use authority, store kernel address
# forge script script/DeployGDAO.s.sol:GdaoDeploy --rpc-url ${GOERLI_INFURA}
# forge script script/DeployGDAO.s.sol:GdaoDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# Deploy sGDAO 
# forge script script/v2/DeploysGDAO.s.sol:sGdaoDeploy --rpc-url ${GOERLI_INFURA}
# forge script script/v2/DeploysGDAO.s.sol:sGdaoDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# Deploy Migrator - optional?
# forge script script/v2/DeployMigrator.s.sol:MigratorDeploy --rpc-url ${GOERLI_INFURA}
# forge script script/v2/DeployMigrator.s.sol:MigratorDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# Deploy xGDAO  - update sGDAO x2 
# forge script script/v2/DeployxGDAO.s.sol:xGdaoDeploy --rpc-url ${GOERLI_INFURA}
# forge script script/v2/DeployxGDAO.s.sol:xGdaoDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# Deploy GDAOStaking - update gdao, sgdao, xgdao, timestamp
# forge script script/v2/DeployGoerliStaking.s.sol:GDAOStakingDeploy --rpc-url ${GOERLI_INFURA}
# forge script script/v2/DeployGoerliStaking.s.sol:GDAOStakingDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# UPDATE ENV and run source .env

# Deploy Fixed GDAOStaking - update gdao, sgdao, xgdao, timestamp
forge script script/v2/DeployFixedStaking.s.sol:GDAOFixedStakingDeploy --rpc-url ${GOERLI_INFURA}
forge script script/v2/DeployFixedStaking.s.sol:GDAOFixedStakingDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# UPDATE ENV and run source .env
# V2
# Deploy Kernel - update gdao / staking / etc.
forge script script/DeployKernel.s.sol:KernelDeploy --rpc-url ${GOERLI_INFURA}
forge script script/DeployKernel.s.sol:KernelDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# -> sGDAO - setIndex, xgdao, initialize

# Update Roles Admin
# forge script script/v2/DeployRoles.s.sol:RolesDeploy --rpc-url ${GOERLI_INFURA}
# forge script script/v2/DeployRoles.s.sol:RolesDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv
# External
# # Deploy TGD - use authority, store kernel address
# forge script script/DeployTGD.s.sol:TgdDeploy --rpc-url ${GOERLI_INFURA}
# forge script script/DeployTGD.s.sol:TgdDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# Deploy Treasury
# forge script script/modules/DeployTreasury.s.sol:DeployTreasury --rpc-url ${GOERLI_INFURA}
# forge script script/modules/DeployTreasury.s.sol:DeployTreasury --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# Deploy Bonding Calc?

# run source .env

# Deploy Stakin Config
forge script script/v2/DeployStakingConfig.s.sol:ConfigureGDAOStaking --rpc-url ${GOERLI_INFURA}
forge script script/v2/DeployStakingConfig.s.sol:ConfigureGDAOStaking --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv


# Deploy Stakin Config Pt 2 (after the first epoch ends)
forge script script/v2/DeployStakingPt2.s.sol:GDAOStakingConfigPt2 --rpc-url ${GOERLI_INFURA}
forge script script/v2/DeployStakingPt2.s.sol:GDAOStakingConfigPt2 --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv


# Deploy Stakin Config Pt 2 (after the first epoch ends)
forge script script/v2/DeployStakingTest.s.sol:StakingTestDeploy --rpc-url ${GOERLI_INFURA}
forge script script/v2/DeployStakingTest.s.sol:StakingTestDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# Deploy Forwarder Contract
forge script script/DeployForwarder.s.sol:ForwarderDeploy --rpc-url ${GOERLI_INFURA}
forge script script/DeployForwarder.s.sol:ForwarderDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv
