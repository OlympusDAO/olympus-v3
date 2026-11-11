---
name: policy-lifecycle
description: Review and implement Default Framework policy admission, dependency binding/setters and enable/disable/reEnable behavior in scenario plans, Foundry tests and contracts.
---

# Policy admission, dependencies and lifecycle

Use for Default Framework Policies and their dependency boundaries. This skill owns policy admission, dependency selection and lifecycle rules; [solidity-test-scenarios](../solidity-test-scenarios/SKILL.md) owns scenario structure, IDs and coverage mapping. It does not prescribe a Core architecture, extend Kernel membership to ordinary contracts, or authorize implementation during planning.

Read the concrete policy, inherited guards/hooks, role lookups and direct services. Distinguish agreed requirements from current source behavior. Preserve the actual guard order unless a change is authorized.

## Subject lifecycle

Kernel membership and local enablement are independent. Use adjacent `Local active` and `Local enabled` columns. The following matrix assumes an otherwise permitted caller and usable cached authorization dependencies; earlier source guards still determine error precedence.

| Operation | Local active | Local enabled | Required outcome |
| --- | --- | --- | --- |
| enable | true | false | Enable after valid payload, binding and operational-dependency checks. |
| enable | false | false | Reject own inactivity; do not enable a deactivated policy. |
| enable | Fuzz false/true | true | Reject already-enabled state before activation hooks. |
| disable | Fuzz false/true | true | Disable without requiring operational dependencies or own Kernel activity. |
| disable | Fuzz false/true | false | Reject already-disabled state. |
| reEnable | true | false | Same activation checks as enable, plus initialized history and valid grace. |
| reEnable | false | false | Reject own inactivity after earlier history/authorization/grace checks. |
| reEnable | Fuzz false/true | true | Reject already-enabled state. |

Disable may retain a local settlement guard and payload validation; broken services must not prevent a pause. Transitions preserve positions, balances, obligations and configuration, changing only the documented lifecycle fields/events.

Guarantee both boolean values when a row groups false/true.

Trace precedence from the actual modifier/hook chain: EnablerV2 checks local transition state before authorization; legacy PolicyEnabler differs. ReEnabler's initialization check is inside that inherited chain. Do not infer a universal first error from the table. A never-activated policy with unset ROLES is different from a deactivated policy with cached ROLES. Match empty revert bytes only when an actually reached dependency call has no stable typed error; do not assume every inactive policy fails opaquely.

Unused enable/disable bytes must be empty, with a product-owned invalid-enabler-data error rather than a change to generic IEnabler. If a consumer uses the payload, test its real domain. reEnable has no payload. Check nonempty data and relevant competing faults in actual guard order.

## Classify direct dependencies

For each relationship, record the consumer, service used, operational/reference classification, required membership/enablement, authoritative binding and errors. Inspect each entry point and configuration mode; an address appearing in storage does not itself require a lifecycle check.

| Relationship | Required validation |
| --- | --- |
| Consumes another Policy's enabled-only service | Active in the consumer's Kernel, reports that Kernel, locally enabled, and correctly bound for the service. |
| Uses an ordinary calculator, lens, token or helper | Its actual interface/address/binding requirements; no invented Kernel membership or Enabler. |
| Uses a Kernel module | Resolve through the intended Kernel/keycode; verify required version/permissions, not Policy lifecycle. |
| Stores an upstream controller, operator or counterparty identity | Validate caller authority/identity as specified; do not inherit downstream service requirements merely from the reference. |

Separate deployment order from readiness order. If A consumes B, but B only stores A's address for authorization, a valid sequence is: deploy A; deploy B bound to A; configure, Kernel-activate and enable B; bind B on A; enable A. B must not require A enabled merely because it stores A's identity. A controller C that consumes A may need A operational; A need not check C's lifecycle. Constructors and binding setters must permit the agreed startup sequence, including any required Kernel activation before binding.

A controller's consumers should not inspect that upstream controller's activity, enablement, interface or reverse binding unless the approved API explicitly requires it. At each forwarding hop, distinguish the external user from the contract caller: the user's ADMIN role is not inherited by the forwarder; use its selected-controller binding or delegated role.

Do not infer transitive readiness from an enabled parent. A previously enabled policy can stay enabled while a direct service is paused, deactivated or migrated independently. Conversely, do not recursively walk the graph or add guards to action paths that do not consume that service. For a multi-action policy, activation covers its required operational services; per-operation checks follow the services that operation actually uses.

An optional service with an approved fallback need not be operational for activation. Recovery may intentionally remain available while a target is paused or inactive. Document those exceptions by operation rather than imposing readiness on every stored reference. Do not add Enabler or ReEnabler merely because a contract is consumed; independent operation, pausing or recovery must justify the lifecycle surface.

