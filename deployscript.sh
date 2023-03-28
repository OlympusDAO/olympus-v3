# Load .env
source .env

# Deploy Kernel
forge script script/Deploy.s.sol:KernelDeploy --fork-url ${LOCALHOST}
forge script script/Deploy.s.sol:KernelDeploy --broadcast --fork-url ${LOCALHOST}

# External
# Deploy GDAO - use authority, store kernel address
forge script script/DeployGDAO.s.sol:GdaoDeploy --fork-url ${LOCALHOST}
forge script script/DeployGDAO.s.sol:GdaoDeploy --broadcast --fork-url ${LOCALHOST}

# Deploy xGDAO
forge script script/v2/DeployxGDAO.s.sol:xGdaoDeploy --fork-url ${LOCALHOST}
forge script script/v2/DeployxGDAO.s.sol:xGdaoDeploy --broadcast --fork-url ${LOCALHOST}

# Deploy sGDAO 
forge script script/v2/DeploysGDAO.s.sol:sGdaoDeploy --fork-url ${LOCALHOST}
forge script script/v2/DeploysGDAO.s.sol:sGdaoDeploy --broadcast --fork-url ${LOCALHOST}

# Deploy GDAOStaking
forge script script/v2/DeployGDAOStaking.s.sol:GDAOStakingDeploy --fork-url ${LOCALHOST}
forge script script/v2/DeployGDAOStaking.s.sol:GDAOStakingDeploy --broadcast --fork-url ${LOCALHOST}
# Modules

# Deploy GDaoInstructions
forge script script/modules/DeployGDaoInstructions.s.sol:GDaoInstrDeploy --fork-url ${LOCALHOST}
forge script script/modules/DeployGDaoInstructions.s.sol:GDaoInstrDeploy --broadcast --fork-url ${LOCALHOST}

# Deploy Minter
forge script script/modules/DeployMinter.s.sol:DeployMinter --fork-url ${LOCALHOST}
forge script script/modules/DeployMinter.s.sol:DeployMinter --broadcast --fork-url ${LOCALHOST}

# Deploy MockPriceFeed
forge script script/DeployMockPriceFeed.s.sol:DeployMockPriceFeed --fork-url ${LOCALHOST}
forge script script/DeployMockPriceFeed.s.sol:DeployMockPriceFeed --broadcast --fork-url ${LOCALHOST}

# Deploy MockOHM (local only)
forge script script/mocks/DeployMockReserve.s.sol:DeployMockReserve --fork-url ${LOCALHOST}
forge script script/mocks/DeployMockReserve.s.sol:DeployMockReserve --broadcast --fork-url ${LOCALHOST}

# Deploy MockPrice
forge script script/DeployMockPrice.s.sol:DeployMockPrice --fork-url ${LOCALHOST}
forge script script/DeployMockPrice.s.sol:DeployMockPrice --broadcast --fork-url ${LOCALHOST}

# Deploy Dev Faucet (local only) - get mock reserve, gdao, kernel address
forge script script/mocks/DeployDevFaucet.s.sol:DeployDevFaucet --fork-url ${LOCALHOST}
forge script script/mocks/DeployDevFaucet.s.sol:DeployDevFaucet --broadcast --fork-url ${LOCALHOST}


# Deploy Price - deploy with price feeds for get and reserve assets
forge script script/DeployPrice.s.sol:DeployPrice --fork-url ${LOCALHOST}
forge script script/DeployPrice.s.sol:DeployPrice --broadcast --fork-url ${LOCALHOST}

# Deploy Range - can deploy later (need more R&D)
forge script script/modules/DeployRange.s.sol:DeployRange --fork-url ${LOCALHOST}
forge script script/modules/DeployRange.s.sol:DeployRange --broadcast --fork-url ${LOCALHOST}

# Deploy Roles
forge script script/modules/DeployRoles.s.sol:DeployRoles --fork-url ${LOCALHOST}
forge script script/modules/DeployRoles.s.sol:DeployRoles --broadcast --fork-url ${LOCALHOST}

# Deploy Treasury
forge script script/modules/DeployTreasury.s.sol:DeployTreasury --fork-url ${LOCALHOST}
forge script script/modules/DeployTreasury.s.sol:DeployTreasury --broadcast --fork-url ${LOCALHOST}

# Deploy Votes - can deploy with xGDAO
forge script script/modules/DeployVotes.s.sol:DeployVotes --fork-url ${LOCALHOST}
forge script script/modules/DeployVotes.s.sol:DeployVotes --broadcast --fork-url ${LOCALHOST}

# Policies

# Deploy Bond Aggregator - set guardian and authority
forge script script/DeployBondAggregator.s.sol:DeployBondAggregator --fork-url ${LOCALHOST}
forge script script/DeployBondAggregator.s.sol:DeployBondAggregator --broadcast --fork-url ${LOCALHOST}

# Deploy Bond Callback - get bondaggregator address
forge script script/DeployBondCallback.s.sol:DeployBondCallback --fork-url ${LOCALHOST}
forge script script/DeployBondCallback.s.sol:DeployBondCallback --broadcast --fork-url ${LOCALHOST}

# Deploy FixedTermTeller - update with Aggregator Contract
forge script script/v2/DeployFixedTermTeller.s.sol:DeployBondFixedTermTeller --fork-url ${LOCALHOST}
forge script script/v2/DeployFixedTermTeller.s.sol:DeployBondFixedTermTeller --broadcast --fork-url ${LOCALHOST}


# Deploy Operator - only needed when there are reserve assets - to do

# Deploy Heart - to do

# Deploy PriceConfig
forge script script/DeployPriceConfig.s.sol:DeployPriceConfig --fork-url ${LOCALHOST}
forge script script/DeployPriceConfig.s.sol:DeployPriceConfig --broadcast --fork-url ${LOCALHOST}

# Deploy Roles Admin
forge script script/DeployRolesAdmin.s.sol:DeployRolesAdmin --fork-url ${LOCALHOST}
forge script script/DeployRolesAdmin.s.sol:DeployRolesAdmin --broadcast --fork-url ${LOCALHOST}

# Deploy TreasuryCustodian
forge script script/DeployTreasuryCustodian.s.sol:DeployTreasuryCustodian --fork-url ${LOCALHOST}
forge script script/DeployTreasuryCustodian.s.sol:DeployTreasuryCustodian --broadcast --fork-url ${LOCALHOST}

# Deploy Distributor - update staking address
forge script script/DeployDistributor.s.sol:DeployDistributor --fork-url ${LOCALHOST}
forge script script/DeployDistributor.s.sol:DeployDistributor --broadcast --fork-url ${LOCALHOST}

# Deploy Emergency
forge script script/DeployEmergency.s.sol:DeployEmergency --fork-url ${LOCALHOST}
forge script script/DeployEmergency.s.sol:DeployEmergency --broadcast --fork-url ${LOCALHOST}

# Deploy Parthenon - governance
forge script script/DeployParthenon.s.sol:DeployParthenon --fork-url ${LOCALHOST}
forge script script/DeployParthenon.s.sol:DeployParthenon --broadcast --fork-url ${LOCALHOST}

# Deploy VgdaoVault - to do

forge script script/mocks/DeployFaucet.s.sol:DeployFaucet --broadcast --fork-url ${LOCALHOST}

