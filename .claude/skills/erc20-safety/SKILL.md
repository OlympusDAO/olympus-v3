---
name: erc20-safety
description: Design, implement, or review Olympus V3 Solidity code that transfers, approves, custodies, or accounts for ERC-20 tokens. Use before changing token-moving production code or its tests.
---

# ERC-20 Safety

Use this skill with `/test-write` when the work includes Solidity tests.

## Review Each Token Path

For each external function that can move tokens, identify:

- The token and transfer direction.
- The sender and recipient.
- The contract that records the transfer in protocol accounting.
- The external functions that a token callback can call.
- The token behavior that governance permits.

Include token calls made by libraries, vaults, custody contracts, and other dependencies.

## Use Safe Transfers

Use an approved safe-transfer library for mandatory ERC-20 `transfer`, `transferFrom`, and approval
calls. A best-effort payout may instead use a bounded safe call that accepts only no return data or
an ABI-encoded `true`, treats `false` or a revert as failure, and limits copied return data.

The safe-transfer library handles these return behaviors:

- The token returns `true`.
- The token returns no data.
- The token returns `false`.
- The token reverts.

Do not repeat all of these library tests in each contract. If a transfer occurs after a state
change, use one representative transfer error to prove that the state change rolls back.

## Keep User Actions Independent of Optional Payouts

Separate the user's required transfer from a downstream protocol payout. A collateral deposit,
repayment, or fee collection from the caller must fail if the caller's transfer fails or the exact
required amount is not received. A failed transfer **to the user** that is the purpose of the action
must also fail; do not record a successful withdrawal that did not pay the user.

When an outgoing fee, incentive, or other noncritical protocol payout follows a valid user action,
prefer to preserve that action if the token contract reverts or returns `false` on transfer to the
payout destination. For example, an extension should not revert solely because the token contract
blocks transfers to TRSRY or a Revenue Distributor, such as through a blacklist. Keep the received
tokens in custody, record the full unpaid amount in a source-specific accounting bucket, and emit
a deferral event. Provide a permissionless or periodic retry; a failed retry must retain the
obligation. Resolve changeable destinations at retry time when the entitlement belongs to a role
or payout type. Keep the original address only when the entitlement belongs to that person, such as
a keeper reward.

Check the whole flow before making a payout fail-soft: its incoming transfer must be strict, its
unpaid balance must remain solvent, and no position, fee, or debt may be credited twice. A token
that reports failure after actually moving funds cannot be made safe by this pattern; reject that
behavior during governance token review.

## Check Incoming Accounting

Check the received balance when an incoming transfer creates protocol accounting. Examples include
collateral credit, debt repayment, reserves, and custody liabilities.

Compare the recipient balance before and after the transfer. Use the received amount for accounting
when inexact transfers are supported. Revert when the protocol requires the received amount to equal
the requested amount.

Do this for each incoming accounting transaction. Do not mark a token as safe after one transfer.
Token behavior can depend on the sender, recipient, amount, allowlist, or current implementation.

Place the check at the contract whose accounting changes. In a multi-contract deposit, this is
usually the final custody contract. If an intermediate contract must retain no tokens, also reject a
new residual balance there.

Do not add balance checks to outgoing transfers. Use the safe-transfer library and the token rules
that governance approved.

## Protect Token Callbacks

Treat each token call as an external call. A token can call the contract during `transfer` or
`transferFrom`, including through ERC-777 hooks or custom token code.

Use one reentrancy guard for all token-moving entry points that share state. Protect a composite or
wrapper when a callback can reenter it before the guarded downstream contract runs.
In callback tests:

- Give the callback address any authorization that the nested call needs.
- Make the callback attempt a meaningful nested action.
- Assert that the reentrancy guard rejects the nested action.
- Assert that the outer action applies only once.

Check both callback outcomes. If the token catches the nested revert, the outer transfer may still
succeed. If the token propagates it, a mandatory transfer reverts and a best-effort payout remains
pending. Do not require the whole user action to revert merely because the nested call was blocked.
Test direct and periodic retry entry points under the same guard when they share payout state.

## Require Governance Review

Do not use an admission-time transfer to classify a token. Governance must review:

- Fee-on-transfer behavior.
- Rebasing behavior.
- Upgradeable token code.
- Sender or recipient allowlists.
- Transfer pauses and limits.
- Token callbacks.

Document unsupported token behavior and the accounting boundary that rejects an inexact incoming
transfer. A balance check during deposit does not make a rebasing token safe after deposit.

## Required Contract Coverage

Add the applicable tests for each changed token path:

- A successful incoming transfer records the received amount correctly.
- An inexact incoming transfer creates no credit when exact receipt is required.
- A transfer error restores state changed before the transfer.
- A failed noncritical outgoing transfer preserves the user action and remains exactly owed; a
    later retry pays it once.
- A token callback cannot apply the same action or a related action twice.

Do not add tests for unsupported token behavior that governance alone must review, unless the
contract contains an explicit guard for that behavior.

For repository examples, read [references/olympus-examples.md](references/olympus-examples.md).