Configuration timelocks have a specific activation boundary: enable and reEnable require compatible consumed target interfaces, the same Kernel, active target Policy membership and selection as the target's current configOperator. Target local enablement is not required or read at activation, so the queue can be repaired while its target remains paused. Queueing/executing configuration and recovery requires the target Kernel-active; inactive-target mutations are not an accepted precedent. Local target enablement remains operation-specific. Ordinary configuration respects the operational pause; explicit custody/claim recovery can remain usable while paused. Document that reasoning per operation rather than copying one target-enabled gate to every selector. See [config-timelock-design](../config-timelock-design/SKILL.md) for the complete queue contract.

## Validate dependency selection and activation

Define two predicates for each relationship: **compatibility** (the right kind of contract and binding) and **readiness** (usable now). Reuse those predicates in the setter and enable/reEnable when they enforce the same relationship. A setter may require a ready replacement, but construction or an identity-only binding must not inherit that requirement without an agreed deployment reason.

Before accepting a candidate, check the applicable requirements:

- Address/code and the interfaces actually consumed, including version discovery when required. Distinguish ERC165 interface IDs from individual function selectors; support advertisement does not prove behavior. Enforce numeric version constraints only when the integration defines them.
- For a Policy, check its reported Kernel and authoritative membership through the consumer's intended `kernel.isPolicyActive(candidate)`. A self-reported `kernel()` alone can be faked; active membership alone does not prove reported Kernel or system binding.
- Where a shared system binding exists, compare the candidate's identity getter with an independently authoritative expected address. Use a small shared interface if several components expose that binding; no universal `core()` getter, reverse selection or new base contract is implied.
- Read untrusted compatibility/status getters with `staticcall` or an existing equivalent safe probe. Reject failed calls and malformed ABI, including noncanonical address/bool values, with the shared Kernel/status error or the consumer's error for other metadata. Do not bubble arbitrary candidate errors or rely on ABI-decode panics. A readable `isEnabled() == false` is a readiness failure, not malformed compatibility.
- Apply local enablement and active membership only where readiness is required. Do not probe irrelevant upstream status or block approved recovery/fallback paths.

Keep the error distinction deliberate and consistent across selection and activation, using the agreed product names:

| Condition | Error contract |
| --- | --- |
| Missing required interface/code, incompatible version/binding, or failed/malformed other required getter | Component-specific `InvalidDependency(candidate)`, such as `InvalidInventory(candidate)`; include the candidate address. |
| Failed or malformed Kernel/isEnabled getter | Generic `PolicyDependency_InvalidDependency(dependency)` from the shared library. |
| A canonical reported Kernel differs from the consumer's Kernel | Generic `PolicyDependency_KernelMismatch(dependency,expectedKernel,reportedKernel)` at construction, binding setters, enable/reEnable and runtime validation. |
| Compatible operational dependency is Kernel-inactive or locally disabled | Generic `PolicyDependency_NotActive(dependency)` for operational readiness. Preserve explicitly agreed replacement-setter errors, such as Core's component-specific invalid-candidate errors. |
| Required pointer is unset | Explicit dependency-not-set error if defined by the API; do not make an external call to address zero. |
| Subject policy is inactive or disabled | Own-policy activity error or inherited local-disabled error, distinct from dependency failure. |

Check compatibility before readiness so a wrong Kernel or binding is not reported as a pause. Preserve earlier subject-state/authorization guards. Mandatory zero candidates remain invalid even when the current pointer is unset; optional zero/clear behavior must be specified. Follow the repository's unchanged-contract-pointer rejection before candidate probing or handoff work; ordinary configuration no-ops and documented exceptions are separate rules.

Use the stateless `PolicyDependency` library for shared Policy Kernel/readiness checks and its generic `PolicyDependency_KernelMismatch`, `PolicyDependency_InvalidDependency` and `PolicyDependency_NotActive` errors. Use a dedicated Kernel-mismatch error for a readable foreign Kernel at every validation boundary. Preserve component-specific invalid-dependency errors for other failed/malformed metadata and wrong system bindings. Check the reported Kernel before dependency readiness, so inactivity cannot mask a readable mismatch. Actual inactivity in the intended Kernel remains a readiness failure when the dependency's identity is otherwise compatible. During scenario work, record old source selectors as pending implementation rather than changing contracts or claiming the new error is already tested.

Prefer a small internal helper shared by setters and activation hooks, or reuse an existing base's hook. Keep component-specific token, accounting and migration checks in the caller. Avoid a new dependency registry, recursive graph validation, generic error forwarding or extra inheritance solely to centralize a few checks. Binding identity must not silently introduce upstream readiness checks.

