
# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

script-mainnet:
        forge script script/NFT.s.sol:MyScript --rpc-url ${RINKEBY_RPC_URL}  --private-key ${PRIVATE_KEY} --broadcast --verify --etherscan-api-key ${ETHERSCAN_KEY} -vvvv
		