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

### Goerli Testnet (without Governance)

- Kernel - [0x3B294580Fcf1F60B94eca4f4CE78A2f52D23cC83](https://goerli.etherscan.io/address/0x3b294580fcf1f60b94eca4f4ce78a2f52d23cc83)

#### Modules

- AUTHR - [0x81D58CcDCA69dd70A498b543cAA2c61D274ad9A3](https://goerli.etherscan.io/address/0x81d58ccdca69dd70a498b543caa2c61d274ad9a3)
- TRSRY - [0x994DfcA46AB23383D8ee6B7ceAE16B725d79f503](https://goerli.etherscan.io/address/0x994dfca46ab23383d8ee6b7ceae16b725d79f503)
- MINTR - [0xf2dFC1BE91dE38F5420DEa2fC1621Fba823c61BE](https://goerli.etherscan.io/address/0xf2dfc1be91de38f5420dea2fc1621fba823c61be)
- PRICE - [0x69a3c50efD5214538389dd7443a0325be55D9D51](https://goerli.etherscan.io/address/0x69a3c50efd5214538389dd7443a0325be55d9d51)
- RANGE - [0x8642DBA4B43aB5d485F57677D6605FfE9aeEe2c5](https://goerli.etherscan.io/address/0x8642dba4b43ab5d485f57677d6605ffe9aeee2c5)

#### Policies

- BondCallback - [0x308fD958B191fdAEa000a1c0c5A2EB6FceB31DeD](https://goerli.etherscan.io/address/0x308fd958b191fdaea000a1c0c5a2eb6fceb31ded)
- Heart - [0x5358D5b1A170D49a23C61B158CC75e7f060a8134](https://goerli.etherscan.io/address/0x5358d5b1a170d49a23c61b158cc75e7f060a8134)
- Operator - [0xcC57b829CC36D8FD121C85a19541883ccaA256b6](https://goerli.etherscan.io/address/0xcc57b829cc36d8fd121c85a19541883ccaa256b6)
- PriceConfig - [0xE5103B14DC6d93b356745Da23A93546f1217c9fc](https://goerli.etherscan.io/address/0xe5103b14dc6d93b356745da23a93546f1217c9fc)

#### Dependencies

- OHM Token - [0x0595328847AF962F951a4f8F8eE9A3Bf261e4f6b](https://goerli.etherscan.io/address/0x0595328847af962f951a4f8f8ee9a3bf261e4f6b)
- DAI Token - [0x41e38e70a36150D08A8c97aEC194321b5eB545A5](https://goerli.etherscan.io/address/0x41e38e70a36150d08a8c97aec194321b5eb545a5)
- WETH Token (for keeper rewards) - [0x0Bb7509324cE409F7bbC4b701f932eAca9736AB7](https://goerli.etherscan.io/address/0x0bb7509324ce409f7bbc4b701f932eaca9736ab7)
- Mock OHM/ETH Price Feed - [0x769435458365Fef4C14aCE998A0ff6AB29c376Ff](https://goerli.etherscan.io/address/0x769435458365fef4c14ace998a0ff6ab29c376ff)
- Mock DAI/ETH Price Feed - [0x63dC91F5efAbf0c49C5a0b1f573B23A4aD40e3aA](https://goerli.etherscan.io/address/0x63dc91f5efabf0c49c5a0b1f573b23a4ad40e3aa)
- Bond Auctioneer - [0x130a364655c5889D665caBa74FbD3bFa1448b99B](https://goerli.etherscan.io/address/0x130a364655c5889D665caBa74FbD3bFa1448b99B)
- Bond Aggregator - [0xaD0752111901b2C0A2062c015592B1098B654458](https://goerli.etherscan.io/address/0xad0752111901b2c0a2062c015592b1098b654458)

#### Privileged Testnet Accounts

- Executor - 0x83D0f479732CC605225263F1AB7016309475aDd9 (PK: 71270e81b91f27d411b9c0cc7d75e2cc5c50df28a0a01e0fd7b432bff5a64ffe)
- Guardian - 0x19518E4D4E542f4b0Fc27366C23FaC7a0bA491Da (PK: 0882aadfaa5053e58924f45a7c68bc5f96c5260dfffc8eac20df816b968c2003)
- Policy - 0x2694C41588A5C92a0dcddBBB778fb18c5cE16D1D (PK: 2a944c921eb69bd6f1ecc289179a37a91d794d32928c8cd77e43915919933e56)
