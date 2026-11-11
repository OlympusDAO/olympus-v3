# BurnerLoansPayoutConfigTimelock.disable coverage plan

Coverage records implemented domains and assertions independently of pass/fail status.

Source: [disable](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol).

## Domains and notation

Scenario scope: `BLCUCT-DISABLE`. Valid default: real same-Kernel Payout, stored controller=this timelock, cached ROLES initialized, Local active=true and Local enabled=true. Payout has IEnabler, but recovery ignores its paused state; Core lifecycle, Payout inactivity and Core selection do not block recovery. Core must be idle for target mutations. Proposers fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap; distributor replacement is direct ADMIN-only and is not admitted by this queue or batches.

Unchanged means authoritative state, balances, allowances and committed logs applicable to this function remain unchanged. Faults are isolated with all other prerequisites satisfied. Use [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md); preserve independent lifecycle columns and guaranteed numeric boundary seeds.

## Authorization

ROLES initialized; valid history/grace for reEnable. Shared local-state/sentinel checks precede authorization.

| ID | Caller | Local active | Local enabled | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCUCT-DISABLE-A01 | Fuzz ADMIN-only, EMERGENCY-only, overlap | true | true | Success with valid prerequisites | Exact local transition/timestamp/events; no target/accounting mutation | Covered: [test][test_givenPermittedCaller_whenDisabled_thenExactTransition], [test][test_whenRoleAndPayloadSeedsUsed] |
| BLCUCT-DISABLE-A02 | Fuzz outside every accepted role class | true | true | NotAuthorised() | Unchanged | Covered: [test][test_givenUnauthorizedCaller_whenDisabled_reverts] |

## Local lifecycle

Data=0x for enable/disable; reEnable is parameterless. For reEnable fix lastTransitionAt>0 and a representable unexpired deadline.

| ID | Caller | Local active | Local enabled | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCUCT-DISABLE-L01 | Fuzz ADMIN-only, EMERGENCY-only, overlap | true | true | Success | Exact transition on success; unchanged on failure | Covered: [test][test_givenPermittedCaller_whenDisabled_thenExactTransition], [test][test_whenRoleAndPayloadSeedsUsed] |
| BLCUCT-DISABLE-L02 | Fuzz ADMIN-only, EMERGENCY-only, overlap | false | true | Success | Exact transition on success; unchanged on failure | Covered: [test][test_givenPermittedCaller_whenDisabled_thenExactTransition], [test][test_whenRoleAndPayloadSeedsUsed] |
| BLCUCT-DISABLE-L03 | Fuzz all callers | true | false | NotEnabled() | Exact transition on success; unchanged on failure | Covered: [test][test_givenDisabled_whenDisabled_reverts] |
| BLCUCT-DISABLE-L04 | Fuzz all callers | false | false | NotEnabled() | Exact transition on success; unchanged on failure | Covered: [test][test_givenDisabled_whenDisabled_reverts] |

## Unused payload

Correct starting local state; caller authorized; all other prerequisites ready. State/auth checks precede payload validation.

| ID | Caller | Payload | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-DISABLE-I01 | Fuzz ADMIN-only, EMERGENCY-only, overlap | data=0x | Success with normal prerequisites | One transition and exact events | Covered: [test][test_givenPermittedCaller_whenDisabled_thenExactTransition], [test][test_whenRoleAndPayloadSeedsUsed] |
| BLCUCT-DISABLE-I02 | Fuzz ADMIN-only, EMERGENCY-only, overlap | Fuzz nonempty length1..256; seed1,256 and encoded zero | BurnerLoans_InvalidEnablerData() | No transition/timestamp/events | Covered: [test][test_whenNonemptyPayload_reverts], [test][test_whenRoleAndPayloadSeedsUsed], [test_givenExistingAdmin_whenNonemptyDisablePayload_reverts][test_givenExistingAdmin_whenNonemptyDisablePayload_reverts] |

## Broken-target independence

Local enabled=true; own active/inactive both seeded with cached ROLES.

| ID | Caller | Target fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-DISABLE-D01 | Fuzz ADMIN-only, EMERGENCY-only, overlap | Payout controller changed; kernel()/configOperator() mocked to revert | Success | Local pause remains possible; no target reads | Covered: [test][test_givenPermittedCaller_whenDisabled_thenExactTransition], [test][test_whenRoleAndPayloadSeedsUsed] |

- [x] Derive concrete acceptance criteria from the implemented call path.
- [x] Implement focused tests and map exact domains/effects; execution results are tracked separately.

[test_givenDisabled_whenDisabled_reverts]: ./disable.t.sol#L58
[test_givenPermittedCaller_whenDisabled_thenExactTransition]: ./disable.t.sol#L17
[test_givenUnauthorizedCaller_whenDisabled_reverts]: ./disable.t.sol#L45
[test_whenNonemptyPayload_reverts]: ./disable.t.sol#L72
[test_whenRoleAndPayloadSeedsUsed]: ./disable.t.sol#L90

[test_givenExistingAdmin_whenNonemptyDisablePayload_reverts]: disable.t.sol#L124
