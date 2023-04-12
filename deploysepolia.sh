# Load .env
source .env

#### DEPLOY MOCKS #####
# local rpc = 127.0.01:8545
# deploy kernel first
# take note of genesis timestamp in anvil

# Deploy Kernel
forge script script/DeployKernel.s.sol:KernelDeploy --rpc-url ${SEPOLIA_INFURA}
forge script script/DeployKernel.s.sol:KernelDeploy --broadcast --rpc-url ${SEPOLIA_INFURA} --private-key 

# Deploy Testnet GDAO
forge script script/mocks/DeployTestnetGDAO.s.sol:TestGdaoDeploy --rpc-url ${SEPOLIA_INFURA}
forge script script/mocks/DeployTestnetGDAO.s.sol:TestGdaoDeploy --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy testnet DAI
forge script script/mocks/DeployTestDAI.s.sol:DeployDAI --rpc-url ${SEPOLIA_INFURA}
forge script script/mocks/DeployTestDAI.s.sol:DeployDAI --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Dev Faucet (local only) - get mock reserve (dai), gdao, kernel address
forge script script/mocks/DeployDevFaucet.s.sol:DeployDevFaucet --rpc-url ${SEPOLIA_INFURA}
forge script script/mocks/DeployDevFaucet.s.sol:DeployDevFaucet --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy MockPriceFeed - no constructor params
forge script script/mocks/DeployMockPriceFeed.s.sol:DeployMockPriceFeed --rpc-url ${SEPOLIA_INFURA}
forge script script/mocks/DeployMockPriceFeed.s.sol:DeployMockPriceFeed --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy MockPrice
forge script script/mocks/DeployMockPrice.s.sol:DeployMockPrice --rpc-url ${SEPOLIA_INFURA}
forge script script/mocks/DeployMockPrice.s.sol:DeployMockPrice  --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Mock Uni pair
forge script script/mocks/DeployMockUni.s.sol:DeployMockUni --rpc-url ${SEPOLIA_INFURA}
forge script script/mocks/DeployMockUni.s.sol:DeployMockUni  --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Mock Module Writer (tseting gated permission stuff)
forge script script/mocks/DeployMockModuleWriter.s.sol:DeployMockModuleWriter --rpc-url ${SEPOLIA_INFURA}
forge script script/mocks/DeployMockModuleWriter.s.sol:DeployMockModuleWriter --broadcast  --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Mock Valid Module
forge script script/mocks/DeployMockValidModule.s.sol:DeployMockValidModule --rpc-url ${SEPOLIA_INFURA}
forge script script/mocks/DeployMockValidModule.s.sol:DeployMockValidModule --broadcast  --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Mock Tests (stake/bond/claim)
forge script script/mocks/DeployMockTests.s.sol:DeployMockTests --rpc-url ${SEPOLIA_INFURA}
forge script script/mocks/DeployMockTests.s.sol:DeployMockTests --broadcast --rpc-url ${SEPOLIA_INFURA}



### TESTNET DEPLOYMENT ################################

