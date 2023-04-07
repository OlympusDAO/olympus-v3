# Load .env
source .env

#### DEPLOY MOCKS #####
# local rpc = 127.0.01:8545
# deploy kernel first
# take note of genesis timestamp in anvil

# Deploy Kernel
forge script script/DeployKernel.s.sol:KernelDeploy --rpc-url ${GOERLI_INFURA}
forge script script/DeployKernel.s.sol:KernelDeploy --broadcast --rpc-url ${GOERLI_INFURA} --private-key 

# # Deploy Kernel Utils
# forge script script/DeployKernelUtils.s.sol:KernelUtilsDeploy --rpc-url ${GOERLI_INFURA}
# forge script script/DeployKernelUtils.s.sol:KernelUtilsDeploy--broadcast --rpc-url ${GOERLI_INFURA}

# Deploy Testnet GDAO
forge script script/mocks/DeployTestnetGDAO.s.sol:TestGdaoDeploy --rpc-url ${GOERLI_INFURA}
forge script script/mocks/DeployTestnetGDAO.s.sol:TestGdaoDeploy --broadcast --rpc-url ${GOERLI_INFURA}

# Deploy testnet DAI
forge script script/mocks/DeployTestDAI.s.sol:DeployDAI --rpc-url ${GOERLI_INFURA}
forge script script/mocks/DeployTestDAI.s.sol:DeployDAI --broadcast --rpc-url ${GOERLI_INFURA}

# Deploy Dev Faucet (local only) - get mock reserve (dai), gdao, kernel address
forge script script/mocks/DeployDevFaucet.s.sol:DeployDevFaucet --rpc-url ${GOERLI_INFURA}
forge script script/mocks/DeployDevFaucet.s.sol:DeployDevFaucet --broadcast --rpc-url ${GOERLI_INFURA}

## test dev faucet
# use cast to mint gdao tokens from dev faucet

cast send -f 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9 "drip(uint8)" 1 --rpc-url ${GOERLI_INFURA}


### ----


# Deploy MockPriceFeed - no constructor params
forge script script/mocks/DeployMockPriceFeed.s.sol:DeployMockPriceFeed --rpc-url ${GOERLI_INFURA}
forge script script/mocks/DeployMockPriceFeed.s.sol:DeployMockPriceFeed --broadcast --rpc-url ${GOERLI_INFURA}

# Deploy MockPrice
forge script script/mocks/DeployMockPrice.s.sol:DeployMockPrice --rpc-url ${GOERLI_INFURA}
forge script script/mocks/DeployMockPrice.s.sol:DeployMockPrice  --broadcast --rpc-url ${GOERLI_INFURA}

# Deploy Mock Uni pair
forge script script/mocks/DeployMockUni.s.sol:DeployMockUni --rpc-url ${GOERLI_INFURA}
forge script script/mocks/DeployMockUni.s.sol:DeployMockUni --broadcast  --broadcast --rpc-url ${GOERLI_INFURA}

# Deploy Mock Module Writer (tseting gated permission stuff)
forge script script/mocks/DeployMockModuleWriter.s.sol:DeployMockModuleWriter --rpc-url ${GOERLI_INFURA}
forge script script/mocks/DeployMockModuleWriter.s.sol:DeployMockModuleWriter --broadcast  --broadcast --rpc-url ${GOERLI_INFURA}

# Deploy Mock Valid Module
forge script script/mocks/DeployMockValidModule.s.sol:DeployMockValidModule --rpc-url ${GOERLI_INFURA}
forge script script/mocks/DeployMockValidModule.s.sol:DeployMockValidModule --broadcast  --broadcast --rpc-url ${GOERLI_INFURA}



# Deploy Mock Tests (stake/bond/claim)
forge script script/DeployMockTests.s.sol:DeployMockTests --rpc-url ${GOERLI_INFURA}
forge script script/DeployMockTests.s.sol:DeployMockTests --broadcast  --broadcast --rpc-url ${GOERLI_INFURA}



