# Emergency Shutdown Instructions

This document provides comprehensive information on how to shut down the Olympus protocol in the event of an emergency.

## Table of Contents

1. [Emergency Multisig Overview](#emergency-multisig-overview)
2. [Emergency Config Structure](#emergency-config-structure)
3. [When to Shutdown](#when-to-shutdown)
4. [Emergency Procedures](#emergency-procedures)
5. [Executing Shutdowns](#executing-shutdowns)

---

## Emergency Multisig Overview

### What is the Emergency MS

The Emergency Multisig (Emergency MS) is a dedicated Safe multisig wallet with specific permissions to execute emergency shutdown procedures. It operates independently from the DAO Multisig (DAO MS) to ensure rapid response capability during critical situations.

### Address and Verification

The Emergency MS address is configured in `src/scripts/env.json` under the key `olympus.multisig.emergency`. The address varies by chain:

**Current Emergency MS Addresses:**

| Chain | Address |
|-------|---------|
| **Mainnet** | `0xa8A6ff2606b24F61AFA986381D8991DFcCCd2D55` |
| **Base** | `0x18a390bD45bCc92652b9A91AD51Aed7f1c1358f5` (same as DAO MS) |
| **Base Sepolia** | `0x1A5309F208f161a393E8b5A253de8Ab894A67188` (same as DAO MS) |
| **Berachain** | `0xa5ea62894027D981D34BB99A04BD36B818b2Aaf0` |
| **Berachain Bartio** | `0x1A5309F208f161a393E8b5A253de8Ab894A67188` (same as DAO MS) |
| **Sepolia** | `0x81E6E5Ba12a11ceed3E8BfE825B56ae9b7260691` |

**⚠️ Missing Emergency MS Addresses:**

The following chains are missing Emergency MS addresses (set to zero address) in `src/scripts/env.json`:

- **Arbitrum**: Currently `0x0000000000000000000000000000000000000000` - **ACTION REQUIRED**
- **Optimism**: Currently `0x0000000000000000000000000000000000000000` - **ACTION REQUIRED**

**TODO Task**:

- [ ] Verify Emergency MS deployment status for Arbitrum
- [ ] Verify Emergency MS deployment status for Optimism
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

---

## Emergency Config Structure

The emergency configuration is stored in `documentation/emergency/emergency-config.json`. This file is used by the emergency frontend to generate and execute shutdown transactions.

### Config Schema

The emergency config follows the structure defined in `documentation/emergency/emergency-config.schema.json`. Key components include:

**Chain Configuration:**

- Chain ID and name mappings
- Emergency multisig addresses per chain
- Component addresses and function selectors

**Component Definitions:**

- Target contract addresses
- Function selectors for shutdown actions
- Required roles and permissions
- Multisig owner (Emergency MS vs DAO MS)
- Severity ratings and shutdown criteria

**Validation:**

- Config is validated automatically via CI/CD (`.github/workflows/validate-emergency-config.yml`)
- Can be validated locally using `shell/validate-emergency-config.js`

### Updating the Config

To update the emergency configuration:

1. Edit `documentation/emergency/emergency-config.json`
2. Ensure changes follow the schema
3. Run validation: `node shell/validate-emergency-config.js`
4. Commit the changes

For bulk updates, use the `/update-emergency-config` command.

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

### Severity Assessment Framework

| Severity | Description | Response Time |
|----------|-------------|---------------|
| **Critical** | Immediate shutdown required, active exploit or imminent risk | Immediate |
| **High** | Immediate shutdown required, significant vulnerability with immediate exploitability | Immediate |
| **Medium** | Shutdown within hours, moderate risk | Hours |
| **Low** | Monitor, no immediate action required | Monitor |

**Note**: Only Critical or High severity issues require immediate shutdown. Medium and Low severity issues should be assessed on a case-by-case basis.

### Decision Tree

```text
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
   - Access the emergency frontend
   - Review available components and their severity ratings

4. **Execution**
   - Select components to shutdown via the frontend
   - Generate Safe multisig transactions
   - Obtain required signatures from signers
   - Execute shutdown transactions

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

## Executing Shutdowns

Emergency shutdowns are executed through the emergency frontend, which uses the configuration in `documentation/emergency/emergency-config.json` to generate and execute transactions.

### Using the Emergency Frontend

The emergency frontend provides a web interface for:

- Viewing all available components and their shutdown criteria
- Generating Safe multisig transactions for shutdown actions
- Collecting signatures from multisig signers
- Submitting transactions to the blockchain
- Tracking execution status

**Access**: The emergency frontend is hosted in a separate repository. Contact the protocol team for access information.

### Component Details

For detailed information about each component—including shutdown criteria, function signatures, and post-shutdown steps—refer to `documentation/emergency/emergency-config.json`. Each component entry includes:

- **Description**: What the component does
- **Severity**: How critical it is
- **Shutdown Criteria**: When to shut it down
- **Post-Shutdown Steps**: How to verify the shutdown worked
- **Dependencies**: Other components that should be shut down together

### Role Assignment

The assignment of roles can be viewed at any time on the [Protocol Visualizer](https://olympus-protocol-visualizer.up.railway.app).
