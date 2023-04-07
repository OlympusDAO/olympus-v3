# Load .env
source .env

# Deploy Kernel
forge script script/Deploy.s.sol:KernelDeploy --fork-url ${LOCAL_RPC}
forge script script/Deploy.s.sol:KernelDeploy --broadcast --fork-url ${LOCAL_RPC}

# External
# Deploy GDAO - use authority, store kernel address
forge script script/DeployGDAO.s.sol:GdaoDeploy --fork-url ${LOCAL_RPC}
forge script script/DeployGDAO.s.sol:GdaoDeploy --broadcast --fork-url ${LOCAL_RPC}

# Deploy xGDAO
forge script script/v2/DeployxGDAO.s.sol:xGdaoDeploy --fork-url ${LOCAL_RPC}
forge script script/v2/DeployxGDAO.s.sol:xGdaoDeploy --broadcast --fork-url ${LOCAL_RPC}

# Deploy sGDAO 
forge script script/v2/DeploysGDAO.s.sol:sGdaoDeploy --fork-url ${LOCAL_RPC}
forge script script/v2/DeploysGDAO.s.sol:sGdaoDeploy --broadcast --fork-url ${LOCAL_RPC}

# Deploy GDAOStaking
forge script script/v2/DeployGDAOStaking.s.sol:GDAOStakingDeploy --fork-url ${LOCAL_RPC}
forge script script/v2/DeployGDAOStaking.s.sol:GDAOStakingDeploy --broadcast --fork-url ${LOCAL_RPC}
# Modules

# Deploy GDaoInstructions
forge script script/modules/DeployGDaoInstructions.s.sol:GDaoInstrDeploy --fork-url ${LOCAL_RPC}
forge script script/modules/DeployGDaoInstructions.s.sol:GDaoInstrDeploy --broadcast --fork-url ${LOCAL_RPC}

# Deploy Minter
forge script script/modules/DeployMinter.s.sol:DeployMinter --fork-url ${LOCAL_RPC}
forge script script/modules/DeployMinter.s.sol:DeployMinter --broadcast --fork-url ${LOCAL_RPC}

# Deploy MockPriceFeed
forge script script/DeployMockPriceFeed.s.sol:DeployMockPriceFeed --fork-url ${LOCAL_RPC}
forge script script/DeployMockPriceFeed.s.sol:DeployMockPriceFeed --broadcast --fork-url ${LOCAL_RPC}

# Deploy MockOHM (local only)
forge script script/mocks/DeployMockReserve.s.sol:DeployMockReserve --fork-url ${LOCAL_RPC}
forge script script/mocks/DeployMockReserve.s.sol:DeployMockReserve --broadcast --fork-url ${LOCAL_RPC}

# Deploy MockPrice
forge script script/DeployMockPrice.s.sol:DeployMockPrice --fork-url ${LOCAL_RPC}
forge script script/DeployMockPrice.s.sol:DeployMockPrice --broadcast --fork-url ${LOCAL_RPC}

# Deploy Dev Faucet (local only) - get mock reserve, gdao, kernel address
forge script script/mocks/DeployDevFaucet.s.sol:DeployDevFaucet --fork-url ${LOCAL_RPC}
forge script script/mocks/DeployDevFaucet.s.sol:DeployDevFaucet --broadcast --fork-url ${LOCAL_RPC}


# Deploy Price - deploy with price feeds for get and reserve assets
forge script script/DeployPrice.s.sol:DeployPrice --fork-url ${LOCAL_RPC}
forge script script/DeployPrice.s.sol:DeployPrice --broadcast --fork-url ${LOCAL_RPC}

# Deploy Range - can deploy later (need more R&D)
forge script script/modules/DeployRange.s.sol:DeployRange --fork-url ${LOCAL_RPC}
forge script script/modules/DeployRange.s.sol:DeployRange --broadcast --fork-url ${LOCAL_RPC}

# Deploy Roles
forge script script/modules/DeployRoles.s.sol:DeployRoles --fork-url ${LOCAL_RPC}
forge script script/modules/DeployRoles.s.sol:DeployRoles --broadcast --fork-url ${LOCAL_RPC}

# Deploy Treasury
forge script script/modules/DeployTreasury.s.sol:DeployTreasury --fork-url ${LOCAL_RPC}
forge script script/modules/DeployTreasury.s.sol:DeployTreasury --broadcast --fork-url ${LOCAL_RPC}

# Deploy Votes - can deploy with xGDAO
forge script script/modules/DeployVotes.s.sol:DeployVotes --fork-url ${LOCAL_RPC}
forge script script/modules/DeployVotes.s.sol:DeployVotes --broadcast --fork-url ${LOCAL_RPC}

# Policies

# Deploy Bond Aggregator - set guardian and authority
forge script script/DeployBondAggregator.s.sol:DeployBondAggregator --fork-url ${LOCAL_RPC}
forge script script/DeployBondAggregator.s.sol:DeployBondAggregator --broadcast --fork-url ${LOCAL_RPC}

# Deploy Bond Callback - get bondaggregator address
forge script script/DeployBondCallback.s.sol:DeployBondCallback --fork-url ${LOCAL_RPC}
forge script script/DeployBondCallback.s.sol:DeployBondCallback --broadcast --fork-url ${LOCAL_RPC}

# Deploy FixedTermTeller - update with Aggregator Contract
forge script script/v2/DeployFixedTermTeller.s.sol:DeployBondFixedTermTeller --fork-url ${LOCAL_RPC}
forge script script/v2/DeployFixedTermTeller.s.sol:DeployBondFixedTermTeller --broadcast --fork-url ${LOCAL_RPC}


# Deploy Operator - only needed when there are reserve assets - to do

# Deploy Heart - to do

# Deploy PriceConfig
forge script script/DeployPriceConfig.s.sol:DeployPriceConfig --fork-url ${LOCAL_RPC}
forge script script/DeployPriceConfig.s.sol:DeployPriceConfig --broadcast --fork-url ${LOCAL_RPC}

# Deploy Roles Admin
forge script script/DeployRolesAdmin.s.sol:DeployRolesAdmin --fork-url ${LOCAL_RPC}
forge script script/DeployRolesAdmin.s.sol:DeployRolesAdmin --broadcast --fork-url ${LOCAL_RPC}

# Deploy TreasuryCustodian
forge script script/DeployTreasuryCustodian.s.sol:DeployTreasuryCustodian --fork-url ${LOCAL_RPC}
forge script script/DeployTreasuryCustodian.s.sol:DeployTreasuryCustodian --broadcast --fork-url ${LOCAL_RPC}

# Deploy Distributor - update staking address
forge script script/DeployDistributor.s.sol:DeployDistributor --fork-url ${LOCAL_RPC}
forge script script/DeployDistributor.s.sol:DeployDistributor --broadcast --fork-url ${LOCAL_RPC}

# Deploy Emergency
forge script script/DeployEmergency.s.sol:DeployEmergency --fork-url ${LOCAL_RPC}
forge script script/DeployEmergency.s.sol:DeployEmergency --broadcast --fork-url ${LOCAL_RPC}

# Deploy Parthenon - governance
forge script script/DeployParthenon.s.sol:DeployParthenon --fork-url ${LOCAL_RPC}
forge script script/DeployParthenon.s.sol:DeployParthenon --broadcast --fork-url ${LOCAL_RPC}

# Deploy VgdaoVault - to do

forge script script/mocks/DeployFaucet.s.sol:DeployFaucet --broadcast --fork-url ${LOCAL_RPC}

