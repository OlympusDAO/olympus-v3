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

-   Kernel - [0xD39e18BDaDa92a808b027b868dFF49F967Faf43b](https://goerli.etherscan.io/address/0xD39e18BDaDa92a808b027b868dFF49F967Faf43b)

#### Modules

-   TRSRY - [0xC57d528ccD28B9075E2850A8A2845dec094C25f4](https://goerli.etherscan.io/address/0xC57d528ccD28B9075E2850A8A2845dec094C25f4)
-   MINTR - [0xf8FEc699ed778aea53324101f5c52DaD45DF7053](https://goerli.etherscan.io/address/0xf8FEc699ed778aea53324101f5c52DaD45DF7053)
-   PRICE - [0x60421d7FD7AcD732384b1AB157F81a81E65296Ec](https://goerli.etherscan.io/address/0x60421d7FD7AcD732384b1AB157F81a81E65296Ec)
-   RANGE - [0xF4D2b752F1936fa69b98ab49BFD92EaEBdE4D266](https://goerli.etherscan.io/address/0xF4D2b752F1936fa69b98ab49BFD92EaEBdE4D266)
-   ROLES - [0x65A036AF60bbC94c868E9E95D50b6981C4260b89](https://goerli.etherscan.io/address/0x65A036AF60bbC94c868E9E95D50b6981C4260b89)

#### Policies

-   BondCallback - [0x79D3387fBf564663F3Ae6f7CEaab3D4f2cBA7744](https://goerli.etherscan.io/address/0x79D3387fBf564663F3Ae6f7CEaab3D4f2cBA7744)
-   Heart - [0xAe5f66B7bc71625b3AD3EE65Ec04512c9Cfe379d](https://goerli.etherscan.io/address/0xAe5f66B7bc71625b3AD3EE65Ec04512c9Cfe379d)
-   Operator - [0x0E37549093CB786C2584eceCb0A96497fCD2aBA0](https://goerli.etherscan.io/address/0x0E37549093CB786C2584eceCb0A96497fCD2aBA0)
-   PriceConfig - [0xf1b31a45c7e4BE21eb9B090eF86DB9d12850345C](https://goerli.etherscan.io/address/0xf1b31a45c7e4BE21eb9B090eF86DB9d12850345C)
-   TreasuryCustodian - [0xF7364d1752a0D914fB9642eD613D725fD8a8cA46](https://goerli.etherscan.io/address/0xF7364d1752a0D914fB9642eD613D725fD8a8cA46)
-   Distributor - [0x54B5BB535F2A013E2B9803F356B8B7a28a564cF7](https://goerli.etherscan.io/address/0x54B5BB535F2A013E2B9803F356B8B7a28a564cF7)
-   RolesAdmin - [0xa44602EA20012763b4f0AFdF6e8aD4f9563E7275](https://goerli.etherscan.io/address/0xa44602EA20012763b4f0AFdF6e8aD4f9563E7275)
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
