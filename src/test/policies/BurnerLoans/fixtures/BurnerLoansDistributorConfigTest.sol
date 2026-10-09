// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test bounds prove casts fit; fixtures intentionally ignore successful token return values and use
// scenario-specific literals for auditability.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return)

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoansContext} from "src/policies/interfaces/IBurnerLoansSeizureContext.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {RevenueDistributorConfigTimelock} from "src/policies/RevenueDistributorConfigTimelock.sol";
import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

abstract contract BurnerLoansDistributorConfigTest is BurnerLoansTest {
    bytes4 internal constant KERNEL_SELECTOR = bytes4(keccak256("kernel()"));
    uint256 internal constant PENDING_FEE = 11e6;
    uint256 internal constant PENDING_SEIZURE = 17e6;
    uint256 internal constant PENDING_REWARD = 23e6;

    address internal keeper;

    struct RoutingSnapshot {
        address distributor;
        bool sendFees;
        bool sendYield;
        uint256 facilityBalance;
        uint256 treasuryBalance;
        uint256 pendingFee;
        uint256 pendingSeizure;
        uint256 pendingReward;
        uint256 totalPending;
    }

    function setUp() public virtual override {
        super.setUp();
        keeper = makeAddr("keeper");
    }

    function _deployRevenueDistributor(
        bool enabled_,
        bool listUsds_
    ) internal returns (RevenueDistributor distributor) {
        vm.startPrank(admin);
        distributor = new RevenueDistributor(kernel);
        RevenueDistributorConfigTimelock timelock = new RevenueDistributorConfigTimelock(
            kernel,
            distributor
        );
        kernel.executeAction(Actions.ActivatePolicy, address(distributor));
        kernel.executeAction(Actions.ActivatePolicy, address(timelock));
        if (enabled_) distributor.enable("");
        timelock.enable("");
        distributor.setConfigOperator(address(timelock));
        vm.stopPrank();

        if (listUsds_) {
            IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](
                0
            );
            vm.prank(address(timelock));
            distributor.setAssetRoutes(address(usds), 0, routes);
        }
    }

    function _selectRevenueDistributor(RevenueDistributor distributor_) internal {
        vm.prank(admin);
        burnerLoans.setRevenueDistributor(address(distributor_));
    }

    function _setFeeFlag(bool enabled_) internal {
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setSendFeesToDistributor(enabled_);
    }

    function _setYieldFlag(bool enabled_) internal {
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setSendYieldToDistributor(enabled_);
    }

    function _setConfigOperator(address operator_) internal {
        vm.prank(admin);
        burnerLoansConfig.setConfigOperator(operator_);
    }

    function _snapshotRouting() internal view returns (RoutingSnapshot memory snapshot) {
        snapshot = RoutingSnapshot({
            distributor: burnerLoans.revenueDistributor(),
            sendFees: burnerLoans.sendFeesToDistributor(),
            sendYield: burnerLoans.sendYieldToDistributor(),
            facilityBalance: usds.balanceOf(address(burnerLoans)),
            treasuryBalance: usds.balanceOf(address(trsry)),
            pendingFee: burnerLoans.pendingFeeForTest(address(usds)),
            pendingSeizure: burnerLoans.pendingSeizureForTest(address(usds)),
            pendingReward: burnerLoans.pendingSeizureRewardForTest(address(usds), keeper),
            totalPending: burnerLoans.totalPendingForTest(address(usds))
        });
    }

    function _assertRoutingUnchanged(RoutingSnapshot memory before_) internal view {
        RoutingSnapshot memory after_ = _snapshotRouting();
        assertEq(after_.distributor, before_.distributor, "distributor pointer");
        assertEq(after_.sendFees, before_.sendFees, "fee routing flag");
        assertEq(after_.sendYield, before_.sendYield, "yield routing flag");
        assertEq(after_.facilityBalance, before_.facilityBalance, "facility token balance");
        assertEq(after_.treasuryBalance, before_.treasuryBalance, "Treasury token balance");
        assertEq(after_.pendingFee, before_.pendingFee, "pending fee");
        assertEq(after_.pendingSeizure, before_.pendingSeizure, "pending seizure");
        assertEq(after_.pendingReward, before_.pendingReward, "pending keeper reward");
        assertEq(after_.totalPending, before_.totalPending, "total pending payout");
    }

    function _seedPendingPayouts(address feeRecipient_) internal {
        uint256 total = PENDING_FEE + PENDING_SEIZURE + PENDING_REWARD;
        usds.mint(alice, PENDING_FEE);
        usds.mint(address(burnerLoans), total - PENDING_FEE);
        vm.prank(alice);
        usds.approve(address(burnerLoans), PENDING_FEE);

        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, feeRecipient_, PENDING_FEE),
            abi.encodeWithSignature("Error(string)", "fee blocked")
        );
        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, address(trsry), PENDING_SEIZURE),
            abi.encodeWithSignature("Error(string)", "seizure blocked")
        );
        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, keeper, PENDING_REWARD),
            abi.encodeWithSignature("Error(string)", "reward blocked")
        );

        burnerLoans.recordPendingFeeForTest(address(usds), alice, feeRecipient_, PENDING_FEE);
        burnerLoans.recordPendingSeizedCollateralForTest(
            address(usds),
            address(trsry),
            PENDING_SEIZURE
        );
        burnerLoans.recordPendingSeizureRewardForTest(address(usds), keeper, PENDING_REWARD);
        vm.clearMockedCalls();

        _assertPendingPayouts(address(usds), keeper, PENDING_FEE, PENDING_SEIZURE, PENDING_REWARD);
        assertEq(usds.balanceOf(address(burnerLoans)), total, "pending custody");
    }

    function _assertPendingRecipients(address feeRecipient_) internal view {
        address[] memory recipients = burnerLoans.getPendingPayoutRecipients(address(usds));
        uint256 expectedCount = feeRecipient_ == address(trsry) || feeRecipient_ == keeper ? 2 : 3;
        assertEq(recipients.length, expectedCount, "pending recipient count");
        assertTrue(_contains(recipients, feeRecipient_), "fee recipient enumerated");
        assertTrue(_contains(recipients, address(trsry)), "Treasury enumerated");
        assertTrue(_contains(recipients, keeper), "keeper enumerated");
    }

    function _assertPendingStatePreserved(RoutingSnapshot memory before_) internal view {
        assertEq(
            burnerLoans.pendingFeeForTest(address(usds)),
            before_.pendingFee,
            "pending fee preserved"
        );
        assertEq(
            burnerLoans.pendingSeizureForTest(address(usds)),
            before_.pendingSeizure,
            "pending seizure preserved"
        );
        assertEq(
            burnerLoans.pendingSeizureRewardForTest(address(usds), keeper),
            before_.pendingReward,
            "pending reward preserved"
        );
        assertEq(
            burnerLoans.totalPendingForTest(address(usds)),
            before_.totalPending,
            "total pending preserved"
        );
        assertEq(
            usds.balanceOf(address(burnerLoans)),
            before_.facilityBalance,
            "pending custody preserved"
        );
    }

    function _contains(address[] memory values_, address value_) internal pure returns (bool) {
        for (uint256 i; i < values_.length; ++i) {
            if (values_[i] == value_) return true;
        }
        return false;
    }

    function _yieldRecipient() internal view returns (address) {
        BurnerLoansContext memory dependencies = burnerLoans.context();
        return dependencies.yieldRecipient;
    }

    function _mockRevenueDistributorInterface(address distributor_, bool supported_) internal {
        vm.mockCall(
            distributor_,
            abi.encodeCall(IERC165.supportsInterface, (type(IRevenueDistributor).interfaceId)),
            abi.encode(supported_)
        );
    }

    function _mockEnablerInterface(address distributor_, bool supported_) internal {
        vm.mockCall(
            distributor_,
            abi.encodeCall(IERC165.supportsInterface, (type(IEnabler).interfaceId)),
            abi.encode(supported_)
        );
    }

    function _mockKernelRevert(address distributor_) internal {
        vm.mockCallRevert(
            distributor_,
            abi.encodeWithSelector(KERNEL_SELECTOR),
            abi.encodeWithSignature("Error(string)", "kernel read failed")
        );
    }

    function _mockKernelMalformed(address distributor_) internal {
        vm.mockCall(distributor_, abi.encodeWithSelector(KERNEL_SELECTOR), hex"01");
    }

    function _mockEnabledRevert(address distributor_) internal {
        vm.mockCallRevert(
            distributor_,
            abi.encodeWithSelector(IEnabler.isEnabled.selector),
            abi.encodeWithSignature("Error(string)", "enabled read failed")
        );
    }

    function _mockEnabledMalformed(address distributor_) internal {
        vm.mockCall(distributor_, abi.encodeWithSelector(IEnabler.isEnabled.selector), hex"01");
    }

    function _driftRevenueDistributor(RevenueDistributor distributor_, uint8 state_) internal {
        state_ = uint8(bound(state_, 0, 6));
        if (state_ == 1) _deactivatePolicy(address(distributor_));
        if (state_ == 2) {
            vm.prank(admin);
            distributor_.disable("");
        }
        if (state_ == 3) _mockKernelRevert(address(distributor_));
        if (state_ == 4) _mockKernelMalformed(address(distributor_));
        if (state_ == 5) _mockEnabledRevert(address(distributor_));
        if (state_ == 6) _mockEnabledMalformed(address(distributor_));
    }

    function _expectInvalidRevenueDistributor(address distributor_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidRevenueDistributor.selector,
                distributor_
            )
        );
    }
}
