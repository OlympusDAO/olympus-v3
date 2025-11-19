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
- **Sepolia**: `0x81E6E5Ba12a11ceed3E8BfE825B56ae9b7260691`

**⚠️ Missing Emergency MS Addresses:**

The following chains are missing Emergency MS addresses (set to zero address) in `src/scripts/env.json`:
- **Arbitrum**: Currently `0x0000000000000000000000000000000000000000` - **ACTION REQUIRED**

**TODO Task**:
- [ ] Verify Emergency MS deployment status for Arbitrum
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
   - Install foundryup: `curl -L https://foundry.paradigm.xyz | bash`
   - Install foundry tools: `foundryup`
   - Verify: `forge --version` and `cast --version`

2. **Bash** - Shell interpreter (typically pre-installed on macOS/Linux)
   - Verify: `bash --version`

3. **Node.js and pnpm** - For project dependencies
   - Install Node.js: [nodejs.org](https://nodejs.org/)
   - Install pnpm: `npm install -g pnpm` (this might reqire a `sudo` prefix, depending on the system)

4. Check out the repo using git: `git clone https://github.com/OlympusDAO/olympus-v3.git`

5. Install dependencies and build: `pnpm run build`

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
./shell/shutdown.sh <component> --chain <chain> [--sign | --submit <signature>] [--account <wallet> | --ledger <index>] [--broadcast <true|false>] [--rpc-url <url>] [--args <path>]
```

- `--chain` is required. Use a Foundry RPC alias (e.g. `mainnet`) or supply `--rpc-url`.
- `--account` expects the cast wallet name; `--ledger` expects the Ledger mnemonic index. Configure defaults in `.env.emergency`.
- `--broadcast true` is only valid when submitting a signature, never with `--sign`.
- `--args` can pass a JSON payload to scripts that require additional parameters. Most current scripts expect an empty arguments file; use `--args` only when instructed.

#### Listing Supported Targets

```bash
./shell/shutdown.sh --list
```

This displays all supported chains, components, and the multisig expected to execute them.

#### Two-Phase Signing Process

The shutdown script uses a two-phase signing process to work with Ledger devices:

**Phase 1: Generate Signature** (`--sign`)
```bash
./shell/shutdown.sh <component> --sign [--account <wallet>|--ledger <index>] --chain <chain>
```

This will:
- Simulate the shutdown transaction
- Generate a signature for the Safe transaction
- Output the signature to the console

**Phase 2: Submit Transaction** (`--submit <signature>`)
```bash
./shell/shutdown.sh <component> --submit <signature> [--account <wallet>|--ledger <index>] --chain <chain> --broadcast true
```

This will:
- Use the pre-generated signature
- Submit the transaction to the Safe multisig
- Broadcast the transaction (if `--broadcast true`)

### Quick Reference: Components and Signers

Run `./shell/shutdown.sh --list` to print the current list of supported targets, their owning multisig, and supported chains.

| Component | Description | Required multisig |
| --- | --- | --- |
| `treasury` | Shutdown TRSRY withdrawals | Emergency MS |
| `minter` | Shutdown MINTR minting | Emergency MS |
| `cooler-v2` | Pause Cooler V2 core operations | Emergency MS |
| `cooler-v2-periphery` | Disable Cooler composites and migrator helpers | DAO MS |
| `emission-manager` | Disable EmissionManager and ConvertibleDepositAuctioneer | Emergency MS |
| `convertible-deposits` | Disable ConvertibleDepositFacility, DepositRedemptionVault, DepositManager | Emergency MS |
| `ccip-bridge` | Disable CCIP bridge contract | DAO MS |
| `ccip-token-pool-mainnet` | Shutdown mainnet CCIP token pool | DAO MS |
| `ccip-token-pool-non-mainnet` | Shutdown non-mainnet CCIP token pools | Emergency MS |
| `layerzero-bridge` | Disable LayerZero bridge | DAO MS |
| `yield-repurchase-facility` | Shutdown YieldRepurchaseFacility | DAO MS |
| `heart` | Deactivate Heart | Emergency MS |
| `reserve-migrator` | Deactivate ReserveMigrator | DAO MS |
| `reserve-wrapper` | Deactivate ReserveWrapper | DAO MS |

### Script Examples

#### Example 1: Shutdown TRSRY (with cast wallet)

**Phase 1 - Generate signature**:
```bash
./shell/shutdown.sh treasury --sign --account emergency-signer --chain <chain>
```

**Phase 2 - Submit transaction**:
```bash
./shell/shutdown.sh treasury --submit 0x1234... --account emergency-signer --chain <chain> --broadcast true
```

#### Example 2: Shutdown MINTR (with Ledger)

**Phase 1 - Generate signature**:
```bash
./shell/shutdown.sh minter --sign --ledger 0 --chain <chain>
```

**Phase 2 - Submit transaction**:
```bash
./shell/shutdown.sh minter --submit 0x5678... --ledger 0 --chain <chain> --broadcast true
```

#### Example 3: Using `.env.emergency`

If `.env.emergency` exists with `ACCOUNT=emergency-signer`:

**Phase 1 - Generate signature**:
```bash
./shell/shutdown.sh treasury --sign --chain <chain>
```

**Phase 2 - Submit transaction**:
```bash
./shell/shutdown.sh treasury --submit 0x1234... --chain <chain> --broadcast true
```

#### Example 4: Shutdown Cooler V2

```bash
# Phase 1
./shell/shutdown.sh cooler-v2 --sign --account emergency-signer --chain <chain>

# Phase 2
./shell/shutdown.sh cooler-v2 --submit 0xabcd... --account emergency-signer --chain <chain> --broadcast true
```

#### Example 5: Shutdown YieldRepurchaseFacility

```bash
# Phase 1
./shell/shutdown.sh yield-repurchase-facility --sign --account emergency-signer --chain <chain>

# Phase 2
./shell/shutdown.sh yield-repurchase-facility --submit 0xefgh... --account emergency-signer --chain <chain> --broadcast true
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
./shell/shutdown.sh treasury --sign --account <wallet> --chain <chain>
./shell/shutdown.sh treasury --submit <signature> --account <wallet> --chain <chain> --broadcast true
```

**Manual execution**:
- Function: `shutdownWithdrawals()`
- Required role: `emergency_shutdown` (DAO MS, Emergency MS, OCG Timelock)
- Address: Check `src/scripts/env.json` for `olympus.policies.Emergency`
- [ABI](abis/emergency.json)

**Batch script**: `src/scripts/emergency/Treasury.sol`

### MINTR

OHM minting by the MINTR can be stopped by calling the [Emergency policy](../../src/policies/Emergency.sol).

**Using shutdown script**:
```bash
./shell/shutdown.sh minter --sign --account <wallet> --chain <chain>
./shell/shutdown.sh minter --submit <signature> --account <wallet> --chain <chain> --broadcast true
```

**Manual execution**:
- Function: `shutdownMinting()`
- Required role: `emergency_shutdown` (DAO MS, Emergency MS, OCG Timelock)
- Address: Check `src/scripts/env.json` for `olympus.policies.Emergency`
- [ABI](abis/emergency.json)

**Batch script**: `src/scripts/emergency/Minter.sol`

### Cooler v2

The Cooler V2 shutdown script handles all Cooler V2 operations: borrows, liquidations, composites, and migrator.

**Using shutdown script**:
```bash
./shell/shutdown.sh cooler-v2 --sign --account <wallet> --chain <chain>
./shell/shutdown.sh cooler-v2 --submit <signature> --account <wallet> --chain <chain> --broadcast true
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

**Batch script**: `src/scripts/emergency/CoolerV2.sol`

### Cooler v2 Periphery

The Cooler V2 periphery shutdown script disables contracts that are owned by the DAO multisig (composites and migrator helpers). Use this **in addition** to the `cooler-v2` script when the exploit surface includes periphery helpers.

**Using shutdown script**:
```bash
./shell/shutdown.sh cooler-v2-periphery --sign --account <wallet> --chain <chain>
./shell/shutdown.sh cooler-v2-periphery --submit <signature> --account <wallet> --chain <chain> --broadcast true
```

**Manual execution**:
- `CoolerComposites.disable("")`
- `CoolerV2Migrator.disable("")`
- Required role: DAO MS (owner)
- Addresses: See `olympus.periphery.CoolerComposites` and `olympus.periphery.CoolerV2Migrator` in `src/scripts/env.json`

**Batch script**: `src/scripts/emergency/CoolerV2Periphery.sol`

### Emission Manager

The EmissionManager shutdown script also disables the ConvertibleDepositAuctioneer as they are related components.

**Using shutdown script**:
```bash
./shell/shutdown.sh emission-manager --sign --account <wallet> --chain <chain>
./shell/shutdown.sh emission-manager --submit <signature> --account <wallet> --chain <chain> --broadcast true
```

**Manual execution**:
- Function: `shutdown()` (via `disable()`)
- Required role: `emergency_shutdown` (DAO MS, Emergency MS, OCG Timelock)
- Address: Check `src/scripts/env.json` for `olympus.policies.EmissionManager`
- [ABI](abis/emission_manager.json)

**Batch script**: `src/scripts/emergency/EmissionManager.sol`

### Convertible Deposits

The Convertible Deposits shutdown script disables ConvertibleDepositFacility, DepositRedemptionVault, and DepositManager as they are related components.

**Using shutdown script**:
```bash
./shell/shutdown.sh convertible-deposits --sign --account <wallet> --chain <chain>
./shell/shutdown.sh convertible-deposits --submit <signature> --account <wallet> --chain <chain> --broadcast true
```

**Manual execution**:
- Function: `disable(bytes)` (empty bytes is fine)
- Required role: Check individual contracts for role requirements
- Addresses: Check `src/scripts/env.json` for:
  - `olympus.policies.ConvertibleDepositFacility`
  - `olympus.policies.DepositRedemptionVault`
  - `olympus.policies.DepositManager`

**Batch script**: `src/scripts/emergency/ConvertibleDeposits.sol`

### CCIP Bridge

Disable the CCIP cross-chain bridge contract. Must be executed by the DAO MS.

**Using shutdown script**:
```bash
./shell/shutdown.sh ccip-bridge --sign --account <wallet> --chain <chain>
./shell/shutdown.sh ccip-bridge --submit <signature> --account <wallet> --chain <chain> --broadcast true
```

**Manual execution**:
- Function: `disable("")` (empty bytes)
- Required role: DAO MS (owner with `emergency` equivalent capabilities)
- Address: `olympus.periphery.CCIPCrossChainBridge` in `src/scripts/env.json`
- Reference: [BRIDGE_CCIP.md](../BRIDGE_CCIP.md)

**Batch script**: `src/scripts/emergency/CCIPBridge.sol`

### CCIP Token Pool (Mainnet)

Withdraw all liquidity from the LockRelease token pool on canonical chains (Ethereum mainnet and Sepolia). Requires DAO MS execution.

**Using shutdown script**:
```bash
./shell/shutdown.sh ccip-token-pool-mainnet --sign --account <wallet> --chain <chain>
./shell/shutdown.sh ccip-token-pool-mainnet --submit <signature> --account <wallet> --chain <chain> --broadcast true
```

**Manual execution**:
- Function: `withdrawLiquidity(totalBalance)`
- Required role: DAO MS (rebalancer)
- Addresses: `olympus.periphery.CCIPLockReleaseTokenPool`, `olympus.legacy.OHM`
- Note: Script auto-detects the current liquidity balance; replicate manually by querying the OHM balance of the token pool.

**Batch script**: `src/scripts/emergency/CCIPTokenPoolMainnet.sol`

### CCIP Token Pool (Non-Mainnet)

Disable the burn/mint token pool on non-canonical chains (all chains except mainnet/Sepolia). Executed by the Emergency MS.

**Using shutdown script**:
```bash
./shell/shutdown.sh ccip-token-pool-non-mainnet --sign --account <wallet> --chain <chain>
./shell/shutdown.sh ccip-token-pool-non-mainnet --submit <signature> --account <wallet> --chain <chain> --broadcast true
```

**Manual execution**:
- Function: `disable("")` (empty bytes)
- Required role: Emergency MS
- Address: `olympus.policies.CCIPBurnMintTokenPool`

**Batch script**: `src/scripts/emergency/CCIPTokenPoolNonMainnet.sol`

### LayerZero Bridge

Bridging OHM between EVM chains is handled by the [LayerZero bridge](../../src/policies/CrossChainBridge.sol).

**⚠️ IMPORTANT**: This shutdown **must be done by the DAO MS**, not the Emergency MS.

**Using shutdown script**:
```bash
./shell/shutdown.sh layerzero-bridge --sign --account <wallet> --chain <chain>
./shell/shutdown.sh layerzero-bridge --submit <signature> --account <wallet> --chain <chain> --broadcast true
```

**Manual execution**:
- Function: `setBridgeStatus(false)`
- Required role: `bridge_admin` (DAO MS, OCG Timelock)
- Address: Check `src/scripts/env.json` for `olympus.policies.CrossChainBridge`
- [ABI](abis/cross_chain_bridge.json)

**Required multisig**: DAO MS (must be done by DAO MS)

**Batch script**: `src/scripts/emergency/LayerZeroBridge.sol`

### Yield Repurchase Facility

The [YieldRepurchaseFacility policy](../../src/policies/YieldRepurchaseFacility.sol) can be shut down.

**⚠️ IMPORTANT**: This shutdown **must be done by the DAO MS**, not the Emergency MS.

**Using shutdown script**:
```bash
./shell/shutdown.sh yield-repurchase-facility --sign --account <wallet> --chain <chain>
./shell/shutdown.sh yield-repurchase-facility --submit <signature> --account <wallet> --chain <chain> --broadcast true
```

**Manual execution**:
- Function: `shutdown(ERC20[])`
- Required role: `loop_daddy` (DAO MS, OCG Timelock)
- Address: Check `src/scripts/env.json` for `olympus.policies.YieldRepurchaseFacility`
- [ABI](abis/yield_repurchase_facility.json)

The `shutdown()` function takes an array of tokens that will be transferred into the TRSRY module. A zero-length array can be provided.

**Required multisig**: DAO MS (must be done by DAO MS)

**Batch script**: `src/scripts/emergency/YieldRepurchaseFacility.sol`

### Heart

The [Heart policy](../../src/policies/Heart.sol) can be shut down.

**Using shutdown script**:
```bash
./shell/shutdown.sh heart --sign --account <wallet> --chain <chain>
./shell/shutdown.sh heart --submit <signature> --account <wallet> --chain <chain> --broadcast true
```

**Manual execution**:
- Function: `disable(bytes)` (empty bytes is fine) - as of v1.7
- Required role: `emergency` (Emergency MS, OCG Timelock) or `admin` (DAO MS, OCG Timelock)
- Address: Check `src/scripts/env.json` for `olympus.policies.OlympusHeart`
- [ABI](abis/heart.json)

**Required multisig**: Emergency MS (as of v1.7+) or DAO MS

**Batch script**: `src/scripts/emergency/Heart.sol`

### Reserve Migrator

The [ReserveMigrator policy](../../src/policies/ReserveMigrator.sol) can be shut down.

**⚠️ IMPORTANT**: This shutdown **must be done by the DAO MS**, not the Emergency MS.

**Using shutdown script**:
```bash
./shell/shutdown.sh reserve-migrator --sign --account <wallet> --chain <chain>
./shell/shutdown.sh reserve-migrator --submit <signature> --account <wallet> --chain <chain> --broadcast true
```

**Manual execution**:
- Function: `deactivate()`
- Required role: `reserve_migrator_admin` (DAO MS, OCG Timelock)
- Address: Check `src/scripts/env.json` for `olympus.policies.ReserveMigrator`
- [ABI](abis/reserve_migrator.json)

**Required multisig**: DAO MS (must be done by DAO MS)

**Batch script**: `src/scripts/emergency/ReserveMigrator.sol`

### Reserve Wrapper

Disable the ReserveWrapper policy via the DAO MS.

**Using shutdown script**:
```bash
./shell/shutdown.sh reserve-wrapper --sign --account <wallet> --chain <chain>
./shell/shutdown.sh reserve-wrapper --submit <signature> --account <wallet> --chain <chain> --broadcast true
```

**Manual execution**:
- Function: `disable("")` (empty bytes)
- Required role: `reserve_wrapper_admin` / DAO MS owner
- Address: `olympus.policies.ReserveWrapper` in `src/scripts/env.json`

**Batch script**: `src/scripts/emergency/ReserveWrapper.sol`

### Bond Manager

The [BondManager policy](../../src/policies/BondManager.sol) can be used to stop the bond callback from minting more OHM. It also closes the market.

**Manual execution only** (not yet integrated into shutdown script):
- Function: `emergencyShutdownFixedExpiryMarket(uint256 marketId)`
- Required role: `bondmanager_admin` (DAO MS)
- Address: Check `src/scripts/env.json` for `olympus.policies.BondManager`
- [ABI](abis/bond_manager.json)

## Role Assignment

The assignment of roles can be viewed at any time on the [Protocol Visualizer](https://olympus-protocol-visualizer.up.railway.app).