### TESTNET DEPLOYMENT

# Deploy Kernel
forge script script/Deploy.s.sol:KernelDeploy --rpc-url ${SEPOLIA_INFURA}
forge script script/Deploy.s.sol:KernelDeploy --rpc-url ${SEPOLIA_INFURA} --private-key ${PRIV_KEY} --broadcast --verify --optimize --optimizer-runs 20000 -vvvv

# # Deploy Testnet GDAO
# forge script script/v2/DeployTestnetGDAO.s.sol:TestGdaoDeploy --rpc-url ${GOERLI_INFURA}
# forge script script/v2/DeployTestnetGDAO.s.sol:TestGdaoDeploy --broadcast --rpc-url ${GOERLI_INFURA}

# # Deploy testnet DAI
# forge script script/v2/DeployTestDAI.s.sol:DeployDAI --rpc-url ${GOERLI_INFURA}
# forge script script/v2/DeployTestDAI.s.sol:DeployDAI --broadcast --rpc-url ${GOERLI_INFURA}

# Deploy Faucet v2 - deploy authority, gdao, dai, staking contracts first
# forge script script/v2/DeployFaucetV2.s.sol:DeployFaucet --rpc-url ${GOERLI_INFURA}
# forge script script/v2/DeployFaucetV2.s.sol:DeployFaucet --broadcast --rpc-url ${GOERLI_INFURA}

# Deploy Dev Faucet v3
forge script script/mocks/DeployDevFaucet.s.sol:DeployDevFaucet --broadcast --fork-url ${GOERLI_INFURA}

# External
# Deploy GDAO - use authority, store kernel address
forge script script/DeployGDAO.s.sol:GdaoDeploy --fork-url ${SEPOLIA_INFURA}
forge script script/DeployGDAO.s.sol:GdaoDeploy --rpc-url ${SEPOLIA_INFURA}  --broadcast #-g 150 --gas-limit 1165322 --gas-price 5760

# Deploy xGDAO
forge script script/v2/DeployxGDAO.s.sol:xGdaoDeploy --fork-url ${SEPOLIA_INFURA}
forge script script/v2/DeployxGDAO.s.sol:xGdaoDeploy --broadcast --fork-url ${SEPOLIA_INFURA}

# Deploy sGDAO 
forge script script/v2/DeploysGDAO.s.sol:sGdaoDeploy --fork-url ${SEPOLIA_INFURA}
forge script script/v2/DeploysGDAO.s.sol:sGdaoDeploy --broadcast --fork-url ${SEPOLIA_INFURA}

# Deploy GDAOStaking
forge script script/v2/DeployGDAOStaking.s.sol:GDAOStakingDeploy --fork-url ${SEPOLIA_INFURA}
forge script script/v2/DeployGDAOStaking.s.sol:GDAOStakingDeploy --broadcast --rpc-url ${GOERLI_INFURA}
# Modules

# Deploy GDaoInstructions
forge script script/modules/DeployGDaoInstructions.s.sol:GDaoInstrDeploy --fork-url ${SEPOLIA_INFURA}
forge script script/modules/DeployGDaoInstructions.s.sol:GDaoInstrDeploy --broadcast --fork-url ${SEPOLIA_INFURA}

# Deploy Minter
forge script script/modules/DeployMinter.s.sol:DeployMinter --fork-url ${SEPOLIA_INFURA}
forge script script/modules/DeployMinter.s.sol:DeployMinter --broadcast --fork-url ${SEPOLIA_INFURA}

# Deploy Price - deploy with price feeds for get and reserve assets
forge script script/DeployPrice.s.sol:DeployPrice --fork-url ${SEPOLIA_INFURA}
forge script script/DeployPrice.s.sol:DeployPrice --broadcast --fork-url ${SEPOLIA_INFURA}

