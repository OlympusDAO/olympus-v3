# Kernel deployment verification script (Sepolia)
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor()") 0xe43cd84c93c12d0b613ab736f6b62dbbfaa2df37 Kernel

# Test GDAO deployment verification script (Sepolia)
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address)" 0xD358dA590f6fA5BF87b2580cD77B70808E297185) 0xBACDCB0151A00Dd7c1aEFbbbEc378939E41BfC76 TestGDAO

# Test DAI deployment verification script (Sepolia)
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(uint256)" 11155111) 0x85983eb365f7159ed6Adf1b130919c1b962cCfA7 DAI

# Faucet deployment verification script (Sepolia)
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address,address,address,uint256,uint256,uint256,uint256)" 0xE43CD84c93c12d0B613aB736F6b62DBbFaa2DF37 0xBACDCB0151A00Dd7c1aEFbbbEc378939E41BfC76 0x85983eb365f7159ed6Adf1b130919c1b962cCfA7 1000000000000000000 10000000000000 10000000000000000000000000 360) 0x7fc386c00D7Edd66D5fE70352Ee2427515f967F5 Faucet

# Mock UniV2 deployment verification script (Sepolia)
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address,address)" 0xBACDCB0151A00Dd7c1aEFbbbEc378939E41BfC76 0x85983eb365f7159ed6Adf1b130919c1b962cCfA7) 0xd3c17b8048bef5ffd853c9f31f73d0059e562737 MockUniV2Pair

# update Strong Faucet to 1000 GDAO
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address,address,address,uint256,uint256,uint256,uint256)" 0xE43CD84c93c12d0B613aB736F6b62DBbFaa2DF37 0xBACDCB0151A00Dd7c1aEFbbbEc378939E41BfC76 0x85983eb365f7159ed6Adf1b130919c1b962cCfA7 1000000000000000000 100000000000000000 10000000000000000000000000 360) 0xfA4760cf75AF273Ec064E066d3C36c9fbcD3918C StrongFaucet

# Mock Price Feed deployment
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor()") 0x7D6779618c40fD981Fe568d901A002099820A97e MockPriceFeed

# Mock Price deployment Sepolia
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address,uint48,uint256)" 0xE43CD84c93c12d0B613aB736F6b62DBbFaa2DF37 28800 10410000000000000000) 0x88737F128Ee902feB2a5Ad5ce4707536fed5A299 MockPrice

# Mock Policy Tests deployment Sepolia
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address)" 0xE43CD84c93c12d0B613aB736F6b62DBbFaa2DF37) 0x27a5df72fbf3795db58a44edab5170131b38426b MockPolicy

# Deploy xGDAO Sepolia
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor()") 0xFFbC5937d48afc21E0D514D1650ffc1e4B84e98C xGDAO

 # Deploy sGDAO Sepolia
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor()") 0xFFbC5937d48afc21E0D514D1650ffc1e4B84e98C xGDAO


