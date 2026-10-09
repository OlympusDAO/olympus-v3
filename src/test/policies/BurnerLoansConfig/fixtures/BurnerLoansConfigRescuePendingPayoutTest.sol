// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

/// @dev Pending-rescue forwarding fixture: distinct keeper and Treasury; 10 reward, 20 fee,
///      30 seizure base units. Custody exactly covers the 60 owed; no surplus is rescued.
abstract contract BurnerLoansConfigRescuePendingPayoutTestBase is BurnerLoansTest {
    uint256 internal constant _FEE = 20;
    uint256 internal constant _SEIZURE = 30;
    uint256 internal constant _REWARD = 10;
    uint256 internal constant _TOTAL_PENDING = _FEE + _SEIZURE + _REWARD;

    MockRevertingTransferToken internal _asset;
    address internal _keeper;

    function setUp() public virtual override {
        super.setUp();
        vm.prank(admin);
        burnerLoansConfig.setConfigOperator(address(configTimelock));
        _asset = new MockRevertingTransferToken(18);
        _keeper = makeAddr("original keeper");
        _asset.mint(alice, _FEE);
        _asset.mint(address(burnerLoans), _SEIZURE + _REWARD);
        vm.prank(alice);
        assertTrue(_asset.approve(address(burnerLoans), _FEE), "fee allowance is set");
        _asset.setTransferReverts(address(trsry), true);
        _asset.setTransferReverts(_keeper, true);
        burnerLoans.recordPendingFeeForTest(address(_asset), alice, address(trsry), _FEE);
        burnerLoans.recordPendingSeizedCollateralForTest(address(_asset), address(trsry), _SEIZURE);
        burnerLoans.recordPendingSeizureRewardForTest(address(_asset), _keeper, _REWARD);
        _assertPendingRescueBalances(0);
    }

    /// @dev This fixture rescues only keeper reward. Fee and seizure remain owed to Treasury.
    /// @param paid_ Exact base units redirected from the keeper's original 10-unit reward.
    // Fixed-fixture checks are intentionally reused by the discrete lifecycle loops.
    // forge-lint: disable-start(calls-loop)
    function _assertPendingRescueBalances(uint256 paid_) internal view {
        assertEq(_asset.balanceOf(alice), paid_, "destination receives the exact rescue");
        assertEq(
            _asset.balanceOf(address(burnerLoans)),
            _TOTAL_PENDING - paid_,
            "custody decreases by the rescue"
        );
        assertEq(
            _asset.balanceOf(address(burnerLoansConfig)),
            0,
            "Config never holds rescued tokens"
        );
        assertEq(_asset.balanceOf(_keeper), 0, "original keeper is not paid");
        assertEq(_asset.balanceOf(address(trsry)), 0, "unrelated Treasury is not paid");
        _assertPendingPayouts(address(_asset), _keeper, _FEE, _SEIZURE, _REWARD - paid_);
        assertEq(
            burnerLoans.pendingPayout(address(_asset), _keeper),
            _REWARD - paid_,
            "remaining keeper entitlement"
        );
        assertEq(
            burnerLoans.pendingPayout(address(_asset), address(trsry)),
            _FEE + _SEIZURE,
            "Treasury entitlement is unchanged"
        );
    }
    // forge-lint: disable-end(calls-loop)
}
