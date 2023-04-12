# Kernel deployment verification script (Sepolia)
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor()") 0xe43cd84c93c12d0b613ab736f6b62dbbfaa2df37 Kernel

# Test GDAO deployment verification script (Sepolia)
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address)" 0xD358dA590f6fA5BF87b2580cD77B70808E297185) 0xBACDCB0151A00Dd7c1aEFbbbEc378939E41BfC76 TestGDAO

# Test DAI deployment verification script (Sepolia)
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(uint256)" 11155111) 0x85983eb365f7159ed6Adf1b130919c1b962cCfA7 DAI

# Mock UniV2 deployment verification script (Sepolia)
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address,address)" 0xBACDCB0151A00Dd7c1aEFbbbEc378939E41BfC76 0x85983eb365f7159ed6Adf1b130919c1b962cCfA7) 0xd3c17b8048bef5ffd853c9f31f73d0059e562737 MockUniV2Pair

# # deploy Faucet with GDAO1.2
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address,address,address,uint256,uint256,uint256,uint256)" 0xE43CD84c93c12d0B613aB736F6b62DBbFaa2DF37 0x9523d80e515960a26cB787C5809CCF68ddAbCBDb  0x85983eb365f7159ed6Adf1b130919c1b962cCfA7 1000000000000000000 100000000000000000 10000000000000000000000000 360) 0xfFCD4EE7E1c294617074B747a6DDF4B3473F4721 src/test/mocks/Faucet.sol:Faucet

# Mock Price Feed deployment
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor()") 0x7D6779618c40fD981Fe568d901A002099820A97e MockPriceFeed

# Mock Price deployment Sepolia
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address,uint48,uint256)" 0xE43CD84c93c12d0B613aB736F6b62DBbFaa2DF37 28800 10410000000000000000) 0x88737F128Ee902feB2a5Ad5ce4707536fed5A299 MockPrice

# Mock Policy Tests deployment Sepolia
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address)" 0xE43CD84c93c12d0B613aB736F6b62DBbFaa2DF37) 0x27a5df72fbf3795db58a44edab5170131b38426b MockPolicy

# Deploy xGDAO Sepolia
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor()") 0xFFbC5937d48afc21E0D514D1650ffc1e4B84e98C xGDAO

 # Deploy sGDAO Sepolia
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor()") 0x66d281fbde3014e01255fbd65108214a5e634657 sGDAO

# Deploy Goerli Staking 1.2
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(uint256,uint256,uint256,uint256,uint256,uint256,uint256)" 0x9523d80e515960a26cB787C5809CCF68ddAbCBDb 0x66d281fbde3014e01255fbd65108214a5e634657 0xFFbC5937d48afc21E0D514D1650ffc1e4B84e98C 28800 1 1639512000 0x86D9e2623D6fFFB1165A58379fE99613df77F17A) 0x2dAba5d558088f874110dBda520717d6C1947f42 src/v2/GDAOStaking.sol:GoerliStaking

# Deploy V1 Faucet
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address,address,address,address)" 0x85983eb365f7159ed6Adf1b130919c1b962cCfA7 0x553F5301DD8709a88Dc1Cd9F416AB33EB5A7cf56 0x419cfD6aBe4F68b7ed001a0b83aF9997a0b26451 0xD358dA590f6fA5BF87b2580cD77B70808E297185) 0xf0248575d8a249730b6ba055ddb6ac13544bc63d Faucet_V1

 # Deploy GDAO Sepolia
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address)" 0x86D9e2623D6fFFB1165A58379fE99613df77F17A) 0x9523d80e515960a26cB787C5809CCF68ddAbCBDb src/external/GDAO.sol:GDAO

# Deploy Instructions Sepolia
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address)" 0xE43CD84c93c12d0B613aB736F6b62DBbFaa2DF37) 0xC965150241514d118600138548Ed34bdb620FE25 GoerliDaoInstructions

