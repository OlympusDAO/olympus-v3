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

-   Kernel - [0x9E8eBfb1aC16B29f55DEa9B67C610a126AA2AAEd](https://goerli.etherscan.io/address/0x9E8eBfb1aC16B29f55DEa9B67C610a126AA2AAEd)

#### Modules

-   TRSRY - [0x4B253Ba186B76Ddb33C076bD6da27Ff6c2D6cDCf](https://goerli.etherscan.io/address/0x4B253Ba186B76Ddb33C076bD6da27Ff6c2D6cDCf)
-   MINTR - [0xC0Ad7066d848088B02efCB718A50bf967AbF4473](https://goerli.etherscan.io/address/0xC0Ad7066d848088B02efCB718A50bf967AbF4473)
-   PRICE - [0xBdeb1E1114AED0C13EE13df89a378F0ECa1A2518](https://goerli.etherscan.io/address/0xBdeb1E1114AED0C13EE13df89a378F0ECa1A2518)
-   RANGE - [0x923762c4BC5CbcB278907ee2e2207916938AF474](https://goerli.etherscan.io/address/0x923762c4BC5CbcB278907ee2e2207916938AF474)
-   INSTR - [0xc7Ca3CC84889053486298F52347C6563DaD33B5d](https://goerli.etherscan.io/address/0xc7Ca3CC84889053486298F52347C6563DaD33B5d)
-   ROLES - [0x1acd5097593A6F398EF07E52C0627d91c8D2d3ed](https://goerli.etherscan.io/address/0x1acd5097593A6F398EF07E52C0627d91c8D2d3ed)

#### Policies

-   BondCallback - [0xF75dEBAa512EEE4217533Ca3FaF61950A60d7d0e](https://goerli.etherscan.io/address/0xF75dEBAa512EEE4217533Ca3FaF61950A60d7d0e)
-   Heart - [0x08B41de3647Ae02D5749814411314C32E1854d19](https://goerli.etherscan.io/address/0x08B41de3647Ae02D5749814411314C32E1854d19)
-   Operator - [0x3b01DAE0C0c24366FE9dEc2A93ae44d586B7afD6](https://goerli.etherscan.io/address/0x3b01DAE0C0c24366FE9dEc2A93ae44d586B7afD6)
-   PriceConfig - [0x9E56edDd1D6F22047AcD722A185a2C66963C8d2F](https://goerli.etherscan.io/address/0x9E56edDd1D6F22047AcD722A185a2C66963C8d2F)
-   TreasuryCustodian - [0x7BDA8f77af66aec12aB4D69342512C9D36B70cDe](https://goerli.etherscan.io/address/0x7BDA8f77af66aec12aB4D69342512C9D36B70cDe)
-   Distributor - [0x1F3417581C6a5E6F680b22fec85E57B457a6A794](https://goerli.etherscan.io/address/0x1F3417581C6a5E6F680b22fec85E57B457a6A794)
-   RolesAdmin - [0xF9a3420DbD332a609f9b7f091dd38fd58f73E9a6](https://goerli.etherscan.io/address/0xF9a3420DbD332a609f9b7f091dd38fd58f73E9a6)
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
