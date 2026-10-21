// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansConfigTimelockTest} from "../BurnerLoansConfigTimelockTest.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";

/// @dev Shared setup and helpers for rescue queue tests; no runnable tests are inherited.
///      Both rescue previews and executions require a Kernel-active facility and permit local
///      disablement. Config must remain active and enabled.
///      All amounts below are base units of the 18-decimal rescue token.
// Fixture-sized amounts and expected-revert calls intentionally use literals and ignore returns.
// forge-lint: disable-start(literal-instead-of-constant,unused-return)
abstract contract BurnerLoansRescueQueueTest is BurnerLoansConfigTimelockTest {
    uint8 internal constant _TOKEN_DECIMALS = 18;
    uint256 internal constant _FEE_PAYOUT = 20;
    uint256 internal constant _SEIZURE_PAYOUT = 30;
    uint256 internal constant _KEEPER_PAYOUT = 10;
    uint256 internal constant _SURPLUS_PAYOUT = 5;
    uint256 internal constant _ROLE_PAYOUT = _FEE_PAYOUT + _SEIZURE_PAYOUT;
    uint256 internal constant _RESERVE = _ROLE_PAYOUT + _KEEPER_PAYOUT;
    uint256 internal constant _CUSTODY = _RESERVE + _SURPLUS_PAYOUT;

    MockRevertingTransferToken internal _rescueAsset;
    address internal _rescueKeeper;
    address internal _rescueDestination;

    function setUp() public virtual override {
        super.setUp();
        _rescueKeeper = makeAddr("rescue matrix keeper");
        _rescueDestination = makeAddr("rescue matrix destination");
        _rescueAsset = _createPendingRescueAsset(_rescueKeeper);
    }

    /// @dev Transfers to the original recipients fail, creating immediately rescuable liabilities.
    function _createPendingRescueAsset(
        address keeper_
    ) internal returns (MockRevertingTransferToken asset) {
        asset = new MockRevertingTransferToken(_TOKEN_DECIMALS);
        asset.mint(alice, _FEE_PAYOUT);
        asset.mint(address(burnerLoans), _SEIZURE_PAYOUT + _KEEPER_PAYOUT + _SURPLUS_PAYOUT);
        vm.prank(alice);
        assertTrue(asset.approve(address(burnerLoans), _FEE_PAYOUT), "fee approval succeeds");
        asset.setTransferReverts(address(trsry), true);
        asset.setTransferReverts(keeper_, true);
        burnerLoans.recordPendingFeeForTest(address(asset), alice, address(trsry), _FEE_PAYOUT);
        burnerLoans.recordPendingSeizedCollateralForTest(
            address(asset),
            address(trsry),
            _SEIZURE_PAYOUT
        );
        burnerLoans.recordPendingSeizureRewardForTest(address(asset), keeper_, _KEEPER_PAYOUT);
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unused-return)