# Deploy Kernel
forge script script/Deploy.s.sol:KernelDeploy --rpc-url ${SEPOLIA_INFURA}
forge script script/Deploy.s.sol:KernelDeploy --rpc-url ${SEPOLIA_INFURA} --private-key ${PRIV_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# Deploy Authority
forge script script/v2/DeployGdaoAuthority.s.sol:AuthorityDeploy --rpc-url ${SEPOLIA_INFURA}
forge script script/v2/DeployGdaoAuthority.s.sol:AuthorityDeploy --broadcast --rpc-url ${SEPOLIA_INFURA}

# External
# Deploy GDAO - use authority, store kernel address
forge script script/DeployGDAO.s.sol:GdaoDeploy --rpc-url ${SEPOLIA_INFURA}
forge script script/DeployGDAO.s.sol:GdaoDeploy --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy xGDAO
forge script script/v2/DeployxGDAO.s.sol:xGdaoDeploy --rpc-url ${SEPOLIA_INFURA}
forge script script/v2/DeployxGDAO.s.sol:xGdaoDeploy --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy sGDAO 
forge script script/v2/DeploysGDAO.s.sol:sGdaoDeploy --rpc-url ${SEPOLIA_INFURA}
forge script script/v2/DeploysGDAO.s.sol:sGdaoDeploy --broadcast --rpc-url ${SEPOLIA_INFURA}


# Deploy GDAOStaking
forge script script/v2/DeployGoerliStaking.s.sol:GDAOStakingDeploy --rpc-url ${SEPOLIA_INFURA}
forge script script/v2/DeployGoerliStaking.s.sol:GDAOStakingDeploy --broadcast --rpc-url ${SEPOLIA_INFURA}

# Modules

# Deploy GDaoInstructions
forge script script/modules/DeployGDaoInstructions.s.sol:GDaoInstrDeploy --rpc-url ${SEPOLIA_INFURA}
forge script script/modules/DeployGDaoInstructions.s.sol:GDaoInstrDeploy --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Roles
forge script script/modules/DeployRoles.s.sol:DeployRoles --rpc-url ${SEPOLIA_INFURA}
forge script script/modules/DeployRoles.s.sol:DeployRoles --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Treasury
forge script script/modules/DeployTreasury.s.sol:DeployTreasury --rpc-url ${SEPOLIA_INFURA}
forge script script/modules/DeployTreasury.s.sol:DeployTreasury --broadcast --rpc-url ${SEPOLIA_INFURA}

##### Modules

# Deploy GDaoInstructions
forge script script/modules/DeployGDaoInstructions.s.sol:GDaoInstrDeploy --rpc-url ${SEPOLIA_INFURA}
forge script script/modules/DeployGDaoInstructions.s.sol:GDaoInstrDeploy --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Minter
forge script script/modules/DeployMinter.s.sol:DeployMinter --rpc-url ${SEPOLIA_INFURA}
forge script script/modules/DeployMinter.s.sol:DeployMinter --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy MockPriceFeed
# forge script script/DeployMockPriceFeed.s.sol:DeployMockPriceFeed --rpc-url ${SEPOLIA_INFURA}
# forge script script/DeployMockPriceFeed.s.sol:DeployMockPriceFeed --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Price - deploy with price feeds for get and reserve assets
forge script script/DeployPrice.s.sol:DeployPrice --rpc-url ${SEPOLIA_INFURA}
forge script script/DeployPrice.s.sol:DeployPrice --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Range - can deploy later (need more R&D)
forge script script/modules/DeployRange.s.sol:DeployRange --rpc-url ${SEPOLIA_INFURA}
forge script script/modules/DeployRange.s.sol:DeployRange --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Roles
forge script script/modules/DeployRoles.s.sol:DeployRoles --rpc-url ${SEPOLIA_INFURA}
forge script script/modules/DeployRoles.s.sol:DeployRoles --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Treasury
forge script script/modules/DeployTreasury.s.sol:DeployTreasury --rpc-url ${SEPOLIA_INFURA}
forge script script/modules/DeployTreasury.s.sol:DeployTreasury --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Votes - can deploy with xGDAO
forge script script/modules/DeployVotes.s.sol:DeployVotes --rpc-url ${SEPOLIA_INFURA}
forge script script/modules/DeployVotes.s.sol:DeployVotes --broadcast --rpc-url ${SEPOLIA_INFURA}

# Policies ###########################################


# Deploy Bond Markets:  FixedTermSDA, BondCallback, Bond AggFixedTermTeller, Distributor

# Deploy Bond Aggregator - set guardian and authority
forge script script/policies/DeployBondAggregator.s.sol:DeployBondAggregator --rpc-url ${SEPOLIA_INFURA}
forge script script/policies/DeployBondAggregator.s.sol:DeployBondAggregator --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Bond Callback - get bondaggregator address
forge script script/policies/DeployBondCallback.s.sol:DeployBondCallback --rpc-url ${SEPOLIA_INFURA}
forge script script/policies/DeployBondCallback.s.sol:DeployBondCallback --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy FixedTermTeller - update with Aggregator Contract
forge script script/v2/DeployFixedTermTeller.s.sol:DeployBondFixedTermTeller --rpc-url ${SEPOLIA_INFURA}
forge script script/v2/DeployFixedTermTeller.s.sol:DeployBondFixedTermTeller --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy BondFixedSDA
forge script script/policies/DeployFixedBondSDA.s.sol:DeployFixedBondSDA --rpc-url ${SEPOLIA_INFURA}
forge script script/policies/DeployFixedBondSDA.s.sol:DeployFixedBondSDA --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Roles Authority
forge script script/v2/DeployRolesAuthority.s.sol:DeployRolesAuthority --rpc-url ${SEPOLIA_INFURA}
forge script script/v2/DeployRolesAuthority.s.sol:DeployRolesAuthority --broadcast --rpc-url ${SEPOLIA_INFURA}


# Deploy Operator - only needed when there are reserve assets - to do

# Deploy Heart - to do

# Deploy PriceConfig
forge script script/DeployPriceConfig.s.sol:DeployPriceConfig --rpc-url ${SEPOLIA_INFURA}
forge script script/DeployPriceConfig.s.sol:DeployPriceConfig --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Roles Admin
forge script script/DeployRolesAdmin.s.sol:DeployRolesAdmin --rpc-url ${SEPOLIA_INFURA}
forge script script/DeployRolesAdmin.s.sol:DeployRolesAdmin --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy TreasuryCustodian
forge script script/DeployTreasuryCustodian.s.sol:DeployTreasuryCustodian --rpc-url ${SEPOLIA_INFURA}
forge script script/DeployTreasuryCustodian.s.sol:DeployTreasuryCustodian --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Distributor - update staking address
forge script script/policies/DeployDistributor.s.sol:DeployDistributor --rpc-url ${SEPOLIA_INFURA}
forge script script/policies/DeployDistributor.s.sol:DeployDistributor --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Emergency
forge script script/policies/DeployEmergency.s.sol:DeployEmergency --rpc-url ${SEPOLIA_INFURA}
forge script script/policies/DeployEmergency.s.sol:DeployEmergency --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Distributor - update staking address
forge script script/policies/DeployDistributor.s.sol:DeployDistributor --rpc-url ${SEPOLIA_INFURA}
forge script script/policies/DeployDistributor.s.sol:DeployDistributor --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Emergency
forge script script/policies/DeployEmergency.s.sol:DeployEmergency --rpc-url ${SEPOLIA_INFURA}
forge script script/policies/DeployEmergency.s.sol:DeployEmergency --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Parthenon - governance
forge script script/policies/DeployParthenon.s.sol:DeployParthenon --rpc-url ${SEPOLIA_INFURA}
forge script script/policies/DeployParthenon.s.sol:DeployParthenon --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy Votes - can deploy with xGDAO
forge script script/modules/DeployVotes.s.sol:DeployVotes --rpc-url ${SEPOLIA_INFURA}
forge script script/modules/DeployVotes.s.sol:DeployVotes --broadcast --rpc-url ${SEPOLIA_INFURA}

# Deploy VgdaoVault - to do
