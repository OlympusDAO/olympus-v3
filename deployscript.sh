# Deploy Kernel
forge script script/Deploy.s.sol:KernelDeploy --fork-url http://127.0.0.1:8545
forge script script/Deploy.s.sol:KernelDeploy --broadcast --fork-url http://127.0.0.1:8545


# External
# Deploy GDAO
forge script script/DeployGDAO.s.sol:GdaoDeploy --fork-url http://127.0.0.1:8545
forge script script/DeployGDAO.s.sol:GdaoDeploy --broadcast --fork-url http://127.0.0.1:8545

# Deploy xGDAO? - to do


# Modules

# Deploy GDaoInstructions
forge script script/modules/DeployGDaoInstructions.s.sol:GDaoInstrDeploy --fork-url http://127.0.0.1:8545
forge script script/modules/DeployGDaoInstructions.s.sol:GDaoInstrDeploy --broadcast --fork-url http://127.0.0.1:8545

# Deploy Minter
forge script script/modules/DeployMinter.s.sol:DeployMinter --fork-url http://127.0.0.1:8545
forge script script/modules/DeployMinter.s.sol:DeployMinter --broadcast --fork-url http://127.0.0.1:8545

# Deploy MockPrice
forge script script/DeployMockPrice.s.sol:DeployMockPrice --fork-url http://127.0.0.1:8545
forge script script/DeployMockPrice.s.sol:DeployMockPrice --broadcast --fork-url http://127.0.0.1:8545

# Deploy MockPriceFeed
forge script script/DeployMockPriceFeed.s.sol:DeployMockPriceFeed --fork-url http://127.0.0.1:8545
forge script script/DeployMockPriceFeed.s.sol:DeployMockPriceFeed --broadcast --fork-url http://127.0.0.1:8545

# Deploy Price
forge script script/DeployPrice.s.sol:DeployPrice --fork-url http://127.0.0.1:8545
forge script script/DeployPrice.s.sol:DeployPrice --broadcast --fork-url http://127.0.0.1:8545

# Deploy Range
forge script script/modules/DeployRange.s.sol:DeployRange --fork-url http://127.0.0.1:8545
forge script script/modules/DeployRange.s.sol:DeployRange --broadcast --fork-url http://127.0.0.1:8545

# Deploy Roles
forge script script/modules/DeployRoles.s.sol:DeployRoles --fork-url http://127.0.0.1:8545
forge script script/modules/DeployRoles.s.sol:DeployRoles --broadcast --fork-url http://127.0.0.1:8545

# Deploy Treasury
forge script script/modules/DeployTreasury.s.sol:DeployTreasury --fork-url http://127.0.0.1:8545
forge script script/modules/DeployTreasury.s.sol:DeployTreasury --broadcast --fork-url http://127.0.0.1:8545

# Deploy Votes
forge script script/modules/DeployVotes.s.sol:DeployVotes --fork-url http://127.0.0.1:8545
forge script script/modules/DeployVotes.s.sol:DeployVotes --broadcast --fork-url http://127.0.0.1:8545

# Policies

# Deploy Bond Aggregator - to do
forge script script/DeployBondAggregator.s.sol:DeployBondAggregator --fork-url http://127.0.0.1:8545
forge script script/DeployBondAggregator.s.sol:DeployBondAggregator --broadcast --fork-url http://127.0.0.1:8545

# Deploy Bond Callback - to do
forge script script/DeployBondCallback.s.sol:DeployBondCallback --fork-url http://127.0.0.1:8545
forge script script/DeployBondCallback.s.sol:DeployBondCallback --broadcast --fork-url http://127.0.0.1:8545

# Deploy Operator - only needed when there are reserve assets - to do

# Deploy Heart - to do

# Deploy PriceConfig
forge script script/DeployPriceConfig.s.sol:DeployPriceConfig --fork-url http://127.0.0.1:8545
forge script script/DeployPriceConfig.s.sol:DeployPriceConfig --broadcast --fork-url http://127.0.0.1:8545

# Deploy Roles Admin
forge script script/DeployRolesAdmin.s.sol:DeployRolesAdmin --fork-url http://127.0.0.1:8545
forge script script/DeployRolesAdmin.s.sol:DeployRolesAdmin --broadcast --fork-url http://127.0.0.1:8545

# Deploy TreasuryCustodian
forge script script/DeployTreasuryCustodian.s.sol:DeployTreasuryCustodian --fork-url http://127.0.0.1:8545
forge script script/DeployTreasuryCustodian.s.sol:DeployTreasuryCustodian --broadcast --fork-url http://127.0.0.1:8545

# Deploy Distributor
forge script script/DeployDistributor.s.sol:DeployDistributor --fork-url http://127.0.0.1:8545
forge script script/DeployDistributor.s.sol:DeployDistributor --broadcast --fork-url http://127.0.0.1:8545

# Deploy Emergency
forge script script/DeployEmergency.s.sol:DeployEmergency --fork-url http://127.0.0.1:8545
forge script script/DeployEmergency.s.sol:DeployEmergency --broadcast --fork-url http://127.0.0.1:8545

# Deploy Parthenon - governance
forge script script/DeployParthenon.s.sol:DeployParthenon --fork-url http://127.0.0.1:8545
forge script script/DeployParthenon.s.sol:DeployParthenon --broadcast --fork-url http://127.0.0.1:8545

# Deploy VgdaoVault - to do