# Deploy Minter Sepolia
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address,address)" 0xE43CD84c93c12d0B613aB736F6b62DBbFaa2DF37 0x553F5301DD8709a88Dc1Cd9F416AB33EB5A7cf56) 0x5768D64f3E1a28Ecc311F0109c70E17a6E0a1336 GoerliMinter

# Deploy Price (later)
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address,address)" ) 

# Deploy Authority
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address,address,address,address)" 0xD358dA590f6fA5BF87b2580cD77B70808E297185 0xD358dA590f6fA5BF87b2580cD77B70808E297185 0x96dEBE563Ac45450Bc1c647489658A74BBC8B094 0xD358dA590f6fA5BF87b2580cD77B70808E297185) 0x86D9e2623D6fFFB1165A58379fE99613df77F17A GdaoAuthority 

# Deploy Distributor
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address,address,address,uint256)" 0xE43CD84c93c12d0B613aB736F6b62DBbFaa2DF37 0x9523d80e515960a26cB787C5809CCF68ddAbCBDb 0x2daba5d558088f874110dbda520717d6c1947f42 12055988) 0x1E4332834d933e5B74312aafAb77D3901B00545B src/policies/Distributor.sol:Distributor

# Deploy Range (later)

# Deploy Roles
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address)" 0xE43CD84c93c12d0B613aB736F6b62DBbFaa2DF37) 0x6c12Bf970a2AC029f607547c86B8Be1531a9a4CF GoerliDaoRoles 

# Deploy Treasury 
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address)" 0xE43CD84c93c12d0B613aB736F6b62DBbFaa2DF37) 0x99c7ACE5C32444D64B6829AB7Ffc9Df36865d491 GoerliDaoTreasury 

# Deploy Bond Aggregator (before fixed term - related to Bond Protocol)
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address,address)" 0x96dEBE563Ac45450Bc1c647489658A74BBC8B094 0x86D9e2623D6fFFB1165A58379fE99613df77F17A) 0xfc7724823061Ce89d9514267De048deDae852DC6  src/policies/BondAggregator.sol:BondAggregator

# Deploy Roles Authority
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address,address)" 0xD358dA590f6fA5BF87b2580cD77B70808E297185 0x0000000000000000000000000000000000000000) 0x22058fa4a9594a22ef208cad79aec5235b980e96  src/v2/RolesAuthority.sol:RolesAuthority

# Deploy Fixed Term Bond
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address,address,address,address)" 0x96dEBE563Ac45450Bc1c647489658A74BBC8B094 0xfc7724823061ce89d9514267de048dedae852dc6 0x96dEBE563Ac45450Bc1c647489658A74BBC8B094 0x22058Fa4a9594a22eF208Cad79aeC5235B980E96) 0x0AA2b949fE0a58001833e468e31581ec53aCbC0b  src/v2/BondFixedTermTeller.sol:BondFixedTermTeller

# Deploy Fixed Term SDA
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address,address,address,address)" 0x0AA2b949fE0a58001833e468e31581ec53aCbC0b 0xfc7724823061ce89d9514267de048dedae852dc6 0x96dEBE563Ac45450Bc1c647489658A74BBC8B094 0x86D9e2623D6fFFB1165A58379fE99613df77F17A) 0x35C7C5Bf71381e39903f33A98810f51F47b28A34 src/policies/BondFixedTermSDA.sol:BondFixedTermSDA

# Deploy Bond Callback
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address,address,address)" 0xE43CD84c93c12d0B613aB736F6b62DBbFaa2DF37 0xfc7724823061ce89d9514267de048dedae852dc6 0x9523d80e515960a26cB787C5809CCF68ddAbCBDb) 0x674565b0DB3B0e597ef99fc67f2DBE5D10804cB4 BondCallback

# Deploy Operator (later?)

# Deploy Heart (later?)

# Deploy Price Config

# Deploy Roles Admin

# Deploy Emergency

# Deploy Treasury Custodian

# Deploy Parthenon (gov - later?)