## Dependency scenario proof

Keep enable and reEnable prerequisites identical. For each operational Policy dependency, cover active/enabled, inactive/enabled, active/disabled and inactive/disabled while other prerequisites pass. Use permitted callers here; unauthorized coverage belongs in its own table. Include reachable drift after successful activation, restoration/retry, and one valid startup sequence that demonstrates there is no activation cycle.

At public binding boundaries, cover required interfaces, reported Kernel versus actual membership, wrong binding, and failed/malformed required reads. Prove the consumer-owned error and unchanged pointer/accounting/events. Include a competing compatibility/readiness fault to establish precedence. Check unchanged-pointer rejection without candidate probes or handoff effects.

Test revalidation only where the state is reachable. Do not duplicate every invalid-interface case in enable/reEnable if validated installation and immutable code/binding make it impossible; do cover independently changeable lifecycle and Kernel state. An identity-only upstream reference must not fail just because the upstream contract is disabled. Plain helpers and approved fallback/recovery modes need their own actual requirements, not a fabricated Policy matrix.

## Ordinary function admission and errors

Repository default for ordinary actions and configuration mutations: apply existing reentrancy guards first, then require own Policy activity, required local enablement, and caller authority, before input validation, idempotent returns, transfers or module writes. Test competing faults to establish this order, including inactive/disabled policies with unauthorized callers or broken cached ROLES. Eventual Module_PolicyNotPermitted or downstream authorization failure is not a substitute for an explicit own-activity error.

Keep intentional exceptions explicit: disabled-capable recovery and configuration omit the enabled requirement; active disabled tasks retain their authorized no-op behavior. Lifecycle transitions retain inherited state/history/authorization/grace ordering, and disable remains available while inactive. Self-only scheduler calls and queued-action existence, terminal-state and execution-window checks retain their framework boundaries. Do not add a reentrancy guard solely to match this ordering.

EMERGENCY cancellation of a configuration-timelock action requires the queue Kernel-active, but permits local disablement and makes no target/operator readiness calls. Cancellation removes pending intent without executing target code, so pausing a queue or breaking its target must not prevent cleanup. Own Kernel inactivity still rejects. Configuration-state commitments should include the current selected config operator by default, alongside only relevant settings; retain live authority checks and current-state restoration semantics rather than inventing a rotation epoch.

Distinguish the inactive subject from an unavailable dependency in the agreed API: own `PolicyNotActive(policy)` versus shared `PolicyDependency_NotActive(dependency)`. A disabled subject can retain inherited NotEnabled(); a disabled dependency should identify the dependency. Preserve explicitly agreed replacement-setter errors. Missing/unset dependency errors are distinct when the API defines them. Do not rename unrelated inherited errors or invent new errors during scenario maintenance.

Do not apply ordinary admission to framework hooks or all views automatically. configureDependencies, requestPermissions, changeKernel, interface queries and getters follow their actual framework/read semantics; dependency setup must remain usable for installation/migration. Preview requirements and explicit execution-only exceptions are defined in the scenario skill.

## Caller, time and transition proof

Fuzz equivalent permitted roles in one family, guaranteeing each exclusive class and overlaps; exclude all permitted identities from unauthorized fuzzing. Do not duplicate the same dependency/time table per role. Match exact errors and arguments, enabled flag, transition timestamp, event fields/emitter and relevant rollback. Keep initialized history, caller, dependency faults and timing independently variable where they affect outcomes.

For grace checks, define L=lastTransitionAt, G=gracePeriod and D=L+G. Derive inclusive/exclusive semantics from the agreed API. For the repository's inclusive deadline, fuzz valid now in L..D and expired now in D+1..MAX48 when nonempty, with exact and adjacent deterministic seeds. Include never-enabled history separately.

Where informative deadline overflow is required, widen the addition and check narrowing; assert the exact SafeCast error rather than accepting an arithmetic panic. Do not cap a duration setter against an unknown future disable timestamp. Preserve shared ReEnabler behavior unless changing it is authorized.

Explicit setter exception: ReEnablerGracePeriod.setGracePeriod with the same valid nonzero period succeeds and emits GracePeriodSet once; it does not change enabled state or the last transition timestamp. Do not add an equality shortcut merely to match ordinary configuration no-ops.

For lifecycle callbacks, use the scenario skill's representative-boundary approach; authorize the nested path enough to reach the guard. Check retry after restoration without changing user accounting. Follow repository test-writing guidance for implementation and report missing source checks as implementation work, not completed coverage.
