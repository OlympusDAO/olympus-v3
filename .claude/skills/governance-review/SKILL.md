---
description: Guide for reviewing deployment, activation and governance steps.
---

# Governance Review

This guide advises on how to perform the rollout of new policies and modules in the Olympus protocol.

## Governance Context

- **OCG (On-Chain Governance):** 11-day process for execution of the proposal, enables policies, grants roles
- **DAO MS (Multisig):** Installs modules/policies via `kernel.executeActions()`, has operational roles (e.g., `price_admin`)
- **Critical systems:** Heart, RANGE cannot have downtime
- **Permissions:** Keycode-based, persist across module upgrades
- **Enabling:** A standard practice is to have an OCG proposal to grant roles and enable new policies.

## Examples

### Module Upgrade

It is intended to upgrade the PRICE module to a new version. The current setup of the protocol allows the DAO MS to install/upgrade modules via the Kernel.

However, that module requires configuration of assets. Without this configuration, existing policies that depend on the module, e.g. YieldRepurchaseFacility, will revert (preventing the heartbeat from succeeding) or behave unexpectedly (likely the worse outcome).

Context:

- The `price_admin` role is already granted to the DAO MS, due to its usage in the previous PriceConfig policy.
- The PriceConfigv2 policy allows for configuration of the PRICE module's assets. It requires installation in the kernel, and actions are gated to the `price_admin` role.
- The standard practice is for new policies to be disabled by default (via the `PolicyEnabler` mix-in). This would require an OCG proposal to be completed in order to enable the PriceConfigv2 policy and allow the DAO MS to configure assets.

The outcome of this is that there is a minimum 11-day window between deployment of the PRICE module upgrade and the execution of the OCG proposal, during which the Heart contract's heartbeat would be non-functional. This is unacceptable.

Potential solutions:

- Configure the assets in the upgraded PRICE module at deployment-time
- Configure the assets in the upgraded PRICE module at installation-time, via a custom `initialize()` function gated to the DAO MS
- Enable the PriceConfigv2 policy so that it is enabled by default. This allows the DAO MS to configure the assets at the time of installation.

## Generic Patterns to Check

### Roles

- Are all necessary roles granted before execution of an OCG proposal?

### Ordering and Timing

- Does the 11-day OCG process cause any issues with activation and configuration of the contracts?
- Does the order of operations account for dependencies?
- Are dependent operations batched together?
- Can the ordering of different tasks be changed?

### Safety

- Is there a rollback plan if something fails?
- Are critical operations batched to avoid downtime?
- Does a batch account for the 11-day OCG timelock?
- Is the reliability of the heartbeat put in jeopoardy?

### Cleanup

- Are roles/permissions cleaned up after temporary grants?
- Are temporary addresses/contracts removed after use?

## Advisory Role

Point out potential issues, suggest optimizations, highlight assumptions, and ask clarifying questions.
