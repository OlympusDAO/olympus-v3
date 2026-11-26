# BurnerLoansUniswapV3Adapter swap scenarios

Source: `src/periphery/adapters/BurnerLoansUniswapV3Adapter.sol` and its separate MIT
interface. The adapter advertises its swap and route discovery interface over ERC-165 and uses the
pinned Uniswap V3 `ISwapRouter` exact-input and exact-output boundaries.

Caller A funds only itself. Output and unused route balances go to A (Composites when it calls the
adapter). The adapter preserves the balance it held before the swap for each route token. The router
is immutable. Route data specifies tokens and pool fees. Path encoding is token(20 bytes),
fee(3 bytes), token(20 bytes), repeated for multihop. Amount, output minimum and deadline are uint256;
all amounts use raw units of their respective tokens. Deadline is inclusive. The adapter has no
Kernel membership or enabled state. Unchanged includes all balances and allowances; failure commits
no events. No onchain preview/oracle is proposed.

This suite owns Uniswap path format/endpoints and router-specific behavior. Composites treats
the path as opaque bytes and tests forwarding through a controlled adapter. Its own minAmountOut
check uses actual receipts independently of any minimum enforced here or by the router; it must
reject a short receipt even when an adapter reports success. See the shared
[Composites swap boundary](../BurnerLoansComposites/execute.md#9-conversion-and-swap-cases).
The unit adapter mock is sufficient for Composites forwarding/minimum tests; this adapter's separate
fork tests call the deployed Uniswap V3 `ISwapRouter` at mainnet block 26,447,690. Both swap modes
exercise DAI → USDC → USDe and DAI → WETH → USDC → USDe, with paths encoded in reverse for exact
output. The Composites flash-loan fork tests also exercise OHM to DAI repayment routes.

## Exact input

The adapter pays each hop from the previous hop's actual receipt. It returns unused initial input
and any intermediate remainder after enforcing the final output minimum.

| ID | Caller | Input / condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRSW-P01 | Fuzz caller | Funded single-hop exact-input path | Success | Actual output returned to caller | Covered: [test][test_whenValidPath] |
| BLRSW-A01 | Zero caller in the test harness | Valid exact-input path with an ERC-20 allowance of zero | `ERC20InsufficientAllowance(adapter, 0, amountIn)` | Starting adapter balances and allowance preserved, with no output sent | Covered: [test][test_whenCallerIsZero_reverts] |
| BLRSW-P02 | A | Two different DAI to USDe paths at call time | Both work when routes exist | Same fixed call boundary; caller controls path | Covered: [USDC][test_whenRealExactInputUsesUsdcRoute], [WETH][test_whenRealExactInputUsesWethRoute] |
| BLRSW-P03 | Deployer | Construct with a valid router | Advertise ERC-165 and the swap interface | Invalid ERC-165 ID is rejected | Covered: [test][test_whenConstructedAdvertisesSwapInterface] |
| BLRSW-I01 | A | Zero token endpoint; same-token endpoints (separate tests) | Reject invalid endpoints | Unchanged | Covered: [test][test_whenEndpointIsZero_reverts], [test][test_whenEndpointsAreIdentical_reverts] |
| BLRSW-I02 | A | Empty or short paths, and malformed lengths with valid endpoints | Reject path in both discovery and execution | Unchanged | Covered: [test][test_whenPathIsTooShort_reverts], [test][test_whenPathHasExtraBytesBetweenValidEndpoints_reverts] |
| BLRSW-I03 | A | Path first/last token differs from supplied endpoints (separate tests) | Reject path | Unchanged | Covered: [test][test_whenPathEndpointDiffers_reverts] |
| BLRSW-N01 | A | Amount 0,1,max256; insufficient balance/allowance at exact boundary | Zero rejects; funded inputs pass; missing input rejects | Cannot spend starting balances | Covered: [test][test_whenInputIsZero_reverts], [test][test_whenExactInputIsFunded], [test][test_whenExactInputAtBoundaryIsFunded], [test][test_whenInputAllowanceIsShort_reverts], [test][test_whenWalletInputIsShort_reverts] |
| BLRSW-N02 | A | Minimum 0,1,actual-1,actual,actual+1,max256 | Zero rejects; equality succeeds; short receipt rejects | Actual received output determines success | Covered: [test][test_whenValidPath], [test][test_whenRouterReportsOutputAboveReceipt_reverts], [test][test_whenMinimumIsZero_reverts], [test][test_whenMinimumFitsOutput], [test][test_whenMinimumFitsOutputBoundarySeeds], [test][test_whenMinimumIsAboveOutput_reverts], [test][test_whenMinimumAtFailureBoundary_reverts] |
| BLRSW-N03 | A | Deadline now-1,now,now+1,max256 | Expiry rejects; equality and future succeed | Unchanged on error | Covered: [test][test_whenValidPath], [test][test_whenDeadlineHasPassed_reverts], [test][test_whenDeadlineIsInFuture], [test][test_whenDeadlineIsAtFutureBoundary] |
| BLRSW-T01 | A | Router lies about delivered output | Compare actual receipt | No fictitious output credit | Covered: [test][test_whenRouterReportsOutputAboveReceipt_reverts] |
| BLRSW-T02 | A | Adapter starts with input/output balances | Successful trade | Preserve both starting balances and clear router allowance | Covered: [test][test_whenValidPath] |
| BLRSW-T03 | A | Either pinned exact-input path misses the output minimum, or a mandatory output transfer fails | Propagate stable dependency error | Unchanged | Covered: [USDC][test_whenUsdcRouteCannotMeetMinimum_reverts], [WETH][test_whenWethRouteCannotMeetMinimum_reverts], [test][test_whenTokenPropagatesNestedSwap_reverts] |
| BLRSW-C01 | Token/router | Funded nested swap during input, router or output callback (separate tests) | Reentrancy guard rejects | Caught failure applies outer swap once; propagated failure restores all | Covered: [test][test_whenRouterAttemptsNestedSwap], [test][test_whenRouterPropagatesNestedSwap_reverts], [test][test_whenTokenCatchesNestedSwap], [test][test_whenTokenPropagatesNestedSwap_reverts] |
| BLRSW-P05 | A | Router spends less than funded input and meets the output minimum | Success | Return unused input and output to A | Covered: [test][test_whenRouterSpendsLessThanFundedInput] |
| BLRSW-P07 | A | A later hop consumes only part of the prior hop's output | Success at the final output minimum | Return the intermediate remainder and output to A. Preserve pre-existing adapter and router balances and clear hop allowances. | Covered: [test][test_whenRouteLeavesIntermediateRemainder] |
| BLRSW-I04 | Deployer | Router is zero or lacks code | InvalidRouter(router) | No deployment | Covered: [test][test_whenRouterHasNoCode_reverts] |

## Exact output

Exact-output paths put the output token first and the input token last, including across multiple
hops. The router receives a fixed output amount and the caller’s maximum input. The adapter
measures the debit and output, returns unused route balances, and preserves the starting balance
of each route token.

| ID | Caller | Input / condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRSW-P04 | A | Reverse path and router spends within the cap | Buy requested output | Return unused input, intermediate proceeds and output to A. Preserve starting balances and clear router allowance. | Covered: [test][test_whenExactOutputUsesReversePathAndRefundsUnusedInput] |
| BLRSW-I05 | A | Forward path supplied for exact output | InvalidRoute | Unchanged | Covered: [test][test_whenExactOutputUsesForwardPath_reverts] |
| BLRSW-T05 | A | Router reports success with a short output | Reject actual receipt below amountOut | Unchanged | Covered: [test][test_whenExactOutputReceiptIsShort_reverts] |
| BLRSW-T06 | A | Router debits one unit of the adapter’s starting input balance after spending the full cap | Reject actual spend above maxAmountIn | Caller funds, starting balance and allowance are restored | Covered: [test][test_whenExactOutputSpendsProtectedInput_reverts] |
| BLRSW-N04 | A | Zero or maximum exact-output amount or input cap | Reject zero. Funded maximum amounts settle within the cap | Actual debit and output determine the balances | Covered: [test][test_whenExactOutputIncludesZeroAmount_reverts], [test][test_whenExactOutputUsesMaximumAmounts] |
| BLRSW-P06 | A | Either pinned reverse path through the deployed V3 router with a 100 DAI cap | Buy exactly 10 USDe | Return unused DAI, preserve starting balances and clear the router allowance | Covered: [USDC][test_whenRealExactOutputUsesUsdcRoute], [WETH][test_whenRealExactOutputUsesWethRoute] |
| BLRSW-T07 | A | Either pinned reverse path through the deployed V3 router with a 1 DAI cap to buy 10 USDe | Revert | Restore wallet balances and allowances | Covered: [USDC][test_whenUsdcRouteExceedsInputCap_reverts], [WETH][test_whenWethRouteExceedsInputCap_reverts] |

## Shared route discovery

| ID | Caller | Input / condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRSW-P08 | Anyone | Single-hop path and a multihop path with a repeated token address | Return intermediate positions in path order, including repeats | No balance or allowance changes | Covered: [test][test_whenReadingRouteIntermediates] |

## Caller settlement

| ID | Caller | Input / condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRSW-T08 | A | Output transfer fee leaves caller's receipt below the required amount in either swap mode | Revert with the actual short receipt | Input and output transfers roll back | Covered: [test][test_whenOutputTransferFeeReducesCallerReceiptBelowMinimum_reverts] |

[test_whenValidPath]: ./swap.t.sol#L77
[test_whenCallerIsZero_reverts]: ./swap.t.sol#L111
[test_whenRealExactInputUsesUsdcRoute]: ../BurnerLoansComposites/externalRoutesFork.t.sol#L114
[test_whenRealExactInputUsesWethRoute]: ../BurnerLoansComposites/externalRoutesFork.t.sol#L119
[test_whenPathEndpointDiffers_reverts]: ./swap.t.sol#L173
[test_whenRouterReportsOutputAboveReceipt_reverts]: ./swap.t.sol#L186
[test_whenDeadlineHasPassed_reverts]: ./swap.t.sol#L289
[test_whenRouterSpendsLessThanFundedInput]: ./swap.t.sol#L227
[test_whenRouteLeavesIntermediateRemainder]: ./swap.t.sol#L236
[test_whenReadingRouteIntermediates]: ./swap.t.sol#L55
[test_whenOutputTransferFeeReducesCallerReceiptBelowMinimum_reverts]: ./swap.t.sol#L203
[test_whenRouterAttemptsNestedSwap]: ./swap.t.sol#L303
[test_whenUsdcRouteCannotMeetMinimum_reverts]: ../BurnerLoansComposites/externalRoutesFork.t.sol#L135
[test_whenWethRouteCannotMeetMinimum_reverts]: ../BurnerLoansComposites/externalRoutesFork.t.sol#L140
[test_whenEndpointIsZero_reverts]: ./swap.t.sol#L353
[test_whenEndpointsAreIdentical_reverts]: ./swap.t.sol#L361
[test_whenInputIsZero_reverts]: ./swap.t.sol#L368
[test_whenExactInputIsFunded]: ./swap.t.sol#L377
[test_whenExactInputAtBoundaryIsFunded]: ./swap.t.sol#L382
[test_whenInputAllowanceIsShort_reverts]: ./swap.t.sol#L390
[test_whenWalletInputIsShort_reverts]: ./swap.t.sol#L407
[test_whenMinimumIsZero_reverts]: ./swap.t.sol#L425
[test_whenMinimumFitsOutput]: ./swap.t.sol#L434
[test_whenMinimumFitsOutputBoundarySeeds]: ./swap.t.sol#L439
[test_whenMinimumIsAboveOutput_reverts]: ./swap.t.sol#L447
[test_whenMinimumAtFailureBoundary_reverts]: ./swap.t.sol#L452
[test_whenDeadlineIsInFuture]: ./swap.t.sol#L458
[test_whenDeadlineIsAtFutureBoundary]: ./swap.t.sol#L463
[test_whenTokenPropagatesNestedSwap_reverts]: ./swap.t.sol#L344
[test_whenRouterPropagatesNestedSwap_reverts]: ./swap.t.sol#L318
[test_whenTokenCatchesNestedSwap]: ./swap.t.sol#L329
[test_whenRouterHasNoCode_reverts]: ./swap.t.sol#L164
[test_whenPathIsTooShort_reverts]: ./swap.t.sol#L136
[test_whenPathHasExtraBytesBetweenValidEndpoints_reverts]: ./swap.t.sol#L147
[test_whenConstructedAdvertisesSwapInterface]: ./swap.t.sol#L44
[test_whenExactOutputUsesReversePathAndRefundsUnusedInput]: ./swap.t.sol#L577
[test_whenExactOutputUsesForwardPath_reverts]: ./swap.t.sol#L621
[test_whenExactOutputReceiptIsShort_reverts]: ./swap.t.sol#L631
[test_whenExactOutputIncludesZeroAmount_reverts]: ./swap.t.sol#L646
[test_whenExactOutputUsesMaximumAmounts]: ./swap.t.sol#L657
[test_whenRealExactOutputUsesUsdcRoute]: ../BurnerLoansComposites/externalRoutesFork.t.sol#L171
[test_whenRealExactOutputUsesWethRoute]: ../BurnerLoansComposites/externalRoutesFork.t.sol#L176
[test_whenUsdcRouteExceedsInputCap_reverts]: ../BurnerLoansComposites/externalRoutesFork.t.sol#L205
[test_whenWethRouteExceedsInputCap_reverts]: ../BurnerLoansComposites/externalRoutesFork.t.sol#L210
[test_whenExactOutputSpendsProtectedInput_reverts]: ./swap.t.sol#L674
