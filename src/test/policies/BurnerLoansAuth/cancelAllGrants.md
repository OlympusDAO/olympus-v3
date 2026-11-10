# BurnerLoansAuth.cancelAllGrants

Source: inherited `OperatorAuth.cancelAllGrants`. The borrower calls the selected Auth with real,
active/enabled Core. Caller A and a fuzzed second owner B both grant the same operator O reusable
authority. B excludes zero, A and O so both grants have distinct nonzero owners and operators. The generic
[cancelAllGrants scenarios](../utils/OperatorAuth/cancelAllGrants.md) own the complete engine matrix.

| ID | Caller | Execution | Effects | Test |
| --- | --- | --- | --- | --- |
| BLAUTH-CANCELALL-P01 | Borrower A; fuzz distinct owner B | Cancels only A's grants | A account epoch advances; both pair counters stay unchanged; A loses authority; B keeps its account epoch, complete grant, original stamp and authority; custody/principal unchanged | Covered: [test][test_whenAccountCancelled] |

[test_whenAccountCancelled]: ./cancelAllGrantsCoreIntegration.t.sol#L8