# Deploy Range - can deploy later (need more R&D)
forge script script/modules/DeployRange.s.sol:DeployRange --fork-url ${SEPOLIA_INFURA}
forge script script/modules/DeployRange.s.sol:DeployRange --broadcast --fork-url ${SEPOLIA_INFURA}

# Deploy Roles
forge script script/modules/DeployRoles.s.sol:DeployRoles --fork-url ${SEPOLIA_INFURA}
forge script script/modules/DeployRoles.s.sol:DeployRoles --broadcast --fork-url ${SEPOLIA_INFURA}

# Deploy Treasury
forge script script/modules/DeployTreasury.s.sol:DeployTreasury --fork-url ${SEPOLIA_INFURA}
forge script script/modules/DeployTreasury.s.sol:DeployTreasury --broadcast --fork-url ${SEPOLIA_INFURA}

# Deploy Votes - can deploy with xGDAO
forge script script/modules/DeployVotes.s.sol:DeployVotes --fork-url ${SEPOLIA_INFURA}
forge script script/modules/DeployVotes.s.sol:DeployVotes --broadcast --fork-url ${SEPOLIA_INFURA}
forge script script/Deploy.s.sol:KernelDeploy --fork-url ${GOERLI_INFURA}
forge script script/Deploy.s.sol:KernelDeploy --broadcast --fork-url ${GOERLI_INFURA}

# External
# Deploy GDAO - use authority, store kernel address
forge script script/DeployGDAO.s.sol:GdaoDeploy --fork-url ${GOERLI_INFURA}
forge script script/DeployGDAO.s.sol:GdaoDeploy --broadcast --fork-url ${GOERLI_INFURA}

# Deploy xGDAO
forge script script/v2/DeployxGDAO.s.sol:xGdaoDeploy --fork-url ${GOERLI_INFURA}
forge script script/v2/DeployxGDAO.s.sol:xGdaoDeploy --broadcast --fork-url ${GOERLI_INFURA}

# Deploy sGDAO 
forge script script/v2/DeploysGDAO.s.sol:sGdaoDeploy --fork-url ${GOERLI_INFURA}
forge script script/v2/DeploysGDAO.s.sol:sGdaoDeploy --broadcast --fork-url ${GOERLI_INFURA}

# Deploy GDAOStaking
forge script script/v2/DeployGDAOStaking.s.sol:GDAOStakingDeploy --fork-url ${GOERLI_INFURA}
forge script script/v2/DeployGDAOStaking.s.sol:GDAOStakingDeploy --broadcast --fork-url ${GOERLI_INFURA}
# Modules

# Deploy GDaoInstructions
forge script script/modules/DeployGDaoInstructions.s.sol:GDaoInstrDeploy --fork-url ${GOERLI_INFURA}
forge script script/modules/DeployGDaoInstructions.s.sol:GDaoInstrDeploy --broadcast --fork-url ${GOERLI_INFURA}

# Deploy Minter
forge script script/modules/DeployMinter.s.sol:DeployMinter --fork-url ${GOERLI_INFURA}
forge script script/modules/DeployMinter.s.sol:DeployMinter --broadcast --fork-url ${GOERLI_INFURA}

# Deploy MockPriceFeed
forge script script/DeployMockPriceFeed.s.sol:DeployMockPriceFeed --fork-url ${GOERLI_INFURA}
forge script script/DeployMockPriceFeed.s.sol:DeployMockPriceFeed --broadcast --fork-url ${GOERLI_INFURA}

# Deploy MockOHM (local only)
forge script script/mocks/DeployMockReserve.s.sol:DeployMockReserve --fork-url ${GOERLI_INFURA}
forge script script/mocks/DeployMockReserve.s.sol:DeployMockReserve --broadcast --fork-url ${GOERLI_INFURA}

# Deploy MockPrice
forge script script/DeployMockPrice.s.sol:DeployMockPrice --fork-url ${GOERLI_INFURA}
forge script script/DeployMockPrice.s.sol:DeployMockPrice --broadcast --fork-url ${GOERLI_INFURA}

