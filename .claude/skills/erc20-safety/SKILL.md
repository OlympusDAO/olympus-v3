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

Use an approved safe-transfer library for ERC-20 `transfer`, `transferFrom`, and approval calls.

The safe-transfer library handles these return behaviors:

- The token returns `true`.
- The token returns no data.
- The token returns `false`.
- The token reverts.

Do not repeat all of these library tests in each contract. If a transfer occurs after a state
change, use one representative transfer error to prove that the state change rolls back.

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
- A token callback cannot apply the same action or a related action twice.

Do not add tests for unsupported token behavior that governance alone must review, unless the
contract contains an explicit guard for that behavior.

For repository examples, read [references/olympus-examples.md](references/olympus-examples.md).
