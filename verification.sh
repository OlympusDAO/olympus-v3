# Kernel deployment verification script (Sepolia)
forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor()") 0xe43cd84c93c12d0b613ab736f6b62dbbfaa2df37 Kernel

forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address)" 0xD358dA590f6fA5BF87b2580cD77B70808E297185) 0xBACDCB0151A00Dd7c1aEFbbbEc378939E41BfC76 TestGDAO

forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(uint256)" 11155111) 0x85983eb365f7159ed6Adf1b130919c1b962cCfA7 DAI

forge verify-contract --chain-id 11155111 --flatten --watch --compiler-version "v0.8.15+commit.e14f2714" --constructor-args $(cast abi-encode "constructor(address,address,address,uint256,uint256,uint256,uint256)" 0xE43CD84c93c12d0B613aB736F6b62DBbFaa2DF37 0xBACDCB0151A00Dd7c1aEFbbbEc378939E41BfC76 0x85983eb365f7159ed6Adf1b130919c1b962cCfA7 1000000000000000000 1000000000000000 10000000000000000000000000 360) 0x7fc386c00D7Edd66D5fE70352Ee2427515f967F5 Faucet