# Deploy Dev Faucet (local only) - get mock reserve, gdao, kernel address
forge script script/mocks/DeployDevFaucet.s.sol:DeployDevFaucet --fork-url ${GOERLI_INFURA}
forge script script/mocks/DeployDevFaucet.s.sol:DeployDevFaucet --broadcast --fork-url ${GOERLI_INFURA}


# Deploy Price - deploy with price feeds for get and reserve assets
forge script script/DeployPrice.s.sol:DeployPrice --fork-url ${GOERLI_INFURA}
forge script script/DeployPrice.s.sol:DeployPrice --broadcast --fork-url ${GOERLI_INFURA}

# Deploy Range - can deploy later (need more R&D)
forge script script/modules/DeployRange.s.sol:DeployRange --fork-url ${GOERLI_INFURA}
forge script script/modules/DeployRange.s.sol:DeployRange --broadcast --fork-url ${GOERLI_INFURA}

# Deploy Roles
forge script script/modules/DeployRoles.s.sol:DeployRoles --fork-url ${GOERLI_INFURA}
forge script script/modules/DeployRoles.s.sol:DeployRoles --broadcast --fork-url ${GOERLI_INFURA}

# Deploy Treasury
forge script script/modules/DeployTreasury.s.sol:DeployTreasury --fork-url ${GOERLI_INFURA}
forge script script/modules/DeployTreasury.s.sol:DeployTreasury --broadcast --fork-url ${GOERLI_INFURA}

# Deploy Votes - can deploy with xGDAO
forge script script/modules/DeployVotes.s.sol:DeployVotes --fork-url ${GOERLI_INFURA}
forge script script/modules/DeployVotes.s.sol:DeployVotes --broadcast --fork-url ${GOERLI_INFURA}

# Policies

# Deploy Bond Aggregator - set guardian and authority
<<<<<<< HEAD
forge script script/DeployBondAggregator.s.sol:DeployBondAggregator --fork-url ${SEPOLIA_INFURA}
forge script script/DeployBondAggregator.s.sol:DeployBondAggregator --broadcast --fork-url ${SEPOLIA_INFURA}

# Deploy Bond Callback - get bondaggregator address
forge script script/DeployBondCallback.s.sol:DeployBondCallback --fork-url ${SEPOLIA_INFURA}
forge script script/DeployBondCallback.s.sol:DeployBondCallback --broadcast --fork-url ${SEPOLIA_INFURA}

# Deploy FixedTermTeller - update with Aggregator Contract
forge script script/v2/DeployFixedTermTeller.s.sol:DeployBondFixedTermTeller --fork-url ${SEPOLIA_INFURA}
forge script script/v2/DeployFixedTermTeller.s.sol:DeployBondFixedTermTeller --broadcast --fork-url ${SEPOLIA_INFURA}
=======
forge script script/DeployBondAggregator.s.sol:DeployBondAggregator --fork-url ${GOERLI_INFURA}
forge script script/DeployBondAggregator.s.sol:DeployBondAggregator --broadcast --fork-url ${GOERLI_INFURA}

# Deploy Bond Callback - get bondaggregator address
forge script script/DeployBondCallback.s.sol:DeployBondCallback --fork-url ${GOERLI_INFURA}
forge script script/DeployBondCallback.s.sol:DeployBondCallback --broadcast --fork-url ${GOERLI_INFURA}

# Deploy FixedTermTeller - update with Aggregator Contract
forge script script/v2/DeployFixedTermTeller.s.sol:DeployBondFixedTermTeller --fork-url ${GOERLI_INFURA}
forge script script/v2/DeployFixedTermTeller.s.sol:DeployBondFixedTermTeller --broadcast --fork-url ${GOERLI_INFURA}
>>>>>>> v3


# Deploy Operator - only needed when there are reserve assets - to do

# Deploy Heart - to do

