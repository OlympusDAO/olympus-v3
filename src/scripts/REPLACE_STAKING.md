# Replace sOHM/Staking Contracts on Sepolia

## Overview

This document describes how to replace the legacy staking contracts (sOHM, gOHM, Staking) and all dependent Bophades contracts on Sepolia to update the sOHM index to the mainnet value (269.24).

The sOHM index is immutable after initialization, so changing it requires deploying entirely new contracts.

## Contracts Replaced

### Legacy Contracts (olympus-contracts)

| Contract | Reason                                     | Address (Old)                                |
| -------- | ------------------------------------------ | -------------------------------------------- |
| sOHM     | Index is immutable after initialization    | `0x89631595649Cc6dEBa249A8012a5b2d88C8ddE48` |
| gOHM     | Already migrated, sOHM reference immutable | `0xBA05d48Fb94dC76820EB7ea1B360fd6DfDEabdc5` |
| Staking  | sOHM/gOHM references are immutable         | `0x40a5F12aD1114608037ce80f028DDCF7C922Ef07` |

### Bophades Modules

| Contract                     | Reason                              | Address (Old)                                |
| ---------------------------- | ----------------------------------- | -------------------------------------------- |
| OlympusGovDelegation (DLGTE) | `_gOHM` is immutable in constructor | `0xca59A85a9B87cba6c706d12E60C1CB4ea61e97C9` |

### Bophades Policies

| Contract              | Reason                                                     | Address (Old)                                |
| --------------------- | ---------------------------------------------------------- | -------------------------------------------- |
| CoolerV2LtvOracle     | `_COLLATERAL_TOKEN` (gOHM) and `_DEBT_TOKEN` are immutable | `0x1Cb7f32fF640fC4a2A161c3d1f1a188a6670787d` |
| CoolerV2 (MonoCooler) | `_COLLATERAL_TOKEN`, `_OHM`, `_STAKING` are immutable      | `0x19b787549A05f7a3f8f20ED55B827A6c49BaEE9c` |
| Clearinghouse         | `gohm`, `ohm`, `staking` are immutable                     | `0x71b8f7c55C799182CC4351a20851A0214baE0ff7` |
| ZeroDistributor       | `staking` is immutable                                     | `0x0db48Fa20894273cF6bB559644d63713E98FE67b` |
| EmissionManager       | `gohm` is immutable                                        | `0x84785E392BfD02F97A9b84F85d86DEc11933ef81` |

### Contracts NOT Replaced

| Contract                     | Reason                                               |
| ---------------------------- | ---------------------------------------------------- |
| CoolerV2TreasuryBorrower     | Uses USDS/sUSDS, not gOHM/OHM                        |
| OlympusClearinghouseRegistry | No immutable token refs, just needs new CH activated |
| V1Migrator                   | Not deployed on Sepolia                              |
| Distributor                  | Not deployed on Sepolia                              |
| Burner                       | Not deployed on Sepolia                              |
| BLVault\* contracts          | Not deployed on Sepolia                              |

## Prerequisites

-   Foundry installed
-   `.env` file with:
    -   `ALCHEMY_API_KEY` - Alchemy API key for RPC access
    -   `PRIVATE_KEY` - Private key for executor address (`0x1A5309F208f161a393E8b5A253de8Ab894A67188`)
-   Clone of `olympus-contracts` repo: https://github.com/OlympusDAO/olympus-contracts

---

## Environment Setup

Ensure your `.env` file contains:

```bash
ALCHEMY_API_KEY=your_alchemy_api_key
PRIVATE_KEY=your_executor_private_key
```

Source the environment:

```bash
source .env
```

### Anvil Fork (Optional)

For local testing, start an Anvil fork of Sepolia:

```bash
# Terminal 1: Start Anvil fork
anvil --fork-url https://eth-sepolia.g.alchemy.com/v2/$ALCHEMY_API_KEY --chain-id 11155111

# Terminal 2: Override PRIVATE_KEY with Anvil's default account
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

Notes:

-   Scripts detect the chain from `block.chainid` and use the appropriate RPC URL
-   Anvil uses account 0's publicly known key
-   Can impersonate any address using `--from` with `cast`
-   Reset state by restarting Anvil and running `git checkout src/scripts/env.json`

---

## Configuration Reference

| Parameter      | Value                                        | Source           |
| -------------- | -------------------------------------------- | ---------------- |
| Index          | 269238508004                                 | Mainnet          |
| Epoch Length   | 28800 (8 hrs)                                | Standard         |
| Test OHM       | 1,000 OHM                                    | For staking test |
| KernelExecutor | `0x1A5309F208f161a393E8b5A253de8Ab894A67188` | env.json         |

## Key Addresses (Sepolia)

### Legacy Contracts

| Contract         | Address                                      |
| ---------------- | -------------------------------------------- |
| OHM              | `0x784cA0C006b8651BAB183829A99fA46BeCe50dBc` |
| Treasury (V2)    | `0x7D7406e4E5Fdb636C888cF17aBb42B5edE8B3722` |
| OlympusAuthority | `0x81057Bef097462957B9388D8DCB7D4AB0699cADB` |

### Bophades Core

| Contract       | Address                                      |
| -------------- | -------------------------------------------- |
| Kernel         | `0x4b0BBa51cE44175a9766f7e55e3d122a9F4BE78E` |
| KernelExecutor | `0x1A5309F208f161a393E8b5A253de8Ab894A67188` |

### Modules

| Contract                     | Address                                      |
| ---------------------------- | -------------------------------------------- |
| MINTR                        | `0x203C46cbB4FCC18977f521a9f7fdE007E1A564f6` |
| ROLES                        | `0xEdd6ebFFeD7D29947957d096dd55e82F523ceb86` |
| OlympusClearinghouseRegistry | `0x38038bdd78602e5AA2accd0Ce07557369e21a6c1` |

### Policies

| Contract                 | Address                                      |
| ------------------------ | -------------------------------------------- |
| RolesAdmin               | `0xf33133E5356B9534e794468dAcD424D11007f1cF` |
| Minter                   | `0x556B5fA9f8aa6E38e5E8FB0AD9Cb978bcAf33913` |
| CoolerV2TreasuryBorrower | `0x74FeAEde88962139f4d36A2f1998BcF56088d519` |

### External Contracts

| Contract                     | Address                                      |
| ---------------------------- | -------------------------------------------- |
| CoolerFactory                | `0x6F448eA89cD897ad1aEdB5Cd8Bf221d50B9A7C6C` |
| sDAI                         | `0xefffab0Aa61828c4af926E039ee754e3edE10dAc` |
| USDS                         | `0xDd668BdDb4241F4fAFBB0BC0d75b49EbEE88B4FC` |
| BondFixedTermAuctioneer      | `0x007A66A2a13415DB3613C1a4dd1C942A285902d1` |
| BondFixedTermTeller          | `0x007F7735baF391e207E3aA380bb53c4Bd9a5Fed6` |
| ConvertibleDepositAuctioneer | `0x247f1989aDc0F63D07b91Bf645De879b9de06fbB` |

---

## Step 1: Deploy Legacy Contracts from olympus-contracts Repo

The legacy contracts (sOHM, gOHM, Staking) must be deployed from the `olympus-contracts` repository since they require Solidity 0.7.5.

We use a **custom deployment script** to deploy only the necessary contracts (sOHM, gOHM, Staking) with the exact mainnet index.

### 1a. Clone and Setup olympus-contracts

```bash
git clone https://github.com/OlympusDAO/olympus-contracts.git
cd olympus-contracts
git checkout sepolia # Has updated dependencies and Sepolia config
npm
```

### 1b. Configure Network

Add sepoliaAnvil network to `hardhat.config.ts` (required for Anvil fork):

```typescript
// In hardhat.config.ts, add to networks section:
sepoliaAnvil: {
    url: "http://127.0.0.1:8545",
    chainId: 11155111  // Match Anvil's --chain-id
}
```

### 1c. Create Deployment Script

Create `scripts/deploy-staking-only.js` in the olympus-contracts repo:

```javascript
// scripts/deploy-staking-only.js
// Deploys only sOHM, gOHM, and Staking contracts (no other legacy contracts)
const {ethers} = require("hardhat");

async function main() {
    const INDEX = 269238508004; // Exact mainnet index
    const EPOCH_LENGTH = 28800; // 8 hours
    const OHM = "0x784cA0C006b8651BAB183829A99fA46BeCe50dBc";
    const TREASURY = "0x7D7406e4E5Fdb636C888cF17aBb42B5edE8B3722";
    const AUTHORITY = "0x81057Bef097462957B9388D8DCB7D4AB0699cADB";

    const [deployer] = await ethers.getSigners();
    console.log("Deploying with:", deployer.address);
    console.log("Network:", network.name);

    // Deploy sOHM
    console.log("\n--- Deploying sOHM ---");
    const SOHM = await ethers.getContractFactory("sOlympus");
    const sOHM = await SOHM.deploy();
    await sOHM.deployed();
    console.log("sOHM deployed:", sOHM.address);

    // Set index
    console.log("\n--- Setting Index ---");
    await sOHM.setIndex(INDEX);
    console.log("Index set to:", INDEX);

    // Deploy gOHM
    console.log("\n--- Deploying gOHM ---");
    const GOHM = await ethers.getContractFactory("gOHM");
    const gOHM = await GOHM.deploy(deployer.address, sOHM.address);
    await gOHM.deployed();
    console.log("gOHM deployed:", gOHM.address);

    // Deploy Staking
    console.log("\n--- Deploying Staking ---");
    const Staking = await ethers.getContractFactory("OlympusStaking");
    const staking = await Staking.deploy(
        OHM,
        sOHM.address,
        gOHM.address,
        EPOCH_LENGTH,
        0,
        Math.floor(Date.now() / 1000),
        AUTHORITY,
    );
    await staking.deployed();
    console.log("Staking deployed:", staking.address);

    // Set gOHM on sOHM
    console.log("\n--- Configuring Contracts ---");
    await sOHM.setgOHM(gOHM.address);
    console.log("gOHM set on sOHM");

    // Initialize sOHM
    await sOHM.initialize(staking.address, TREASURY);
    console.log("sOHM initialized");

    // Migrate gOHM
    await gOHM.migrate(staking.address, sOHM.address);
    console.log("gOHM migrated");

    console.log("\n========================================");
    console.log("         DEPLOYMENT SUMMARY");
    console.log("========================================");
    console.log("sOHM:    ", sOHM.address);
    console.log("gOHM:    ", gOHM.address);
    console.log("Staking: ", staking.address);
    console.log("Index:   ", INDEX);
    console.log("========================================");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
```

### 1d. Run Deployment

Ensure environment is sourced (see Environment Setup).

**Sepolia:**

```bash
npx hardhat run scripts/deploy-staking-only.js --network sepolia
```

**Anvil Fork:**

```bash
# Ensure Anvil is running (see Environment Setup)
npx hardhat run scripts/deploy-staking-only.js --network localhost
```

Record the deployed addresses (sOHM, gOHM, Staking).

---

## Step 2: Update env.json and Verify

### 2a. Update env.json

Add the deployed addresses to `src/scripts/env.json`:

```json
{
    "current": {
        "sepolia": {
            "olympus": {
                "legacy": {
                    "Staking": "0x...",
                    "gOHM": "0x...",
                    "sOHM": "0x..."
                }
            }
        }
    }
}
```

### 2b. Verify Contracts

Run the verification script:

```bash
forge script src/scripts/ops/VerifyLegacyStaking.s.sol:VerifyLegacyStaking \
    --rpc-url sepolia \
    -vvv
```

**Anvil Fork:**

```bash
forge script src/scripts/ops/VerifyLegacyStaking.s.sol:VerifyLegacyStaking \
    --rpc-url http://localhost:8545 \
    -vvv
```

This script:

-   Reads sOHM, gOHM, Staking addresses from env.json
-   Verifies sOHM index is set correctly (269238508004)
-   Verifies all contract references are correct

---

## Step 3: Setup Minter Permissions

Grant `minter_admin` role to the executor address if not already granted:

**Using cast wallet:**

```bash
./shell/roles/grantRole.sh \
    --role minter_admin \
    --to 0x1A5309F208f161a393E8b5A253de8Ab894A67188 \
    --chain sepolia \
    --account <<wallet>> \
    --broadcast true
```

**Using Ledger:**

```bash
./shell/roles/grantRole.sh \
    --role minter_admin \
    --to 0x1A5309F208f161a393E8b5A253de8Ab894A67188 \
    --chain sepolia \
    --ledger <<index>> \
    --broadcast true
```

**Anvil Fork:**

```bash
./shell/roles/grantRole.sh \
    --role minter_admin \
    --to 0x1A5309F208f161a393E8b5A253de8Ab894A67188 \
    --chain http://localhost:8545 \
    --account <<wallet>> \
    --broadcast true
```

Note: The `test` mint category will be added automatically by the ReplaceStaking script if it doesn't exist.

---

## Step 4: Deploy New Bophades Contracts

Deploy new module and policies:

**Using cast wallet:**

```bash
forge script src/scripts/ops/ReplaceStaking.s.sol:ReplaceStaking \
    --rpc-url sepolia \
    --account <<wallet>> \
    --sender 0x1A5309F208f161a393E8b5A253de8Ab894A67188 \
    --broadcast \
    --verify \
    -vvv
```

**Using Ledger:**

```bash
forge script src/scripts/ops/ReplaceStaking.s.sol:ReplaceStaking \
    --rpc-url sepolia \
    --ledger \
    --mnemonic-indexes <<index>> \
    --sender 0x1A5309F208f161a393E8b5A253de8Ab894A67188 \
    --broadcast \
    --verify \
    -vvv
```

**Anvil Fork:**

```bash
forge script src/scripts/ops/ReplaceStaking.s.sol:ReplaceStaking \
    --rpc-url http://localhost:8545 \
    --account <<account>> \
    --sender 0x1A5309F208f161a393E8b5A253de8Ab894A67188 \
    --broadcast \
    -vvv
```

This script:

### Phase 1: Deactivate Old Policies

-   Deactivates old MonoCooler, Clearinghouse, ZeroDistributor, EmissionManager, LtvOracle

### Phase 2: Upgrade DLGTE Module

-   Deploys new `OlympusGovDelegation` (DLGTE) with new gOHM address
-   Upgrades module in Kernel

### Phase 3: Deploy New Policies

-   Deploys new `CoolerV2LtvOracle` with new gOHM as collateral
-   Deploys new `MonoCooler` (CoolerV2) with new gOHM and Staking
-   Deploys new `Clearinghouse` with new gOHM and Staking
-   Deploys new `ZeroDistributor` with new Staking
-   Deploys new `EmissionManager` with new gOHM

### Phase 4: Activate New Policies

-   Activates all new policies in Kernel

### Phase 5: Test Staking

-   Mints 1,000 OHM to the deployer
-   Approves Staking to spend OHM
-   Stakes OHM to receive gOHM
-   Verifies that staking is working correctly

### Phase 6: Update env.json

-   Automatically updates all policy addresses

### Phase 7: Verify Deployment

-   Verifies sOHM and gOHM indices
-   Verifies new MonoCooler is active in Kernel
-   Verifies old MonoCooler is deactivated

---

## Deployment Order Summary

```
1. olympus-contracts repo (0.7.5)
   └── Deploy sOHM → gOHM → Staking → setIndex → setgOHM → initialize → migrate
   └── Add addresses to env.json

2. Bophades repo - VerifyLegacyStaking (0.8.15)
   └── Reads from env.json → Verifies on-chain configuration
   └── Usage: forge script src/scripts/ops/VerifyLegacyStaking.s.sol --rpc-url sepolia

3. Bophades repo - ReplaceStaking (0.8.15)
   ├── Phase 1: Deactivate old policies
   ├── Phase 2: Upgrade DLGTE module
   ├── Phase 3: Deploy new policies
   ├── Phase 4: Activate new policies
   ├── Phase 5: Test staking (mint and stake sample OHM)
   ├── Phase 6: Update env.json
   └── Phase 7: Verify deployment
```

---

## Troubleshooting

### "sOHM index not set correctly"

The sOHM `setIndex()` function can only be called once. If the index is wrong, you must redeploy sOHM.

### "Minter_CategoryNotApproved" or "ROLES_RequireRole"

The script automatically adds the `test` category if it doesn't exist. If this fails, ensure the executor has `minter_admin` role (see Step 3).

### "Kernel_OnlyExecutor"

The script must be run from the executor address (`0x1A5309F208f161a393E8b5A253de8Ab894A67188`). Ensure `--sender` is set correctly.

### "Insufficient OHM balance in contract"

Staking needs OHM balance for `unstake()`. Ensure Phase 5 (staking test) completed successfully.

---

## Notes

-   **Existing positions will be lost**: Old MonoCooler loans and Clearinghouse positions will not be migrated. This is acceptable for a testnet.
-   **gOHM holders**: Existing gOHM tokens on Sepolia will reference the old sOHM contract and will not work with the new staking system. Users will need new gOHM.
-   **env.json**: Manually update env.json after Step 1. ReplaceStaking automatically updates policy addresses.
-   **CoolerV2TreasuryBorrower**: Does NOT need redeployment - it only uses USDS/sUSDS, not gOHM or OHM.
```
