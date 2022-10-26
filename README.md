# Olympus Bophades

Use yarn build to refresh deps.

Set up a foundry config in foundry.toml.

## SRC Directory Structure

```ml
├─ external - "External contracts needed for core functionality"
├─ interfaces - "Standard interfaces"
├─ libraries - "Libraries"
├─ modules - "Default framework modules"
│  ├─ AUTHR
│  ├─ INSTR
│  ├─ MINTR
│  ├─ PRICE
│  ├─ RANGE
│  ├─ TRSRY
├─ policies - "Default framework policies"
├─ test - "General test utilities and mocks/larps"
```

## Deployments

### Goerli Testnet

-   Kernel - [0x7fDdf40f4Dbbd0B66dF26ea8Ba9d0b539d64c0b5](https://goerli.etherscan.io/address/0x7fDdf40f4Dbbd0B66dF26ea8Ba9d0b539d64c0b5)

#### Modules

-   TRSRY - [0x91F9EE2074C2dC3B50d5242d0518AFE77938Cc87](https://goerli.etherscan.io/address/0x91F9EE2074C2dC3B50d5242d0518AFE77938Cc87)
-   MINTR - [0x437B9093d74a5ad6416c6F655929C34785a6d338](https://goerli.etherscan.io/address/0x437B9093d74a5ad6416c6F655929C34785a6d338)
-   PRICE - [0x6d39cDfa180974c5e1ac6FD325A1718F2Fd4412f](https://goerli.etherscan.io/address/0x6d39cDfa180974c5e1ac6FD325A1718F2Fd4412f)
-   RANGE - [0x9ECDA630626a3aa9EF24A53c4Faca1Ce76a1A508](https://goerli.etherscan.io/address/0x9ECDA630626a3aa9EF24A53c4Faca1Ce76a1A508)
-   INSTR - [0x7FB14e84c89F5bd93d3aB633C05d299eAD2455B2](https://goerli.etherscan.io/address/0x7FB14e84c89F5bd93d3aB633C05d299eAD2455B2)
-   ROLES - [0xf588E6028Aa49313ecDE72b3CeC3Fd0C5BE50F99](https://goerli.etherscan.io/address/0xf588E6028Aa49313ecDE72b3CeC3Fd0C5BE50F99)

#### Policies

-   BondCallback - [0xaBe5A8c818f7EA6fC4c2Ea2308E2B1ecd5b8f003](https://goerli.etherscan.io/address/0xaBe5A8c818f7EA6fC4c2Ea2308E2B1ecd5b8f003)
-   Heart - [0x699C3d1DbCF524506dd98aC483F78C9Ba0B5D1dE](https://goerli.etherscan.io/address/0x699C3d1DbCF524506dd98aC483F78C9Ba0B5D1dE)
-   Operator - [0x4099dACb7292138FA7d4C0e07Ff36930593D92a4](https://goerli.etherscan.io/address/0x4099dACb7292138FA7d4C0e07Ff36930593D92a4)
-   PriceConfig - [0x00e2A89ec10473FA5FDfF0a2EBB16eCE4D480777](https://goerli.etherscan.io/address/0x00e2A89ec10473FA5FDfF0a2EBB16eCE4D480777)
-   TreasuryCustodian - [0x5dC1B63A675365a00154FDD3B17C89b3491257f8](https://goerli.etherscan.io/address/0x5dC1B63A675365a00154FDD3B17C89b3491257f8)
-   Distributor - [0x65dDa32eafC1a0db338e302ffa4a714FbD82c4cD](https://goerli.etherscan.io/address/0x65dDa32eafC1a0db338e302ffa4a714FbD82c4cD)
-   RolesAdmin - [0xDa08D1dA7CcC756cfB62997c61C93Dd11b19e4F2](https://goerli.etherscan.io/address/0xDa08D1dA7CcC756cfB62997c61C93Dd11b19e4F2)
-   Faucet (Testnet only) - [0xA247156a39169c0FAFf979F57361CC734e82e3d0](https://goerli.etherscan.io/address/0xA247156a39169c0FAFf979F57361CC734e82e3d0)

#### Dependencies

-   OHM Token - [0x0595328847AF962F951a4f8F8eE9A3Bf261e4f6b](https://goerli.etherscan.io/address/0x0595328847af962f951a4f8f8ee9a3bf261e4f6b)
-   DAI Token - [0x41e38e70a36150D08A8c97aEC194321b5eB545A5](https://goerli.etherscan.io/address/0x41e38e70a36150d08a8c97aec194321b5eb545a5)
-   OHM-DAI Balancer LP Pool - [0xd8833594420dB3D6589c1098dbDd073f52419Dba](https://goerli.etherscan.io/address/0xd8833594420dB3D6589c1098dbDd073f52419Dba)
-   WETH Token (for keeper rewards) - [0x0Bb7509324cE409F7bbC4b701f932eAca9736AB7](https://goerli.etherscan.io/address/0x0bb7509324ce409f7bbc4b701f932eaca9736ab7)
-   Mock OHM/ETH Price Feed - [0x022710a589C9796dce59A0C52cA4E36f0a5e991A](https://goerli.etherscan.io/address/0x022710a589c9796dce59a0c52ca4e36f0a5e991a)
-   Mock DAI/ETH Price Feed - [0xdC8E4eD326cFb730a759312B6b1727C6Ef9ca233](https://goerli.etherscan.io/address/0xdc8e4ed326cfb730a759312b6b1727c6ef9ca233)
-   Bond Auctioneer - [0xaE73A94b94F6E7aca37f4c79C4b865F1AF06A68b](https://goerli.etherscan.io/address/0xae73a94b94f6e7aca37f4c79c4b865f1af06a68b)
-   Bond Teller - [0x36211a11f2DaC433Ae34Be898b173942b334dBD5](https://goerli.etherscan.io/address/0x36211a11f2dac433ae34be898b173942b334dbd5)
-   Bond Aggregator - [0xB4860B2c12C6B894B64471dFb5a631ff569e220e](https://goerli.etherscan.io/address/0xb4860b2c12c6b894b64471dfb5a631ff569e220e)

#### Privileged Testnet Accounts

-   Executor - 0x83D0f479732CC605225263F1AB7016309475aDd9 (PK: 71270e81b91f27d411b9c0cc7d75e2cc5c50df28a0a01e0fd7b432bff5a64ffe)
-   Guardian - 0x19518E4D4E542f4b0Fc27366C23FaC7a0bA491Da (PK: 0882aadfaa5053e58924f45a7c68bc5f96c5260dfffc8eac20df816b968c2003)
-   Policy - 0x2694C41588A5C92a0dcddBBB778fb18c5cE16D1D (PK: 2a944c921eb69bd6f1ecc289179a37a91d794d32928c8cd77e43915919933e56)