# Deploy PriceConfig
<<<<<<< HEAD
forge script script/DeployPriceConfig.s.sol:DeployPriceConfig --fork-url ${SEPOLIA_INFURA}
forge script script/DeployPriceConfig.s.sol:DeployPriceConfig --broadcast --fork-url ${SEPOLIA_INFURA}

# Deploy Roles Admin
forge script script/DeployRolesAdmin.s.sol:DeployRolesAdmin --fork-url ${SEPOLIA_INFURA}
forge script script/DeployRolesAdmin.s.sol:DeployRolesAdmin --broadcast --fork-url ${SEPOLIA_INFURA}

# Deploy TreasuryCustodian
forge script script/DeployTreasuryCustodian.s.sol:DeployTreasuryCustodian --fork-url ${SEPOLIA_INFURA}
forge script script/DeployTreasuryCustodian.s.sol:DeployTreasuryCustodian --broadcast --fork-url ${SEPOLIA_INFURA}

# Deploy Distributor - update staking address
forge script script/DeployDistributor.s.sol:DeployDistributor --fork-url ${SEPOLIA_INFURA}
forge script script/DeployDistributor.s.sol:DeployDistributor --broadcast --fork-url ${SEPOLIA_INFURA}

# Deploy Emergency
forge script script/DeployEmergency.s.sol:DeployEmergency --fork-url ${SEPOLIA_INFURA}
forge script script/DeployEmergency.s.sol:DeployEmergency --broadcast --fork-url ${SEPOLIA_INFURA}

# Deploy Parthenon - governance
forge script script/DeployParthenon.s.sol:DeployParthenon --fork-url ${SEPOLIA_INFURA}
forge script script/DeployParthenon.s.sol:DeployParthenon --broadcast --fork-url ${SEPOLIA_INFURA}

# Deploy VgdaoVault - to do


# cast call 0x96f3ce39ad2bfdcf92c0f6e2c2cabf83874660fc "dripTestAmounts()" $LOCAL_AUTHORITY_PRIV
# cast send --from 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 "mint(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, 1000000000)(address)(uint256)" $LOCAL_AUTHORITY_PRIV
=======
forge script script/DeployPriceConfig.s.sol:DeployPriceConfig --fork-url ${GOERLI_INFURA}
forge script script/DeployPriceConfig.s.sol:DeployPriceConfig --broadcast --fork-url ${GOERLI_INFURA}

# Deploy Roles Admin
forge script script/DeployRolesAdmin.s.sol:DeployRolesAdmin --fork-url ${GOERLI_INFURA}
forge script script/DeployRolesAdmin.s.sol:DeployRolesAdmin --broadcast --fork-url ${GOERLI_INFURA}

# Deploy TreasuryCustodian
forge script script/DeployTreasuryCustodian.s.sol:DeployTreasuryCustodian --fork-url ${GOERLI_INFURA}
forge script script/DeployTreasuryCustodian.s.sol:DeployTreasuryCustodian --broadcast --fork-url ${GOERLI_INFURA}

# Deploy Distributor - update staking address
forge script script/DeployDistributor.s.sol:DeployDistributor --fork-url ${GOERLI_INFURA}
forge script script/DeployDistributor.s.sol:DeployDistributor --broadcast --fork-url ${GOERLI_INFURA}

# Deploy Emergency
forge script script/DeployEmergency.s.sol:DeployEmergency --fork-url ${GOERLI_INFURA}
forge script script/DeployEmergency.s.sol:DeployEmergency --broadcast --fork-url ${GOERLI_INFURA}

# Deploy Parthenon - governance
forge script script/DeployParthenon.s.sol:DeployParthenon --fork-url ${GOERLI_INFURA}
forge script script/DeployParthenon.s.sol:DeployParthenon --broadcast --fork-url ${GOERLI_INFURA}

# Deploy VgdaoVault - to do

forge script script/mocks/DeployFaucet.s.sol:DeployFaucet --broadcast --fork-url ${GOERLI_INFURA}
>>>>>>> v3

