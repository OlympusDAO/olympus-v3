# Load .env
source .env

# Deploy V2
forge script script/v2/DeployV2.s.sol:V2Deploy --rpc-url ${GOERLI_INFURA}
forge script script/v2/DeployV2.s.sol:V2Deploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# UPDATE ENV (GDAO, SGDAO, XGDAO, Authority) and run source .env

# Deploy Fixed GDAOStaking - update gdao, sgdao, xgdao, timestamp
forge script script/v2/DeployFixedStaking.s.sol:GDAOFixedStakingDeploy --rpc-url ${GOERLI_INFURA}
forge script script/v2/DeployFixedStaking.s.sol:GDAOFixedStakingDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# UPDATE ENV and run source .env
# V2
# Deploy Kernel - update gdao / staking / etc.
forge script script/DeployKernel.s.sol:KernelDeploy --rpc-url ${GOERLI_INFURA}
forge script script/DeployKernel.s.sol:KernelDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# -> sGDAO - setIndex, xgdao, initialize

# run source .env

# Deploy Stakin Config
forge script script/v2/DeployStakingConfig.s.sol:ConfigureGDAOStaking --rpc-url ${GOERLI_INFURA}
forge script script/v2/DeployStakingConfig.s.sol:ConfigureGDAOStaking --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# Deploy Stakin Config Pt 2 (after the first epoch ends)
forge script script/v2/DeployStakingPt2.s.sol:GDAOStakingConfigPt2 --rpc-url ${GOERLI_INFURA}
forge script script/v2/DeployStakingPt2.s.sol:GDAOStakingConfigPt2 --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# Deploy Stakin Config Pt 3 (test with diff account - update signing account)
forge script script/v2/DeployStakingTest.s.sol:StakingTestDeploy --rpc-url ${GOERLI_INFURA}
forge script script/v2/DeployStakingTest.s.sol:StakingTestDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# Deploy Forwarder Contract
forge script script/DeployForwarder.s.sol:ForwarderDeploy --rpc-url ${GOERLI_INFURA}
forge script script/DeployForwarder.s.sol:ForwarderDeploy --rpc-url ${GOERLI_INFURA} --etherscan-api-key ${ETHERSCAN_API_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv
