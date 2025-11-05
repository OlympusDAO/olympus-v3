# Emergency Shutdown Instructions

This document provides comprehensive information on how to shut down the Olympus protocol in the event of an emergency.

## Table of Contents

1. [Emergency Multisig Overview](#emergency-multisig-overview)
2. [Technical Requirements](#technical-requirements)
3. [When to Shutdown](#when-to-shutdown)
4. [Emergency Procedures](#emergency-procedures)
5. [Using the Shutdown Script](#using-the-shutdown-script)
6. [Component Shutdown Instructions](#component-shutdown-instructions)

---

## Emergency Multisig Overview

### What is the Emergency MS

The Emergency Multisig (Emergency MS) is a dedicated Safe multisig wallet with specific permissions to execute emergency shutdown procedures. It operates independently from the DAO Multisig (DAO MS) to ensure rapid response capability during critical situations.

### Address and Verification

The Emergency MS address is configured in `src/scripts/env.json` under the key `olympus.multisig.emergency`. The address varies by chain:

**Current Emergency MS Addresses:**

- **Mainnet**: `0xa8A6ff2606b24F61AFA986381D8991DFcCCd2D55`
- **Base**: `0x18a390bD45bCc92652b9A91AD51Aed7f1c1358f5` (same as DAO MS)
- **Base Sepolia**: `0x1A5309F208f161a393E8b5A253de8Ab894A67188` (same as DAO MS)
- **Berachain**: `0xa5ea62894027D981D34BB99A04BD36B818b2Aaf0`
- **Berachain Bartio**: `0x1A5309F208f161a393E8b5A253de8Ab894A67188` (same as DAO MS)
- **Sepolia**: See `src/scripts/env.json` for current configuration

**⚠️ Missing Emergency MS Addresses:**

The following chains are missing Emergency MS addresses (set to zero address) in `src/scripts/env.json`:
- **Arbitrum**: Currently `0x0000000000000000000000000000000000000000` - **ACTION REQUIRED**
- **Sepolia**: Some entries show `0x0000000000000000000000000000000000000000` - **ACTION REQUIRED**

**TODO Task**:
- [ ] Verify Emergency MS deployment status for Arbitrum
- [ ] Verify Emergency MS deployment status for Sepolia
- [ ] Configure Emergency MS addresses in `src/scripts/env.json` for all chains where the protocol is deployed
- [ ] Update this documentation once Emergency MS addresses are configured

**Note**: Emergency shutdown procedures cannot be executed on chains without a configured Emergency MS address. Use DAO MS for these chains until Emergency MS is deployed and configured.

**Important**: Always verify the Emergency MS address before executing shutdown procedures. You can verify the address by:
1. Checking the `env.json` file
2. Verifying on the [Protocol Visualizer](https://olympus-protocol-visualizer.up.railway.app)
3. Confirming with the protocol team

### Role Assignments and Permissions

For detailed information about all roles in the protocol, see [ROLES.md](../../ROLES.md).

The Emergency MS has been granted the following roles:

- `emergency_shutdown` - Allows shutdown of TRSRY withdrawals, MINTR minting
- `emergency` - Allows shutdown of Cooler V2 operations (borrows and liquidations), CCIP CrossChainBridge, Heart, EmissionManager and Convertible Deposits

The Emergency MS does **not** have access to:
- `bridge_admin` (LayerZero CrossChainBridge)
- `loop_daddy` (YieldRepurchaseFacility)
- `reserve_migrator_admin` (ReserveMigrator)

These require the DAO MS or OCG Timelock.

### Access Requirements

To execute shutdown procedures using the Emergency MS:
1. You must be a signer on the Emergency MS
2. You must have access to a wallet configured with `cast` or a Ledger device
3. You must have the private key or Ledger device available
4. The Emergency MS must have sufficient signers available to meet threshold requirements

---

## Technical Requirements

### Required Software

The following software must be installed and configured:

1. **Foundry** - For running batch scripts
   - Install: `curl -L https://foundry.paradigm.xyz | bash`
   - Verify: `forge --version` and `cast --version`

2. **Bash** - Shell interpreter (typically pre-installed on macOS/Linux)
   - Verify: `bash --version`

3. **Node.js and pnpm** - For project dependencies
   - Install Node.js: [nodejs.org](https://nodejs.org/)
   - Install pnpm: `npm install -g pnpm`

### Wallet Setup Options

You have two options for signing transactions:

#### Option 1: Ledger Device (Recommended for Security)

**This is the recommended option** as it provides hardware-level security for private keys.

1. **Connect your Ledger** device and unlock it
2. **Determine your Ledger index**:
   - The Ledger index starts at 0 for the first account
   - To find your index, you can:
     - Check in Ledger Live or Rabby wallet software (the account order corresponds to the index)
     - Or verify the address matches your Emergency MS signer address using:
       ```bash
       cast wallet address --ledger --mnemonic-index 0
       ```
       Try different indices (0, 1, 2, etc.) until you find the matching address
     - First account (default): index `0`
     - Second account: index `1`
     - Third account: index `2`
     - And so on...

3. **Configure in `.env.emergency`** (optional):
   ```bash
   echo "LEDGER_INDEX=0" > .env.emergency
   ```
   Replace `0` with your actual account index.

#### Option 2: Cast Wallet (Not Recommended - Security Risk)

**⚠️ Security Warning**: Using cast wallet requires storing private keys on disk, which poses a significant security risk. Only use this option if Ledger is unavailable and you understand the security implications.

1. **Import a wallet**:
   ```bash
   cast wallet import <wallet-name> --interactive
   ```
   You will be prompted to enter your private key.

2. **Verify wallet address**:
   ```bash
   cast wallet address <wallet-name>
   ```

3. **List available wallets**:
   ```bash
   cast wallet list
   ```

**Security Note**: Private keys are stored in `~/.foundry/keystores/`. Ensure proper file permissions and consider using encrypted storage. **This method is not recommended for production use.**

### Environment Configuration

#### `.env.emergency` File (Optional)

Create a `.env.emergency` file in the project root to automatically configure your account for emergency operations:

```bash
# .env.emergency
ACCOUNT=<cast-wallet-name>
# OR
LEDGER_INDEX=<mnemonic-index>
```

If this file exists, the shutdown script will automatically use the configured account or Ledger index.

#### Required Environment Variables

The following environment variables must also be set (either in `.env.emergency` or as shell variables):

- `RPC_URL` - RPC endpoint for the target chain (e.g., `https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY`)

### Network Access Requirements

- Stable internet connection
- Access to an Ethereum RPC endpoint (Infura, Alchemy, or self-hosted node)
- Ability to connect to the target blockchain network

### Prerequisites Checklist

Before executing shutdown procedures, verify:

- [ ] Foundry is installed and up to date
- [ ] Wallet is configured (cast wallet or Ledger)
- [ ] `.env.emergency` file is configured (optional but recommended)
- [ ] RPC endpoint is accessible
- [ ] You are a signer on the Emergency MS
- [ ] Emergency MS has sufficient signers available
- [ ] You have tested the connection with a simulation (without `--broadcast`)

---

## When to Shutdown

### General Protocol-Level Guidance

Shutdown procedures should be initiated when:

1. **Critical Vulnerabilities**
   - Active exploit detected
   - Code vulnerability that could lead to fund loss
   - Access control bypasses

2. **Infinite Mint Bugs**
   - Unauthorized minting capability
   - Broken minting controls
   - Oracle manipulation leading to infinite minting

3. **Oracle Failures**
   - Price oracle manipulation
   - Stale or incorrect price feeds
   - Oracle downtime affecting critical operations

4. **Bridge Exploits**
   - Cross-chain bridge vulnerabilities
   - Unauthorized bridging
   - Bridge contract compromises

5. **Governance Attacks**
   - Unauthorized governance actions
   - Compromised governance contracts
   - Malicious proposals being executed

### Per-Contract Specific Guidance

#### TRSRY (Treasury)
- **Shutdown when**: Unauthorized withdrawals detected, treasury contract compromised
- **Severity**: Critical - Immediate shutdown required if funds are at risk

#### MINTR (Minter)
- **Shutdown when**: Unauthorized minting detected, minting controls bypassed
- **Severity**: Critical - Immediate shutdown required to prevent infinite supply

#### Cooler V2
- **Shutdown when**:
  - Collateral oracle manipulation
  - Borrowing exploit detected
  - Liquidation mechanism compromised
- **Severity**: High - Shutdown if active exploit or immediate risk

#### EmissionManager
- **Shutdown when**: Bond market manipulation, incorrect emission calculations
- **Severity**: High - Shutdown if affecting protocol stability

#### Convertible Deposits
- **Shutdown when**: Auction mechanism exploited, conversion price manipulation
- **Severity**: Medium-High - Shutdown if affecting user funds or protocol stability

#### CCIP Bridge
- **Shutdown when**: Bridge exploit detected, unauthorized cross-chain transfers
- **Severity**: Critical - Immediate shutdown if bridge is compromised

#### LayerZero Bridge
- **Shutdown when**: Bridge exploit detected, unauthorized cross-chain transfers
- **Severity**: Critical - Immediate shutdown if bridge is compromised

#### YieldRepurchaseFacility
- **Shutdown when**: Yield calculation errors, unauthorized fund movements
- **Severity**: Medium - Shutdown if affecting protocol operations

#### Heart
- **Shutdown when**: Heartbeat mechanism compromised, keeper rewards exploited
- **Severity**: Medium - Shutdown if affecting protocol operations

#### ReserveMigrator
- **Shutdown when**: Migration mechanism exploited, unauthorized reserve movements
- **Severity**: Low - Monitor, no immediate action required unless actively exploited

#### ReserveWrapper
- **Shutdown when**: Wrapper mechanism exploited, unauthorized reserve movements
- **Severity**: Low - Monitor, no immediate action required unless actively exploited

### Decision Tree

```
Is there an active exploit?
├─ YES → Is it affecting user funds?
│   ├─ YES → Shutdown immediately (TRSRY, MINTR, Bridges)
│   └─ NO → Assess severity and shutdown affected components
└─ NO → Is there a critical vulnerability?
    ├─ YES → Is it exploitable immediately?
    │   ├─ YES → Shutdown vulnerable components
    │   └─ NO → Plan coordinated shutdown
    └─ NO → Monitor and assess
```

### Severity Assessment Framework

- **Critical**: Immediate shutdown required, active exploit or imminent risk
- **High**: Immediate shutdown required, significant vulnerability with immediate exploitability
- **Medium**: Shutdown within hours, moderate risk
- **Low**: Monitor, no immediate action required

**Note**: Only Critical or High severity issues require immediate shutdown. Medium and Low severity issues should be assessed on a case-by-case basis and may not require immediate shutdown.

---

## Emergency Procedures

### Step-by-Step Emergency Response Protocol

1. **Detection and Assessment**
   - Identify the issue
   - Assess severity using the framework above
   - Determine affected components

2. **Communication**
   - Alert the protocol team immediately
   - Coordinate with Emergency MS signers
   - Document the issue and proposed response

3. **Preparation**
   - Verify Emergency MS signer availability
   - Ensure technical requirements are met
   - Prepare shutdown commands

4. **Execution**
   - Run shutdown script in simulation mode first
   - Review the proposed transactions
   - Execute shutdown in two phases (sign, then submit)

5. **Verification**
   - Verify shutdown transactions on-chain
   - Confirm affected components are disabled
   - Document the shutdown

6. **Post-Shutdown Actions**
   - Communicate status to community
   - Begin investigation and remediation
   - Plan restart procedures

### Communication Procedures

- **Internal**: Use designated emergency communication channels
- **External**: Coordinate public communication through official channels
- **Timeline**: Document all actions and timelines

### Escalation Path

1. **Level 1**: Protocol team assessment
2. **Level 2**: Emergency MS signer coordination
3. **Level 3**: DAO MS involvement (if required)
4. **Level 4**: External security audit and remediation

### Coordination Between Emergency MS Signers

- Establish communication channel before emergencies
- Pre-agree on shutdown procedures
- Coordinate signature timing
- Verify all signers are available

### Post-Shutdown Actions

1. **Investigation**
   - Root cause analysis
   - Impact assessment
   - Remediation planning

2. **Remediation**
   - Fix vulnerabilities
   - Test solutions
   - Prepare restart procedures

3. **Restart**
   - Coordinate restart with governance
   - Execute restart procedures
   - Monitor post-restart operations

---

## Using the Shutdown Script

### Overview

The `shutdown.sh` script provides a unified interface for executing emergency shutdown procedures. It handles all the complexity of batch script execution, signature generation, and transaction submission.

**Location**: `shell/shutdown.sh`

### Prerequisites

Before using the shutdown script, ensure you have completed the setup steps described in the [Technical Requirements](#technical-requirements) section above, including:
- Wallet setup (Ledger device or cast wallet)
- Environment configuration (`.env.emergency` file or environment variables)
- RPC URL configuration
- Chain configuration verification in `src/scripts/env.json`

### Script Usage

#### Basic Syntax

```bash
./shell/shutdown.sh <component> [--sign|--submit <signature>] [--account <wallet>|--ledger <index>] [--chain <chain>] [--broadcast <true|false>]
```

#### Two-Phase Signing Process

The shutdown script uses a two-phase signing process to work with Ledger devices:

**Phase 1: Generate Signature** (`--sign`)
```bash
./shell/shutdown.sh <component> --sign [--account <wallet>|--ledger <index>] --chain mainnet
```

This will:
- Simulate the shutdown transaction
- Generate a signature for the Safe transaction
- Output the signature to the console

**Phase 2: Submit Transaction** (`--submit <signature>`)
```bash
./shell/shutdown.sh <component> --submit <signature> [--account <wallet>|--ledger <index>] --chain mainnet --broadcast true
```

This will:
- Use the pre-generated signature
- Submit the transaction to the Safe multisig
- Broadcast the transaction (if `--broadcast true`)

### Available Components

The following components can be shut down using the script:

- `trsry` - Shutdown TRSRY withdrawals
- `mintr` - Shutdown MINTR minting
- `cooler-v2` - Shutdown all Cooler V2 operations (borrows, liquidations, composites, migrator)
- `emission-manager` - Shutdown EmissionManager and ConvertibleDepositAuctioneer
- `convertible-deposits` - Disable ConvertibleDepositFacility, DepositRedemptionVault, and DepositManager
- `ccip` - Disable CCIP bridge and emergency shutdown CCIP token pool
- `layerzero-bridge` - Disable LayerZero bridge
- `yield-repurchase-facility` - Shutdown YieldRepurchaseFacility
- `heart` - Deactivate Heart
- `reserve-migrator` - Deactivate ReserveMigrator

### Examples

#### Example 1: Shutdown TRSRY (with cast wallet)

**Phase 1 - Generate signature**:
```bash
./shell/shutdown.sh trsry --sign --account emergency-signer --chain mainnet
```

**Phase 2 - Submit transaction**:
```bash
./shell/shutdown.sh trsry --submit 0x1234... --account emergency-signer --chain mainnet --broadcast true
```

#### Example 2: Shutdown MINTR (with Ledger)

**Phase 1 - Generate signature**:
```bash
./shell/shutdown.sh mintr --sign --ledger 0 --chain mainnet
```

**Phase 2 - Submit transaction**:
```bash
./shell/shutdown.sh mintr --submit 0x5678... --ledger 0 --chain mainnet --broadcast true
```

#### Example 3: Using `.env.emergency`

If `.env.emergency` exists with `ACCOUNT=emergency-signer`:

**Phase 1 - Generate signature**:
```bash
./shell/shutdown.sh trsry --sign --chain mainnet
```

**Phase 2 - Submit transaction**:
```bash
./shell/shutdown.sh trsry --submit 0x1234... --chain mainnet --broadcast true
```

#### Example 4: Shutdown Cooler V2

```bash
# Phase 1
./shell/shutdown.sh cooler-v2 --sign --account emergency-signer --chain mainnet

# Phase 2
./shell/shutdown.sh cooler-v2 --submit 0xabcd... --account emergency-signer --chain mainnet --broadcast true
```

#### Example 5: Shutdown YieldRepurchaseFacility

```bash
# Phase 1
./shell/shutdown.sh yield-repurchase-facility --sign --account emergency-signer --chain mainnet

# Phase 2
./shell/shutdown.sh yield-repurchase-facility --submit 0xefgh... --account emergency-signer --chain mainnet --broadcast true
```

### Troubleshooting

#### Common Issues

1. **"No contract name provided"**
   - Solution: Ensure you're using a valid component name (see Available Components above)

2. **"RPC URL not found"**
   - Solution: Set `RPC_URL` environment variable or add to `.env.emergency`

3. **"Account not found"** (cast wallet)
   - Solution: Import the wallet first: `cast wallet import <name> --interactive`

4. **Ledger not detected**
   - Solution: Ensure Ledger is connected, unlocked, and Ethereum app is open

5. **Signature generation fails**
   - Solution: Verify you're using the correct account/Ledger index that matches an Emergency MS signer

6. **Transaction simulation fails**
   - Solution: Check that the Emergency MS has the required roles and sufficient signers

#### Error Handling and Recovery

- **If signature generation fails**: Check wallet/Ledger connection and try again
- **If transaction submission fails**: Verify the signature is correct and the Safe transaction hasn't expired
- **If broadcast fails**: Check network connectivity and RPC endpoint status
- **Always simulate first**: Use `--broadcast false` to test before actual submission

### Safety Checks

The script includes several safety checks:

1. **Simulation before execution**: All transactions are simulated before submission
2. **Multisig verification**: Verifies the target is a Safe multisig
3. **Role verification**: Checks that the Emergency MS has required roles
4. **Signature validation**: Validates signatures before submission

---

## Component Shutdown Instructions

### TRSRY

Withdrawals from the TRSRY module can be stopped by calling the [Emergency policy](../../src/policies/Emergency.sol).

**Using shutdown script**:
```bash
./shell/shutdown.sh trsry --sign --account <wallet> --chain mainnet
./shell/shutdown.sh trsry --submit <signature> --account <wallet> --chain mainnet --broadcast true
```

**Manual execution**:
- Function: `shutdownWithdrawals()`
- Required role: `emergency_shutdown` (DAO MS, Emergency MS, OCG Timelock)
- Address: Check `src/scripts/env.json` for `olympus.policies.Emergency`
- [ABI](abis/emergency.json)

**Batch script**: `src/scripts/emergency/EmergencyShutdown.sol`

### MINTR

OHM minting by the MINTR can be stopped by calling the [Emergency policy](../../src/policies/Emergency.sol).

**Using shutdown script**:
```bash
./shell/shutdown.sh mintr --sign --account <wallet> --chain mainnet
./shell/shutdown.sh mintr --submit <signature> --account <wallet> --chain mainnet --broadcast true
```

**Manual execution**:
- Function: `shutdownMinting()`
- Required role: `emergency_shutdown` (DAO MS, Emergency MS, OCG Timelock)
- Address: Check `src/scripts/env.json` for `olympus.policies.Emergency`
- [ABI](abis/emergency.json)

**Batch script**: `src/scripts/emergency/EmergencyShutdown.sol`

### Cooler v2

The Cooler V2 shutdown script handles all Cooler V2 operations: borrows, liquidations, composites, and migrator.

**Using shutdown script**:
```bash
./shell/shutdown.sh cooler-v2 --sign --account <wallet> --chain mainnet
./shell/shutdown.sh cooler-v2 --submit <signature> --account <wallet> --chain mainnet --broadcast true
```

**Manual execution**:

#### Borrows
- Function: `setBorrowPaused(true)`
- Required role: `admin` (OCG Timelock) or `emergency` (OCG Timelock or Emergency MS)
- Address: Check `src/scripts/env.json` for `olympus.policies.CoolerV2`

#### Liquidations
- Function: `setLiquidationsPaused(true)`
- Required role: `admin` (OCG Timelock) or `emergency` (OCG Timelock or Emergency MS)
- Address: Check `src/scripts/env.json` for `olympus.policies.CoolerV2`

#### Composites
- Function: `disable(bytes)` (empty bytes is fine)
- Required role: Currently owned by the DAO MS
- Address: Check `src/scripts/env.json` for `olympus.periphery.CoolerComposites`

#### Migrator
- Function: `disable(bytes)` (empty bytes is fine)
- Required role: Currently owned by the DAO MS
- Address: Check `src/scripts/env.json` for `olympus.periphery.CoolerV2Migrator`

**Batch script**: `src/scripts/emergency/CoolerV2Shutdown.sol`

### Emission Manager

The EmissionManager shutdown script also disables the ConvertibleDepositAuctioneer as they are related components.

**Using shutdown script**:
```bash
./shell/shutdown.sh emission-manager --sign --account <wallet> --chain mainnet
./shell/shutdown.sh emission-manager --submit <signature> --account <wallet> --chain mainnet --broadcast true
```

**Manual execution**:
- Function: `shutdown()` (via `disable()`)
- Required role: `emergency_shutdown` (DAO MS, Emergency MS, OCG Timelock)
- Address: Check `src/scripts/env.json` for `olympus.policies.EmissionManager`
- [ABI](abis/emission_manager.json)

**Batch script**: `src/scripts/emergency/EmissionManagerShutdown.sol`

### Convertible Deposits

The Convertible Deposits shutdown script disables ConvertibleDepositFacility, DepositRedemptionVault, and DepositManager as they are related components.

**Using shutdown script**:
```bash
./shell/shutdown.sh convertible-deposits --sign --account <wallet> --chain mainnet
./shell/shutdown.sh convertible-deposits --submit <signature> --account <wallet> --chain mainnet --broadcast true
```

**Manual execution**:
- Function: `disable(bytes)` (empty bytes is fine)
- Required role: Check individual contracts for role requirements
- Addresses: Check `src/scripts/env.json` for:
  - `olympus.policies.ConvertibleDepositFacility`
  - `olympus.policies.DepositRedemptionVault`
  - `olympus.policies.DepositManager`

**Batch script**: `src/scripts/emergency/ConvertibleDepositShutdown.sol`

### CCIP Bridge

The CCIP shutdown script handles both the CCIP bridge and token pool.

**Using shutdown script**:
```bash
./shell/shutdown.sh ccip --sign --account <wallet> --chain mainnet
./shell/shutdown.sh ccip --submit <signature> --account <wallet> --chain mainnet --broadcast true
```

**Manual execution**:
- Bridge: Function `disable()` - Check `src/scripts/env.json` for CCIP bridge address
- Token Pool: Function `emergencyShutdownAll()` - Check `src/scripts/env.json` for CCIP token pool address
- See [BRIDGE_CCIP](../BRIDGE_CCIP.md) for detailed instructions

**Required multisig**: Emergency MS (can be done by Emergency MS)

**Batch script**: `src/scripts/emergency/CCIPShutdown.sol`

### LayerZero Bridge

Bridging OHM between EVM chains is handled by the [LayerZero bridge](../../src/policies/CrossChainBridge.sol).

**⚠️ IMPORTANT**: This shutdown **must be done by the DAO MS**, not the Emergency MS.

**Using shutdown script**:
```bash
./shell/shutdown.sh layerzero-bridge --sign --account <wallet> --chain mainnet
./shell/shutdown.sh layerzero-bridge --submit <signature> --account <wallet> --chain mainnet --broadcast true
```

**Manual execution**:
- Function: `setBridgeStatus(false)`
- Required role: `bridge_admin` (DAO MS, OCG Timelock)
- Address: Check `src/scripts/env.json` for `olympus.policies.CrossChainBridge`
- [ABI](abis/cross_chain_bridge.json)

**Required multisig**: DAO MS (must be done by DAO MS)

**Batch script**: `src/scripts/emergency/LayerZeroBridgeShutdown.sol`

### Yield Repurchase Facility

The [YieldRepurchaseFacility policy](../../src/policies/YieldRepurchaseFacility.sol) can be shut down.

**⚠️ IMPORTANT**: This shutdown **must be done by the DAO MS**, not the Emergency MS.

**Using shutdown script**:
```bash
./shell/shutdown.sh yield-repurchase-facility --sign --account <wallet> --chain mainnet
./shell/shutdown.sh yield-repurchase-facility --submit <signature> --account <wallet> --chain mainnet --broadcast true
```

**Manual execution**:
- Function: `shutdown(ERC20[])`
- Required role: `loop_daddy` (DAO MS, OCG Timelock)
- Address: Check `src/scripts/env.json` for `olympus.policies.YieldRepurchaseFacility`
- [ABI](abis/yield_repurchase_facility.json)

The `shutdown()` function takes an array of tokens that will be transferred into the TRSRY module. A zero-length array can be provided.

**Required multisig**: DAO MS (must be done by DAO MS)

**Batch script**: `src/scripts/emergency/YieldRepurchaseFacilityShutdown.sol`

### Heart

The [Heart policy](../../src/policies/Heart.sol) can be shut down.

**Using shutdown script**:
```bash
./shell/shutdown.sh heart --sign --account <wallet> --chain mainnet
./shell/shutdown.sh heart --submit <signature> --account <wallet> --chain mainnet --broadcast true
```

**Manual execution**:
- Function: `disable(bytes)` (empty bytes is fine) - as of v1.7
- Required role: `emergency` (Emergency MS, OCG Timelock) or `admin` (DAO MS, OCG Timelock)
- Address: Check `src/scripts/env.json` for `olympus.policies.OlympusHeart`
- [ABI](abis/heart.json)

**Required multisig**: Emergency MS (as of v1.7+) or DAO MS

**Batch script**: `src/scripts/emergency/HeartShutdown.sol`

### Reserve Migrator

The [ReserveMigrator policy](../../src/policies/ReserveMigrator.sol) can be shut down.

**⚠️ IMPORTANT**: This shutdown **must be done by the DAO MS**, not the Emergency MS.

**Using shutdown script**:
```bash
./shell/shutdown.sh reserve-migrator --sign --account <wallet> --chain mainnet
./shell/shutdown.sh reserve-migrator --submit <signature> --account <wallet> --chain mainnet --broadcast true
```

**Manual execution**:
- Function: `deactivate()`
- Required role: `reserve_migrator_admin` (DAO MS, OCG Timelock)
- Address: Check `src/scripts/env.json` for `olympus.policies.ReserveMigrator`
- [ABI](abis/reserve_migrator.json)

**Required multisig**: DAO MS (must be done by DAO MS)

**Batch script**: `src/scripts/emergency/ReserveMigratorShutdown.sol`

### Bond Manager

The [BondManager policy](../../src/policies/BondManager.sol) can be used to stop the bond callback from minting more OHM. It also closes the market.

**Manual execution only** (not yet integrated into shutdown script):
- Function: `emergencyShutdownFixedExpiryMarket(uint256 marketId)`
- Required role: `bondmanager_admin` (DAO MS)
- Address: Check `src/scripts/env.json` for `olympus.policies.BondManager`
- [ABI](abis/bond_manager.json)

---

## Role Assignment

The assignment of roles can be viewed at any time on the [Protocol Visualizer](https://olympus-protocol-visualizer.up.railway.app).

## Contract Addresses

Addresses are provided in the sections below, but effort should be made to check the address in [env.json](../../src/scripts/env.json), in case it has not been updated here.

## CCIP Bridge

See [BRIDGE_CCIP](../BRIDGE_CCIP.md) for detailed instructions on how to shut down the components of the CCIP bridge.

## LayerZero Bridge

Bridging OHM between EVM chains is currently handled by the [LayerZero bridge](../../src/policies/CrossChainBridge.sol). Transactions can be paused by calling the following:

- Function: `setBridgeStatus(bool)`
- Required role: `bridge_admin` (DAO MS, OCG Timelock)
- Address: `0x45e563c39cDdbA8699A90078F42353A57509543a`
- [ABI](abis/cross_chain_bridge.json)

## TRSRY

Withdrawals from the TRSRY module can be stopped by calling the [Emergency policy](../../src/policies/Emergency.sol):

- Function: `shutdownWithdrawals()`
- Required role: `emergency_shutdown` (DAO MS, Emergency MS, OCG Timelock)
- Address: `0x9229b0b6FA4A58D67Eb465567DaA2c6A34714A75`
- [ABI](abis/emergency.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)

## MINTR

OHM minting by the MINTR can be stopped by calling the [Emergency policy](../../src/policies/Emergency.sol):

- Function: `shutdownMinting()`
- Required role: `emergency_shutdown` (DAO MS, Emergency MS, OCG Timelock)
- Address: `0x9229b0b6FA4A58D67Eb465567DaA2c6A34714A75`
- [ABI](abis/emergency.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)

## Cooler v2

### Borrows

Borrows can be paused on the Cooler V2 contract ([MonoCooler](../../src/policies/cooler/MonoCooler.sol)):

- Function: `setBorrowPaused(bool)`
- Required role: `admin` (OCG Timelock) or `emergency` (OCG Timelock or Emergency MS)
- Address: `0xdb591Ea2e5Db886dA872654D58f6cc584b68e7cC`
- [ABI](abis/cooler_v2.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)

### Composites

The [composites periphery contract](../../src/periphery/CoolerComposites.sol) can be disabled using the following:

- Function: `disable(bytes)` (empty bytes is fine)
- Required role: currently owned by the DAO MS
- Address: `0x6593768feBF9C95aC857Fb7Ef244D5738D1C57Fd`
- [ABI](abis/periphery_enabler.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)

### Migrator

The [migrator periphery contract](../../src/periphery/CoolerV2Migrator.sol) can be disabled using the following:

- Function: `disable(bytes)` (empty bytes is fine)
- Required role: currently owned by the DAO MS
- Address: `0xE045BD0A0d85E980AA152064C06EAe6B6aE358D2`
- [ABI](abis/periphery_enabler.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)

### Liquidations

Liquidations can be paused on the Cooler V2 contract ([MonoCooler](../../src/policies/cooler/MonoCooler.sol)):

- Function: `setLiquidationsPaused(bool)`
- Required role: `admin` (OCG Timelock) or `emergency` (OCG Timelock or Emergency MS)
- Address: `0xdb591Ea2e5Db886dA872654D58f6cc584b68e7cC`
- [ABI](abis/cooler_v2.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)

## Emission Manager

The [EmissionManager policy](../../src/policies/EmissionManager.sol) can be shut down using the following:

- Function: `shutdown()`
- Required role: `emergency_shutdown` (DAO MS, Emergency MS, OCG Timelock)
- Address: `0x50f441a3387625bDA8B8081cE3fd6C04CC48C0A2`
- [ABI](abis/emission_manager.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)

## Yield Repurchase Facility

The [YieldRepurchaseFacility policy](../../src/policies/YieldRepurchaseFacility.sol) can be shut down using the following:

- Function: `shutdown(ERC20[])`
- Required role: `loop_daddy` (DAO MS, OCG Timelock)
- Address: `0x271e35a8555a62F6bA76508E85dfD76D580B0692`
- [ABI](abis/yield_repurchase_facility.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)

The `shutdown()` function takes an array of tokens that will be transferred into the TRSRY module. A zero-length array can be provided.

## Heart

The [Heart policy](../../src/policies/Heart.sol) can be shut down using the following:

- Function: `disable()`
- Required role: `emergency` (OCG Timelock, Emergency MS)
- Address: `0x5824850D8A6E46a473445a5AF214C7EbD46c5ECB`
- [ABI](abis/heart.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)

## Bond Manager

The [BondManager policy](../../src/policies/BondManager.sol) can be used to stop the bond callback from minting more OHM. It also closes the market.

- Function: `emergencyShutdownFixedExpiryMarket(uint256 marketId)`
- Required role: `bondmanager_admin` (DAO MS)
- Address: `0xf577c77ee3578c7F216327F41B5D7221EaD2B2A3`
- [ABI](abis/bond_manager.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)

## Reserve Migrator

The [ReserveMigrator policy](../../src/policies/ReserveMigrator.sol) can be shut down using the following:

- Function: `deactivate()`
- Required role: `reserve_migrator_admin` (DAO MS, OCG Timelock)
- Address: `0x986b99579BEc7B990331474b66CcDB94Fa2419F5`
- [ABI](abis/reserve_migrator.json) (the Safe UI should automatically load the ABI from Etherscan, but this is provided just in case)
