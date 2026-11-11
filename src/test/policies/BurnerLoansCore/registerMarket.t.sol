// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Libraries
import {BL_YIELD_CLAIMER_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {Actions} from "src/Kernel.sol";

contract BurnerLoansCoreRegisterMarketTest is BurnerLoansCoreTest {
    // Scenarios: BLCORE-MARKET-A01.
    function test_givenUnauthorized_whenRegistered_reverts(
        address caller_,
        address asset_,
        uint32 id_,
        bool shares_
    ) public {
        vm.assume(caller_ != address(_config));
        vm.expectRevert(
            abi.encodeWithSelector(IConfigOperator.ConfigOperator_Unauthorized.selector, caller_)
        );
        vm.prank(caller_);
        _core.registerMarket(asset_, id_, shares_);
    }

    // Scenarios: BLCORE-MARKET-A01.
    function test_givenAdminWithoutConfigOperatorAuthority_whenRegistered_reverts() public {
        _grantAdmin(_recipient);
        test_givenUnauthorized_whenRegistered_reverts(_recipient, address(_asset), 0, false);
    }

    // Scenarios: BLCORE-MARKET-A02, BLCORE-MARKET-L01, BLCORE-MARKET-P01.
    function test_givenNewAsset_whenRegistered(address asset_, uint32 id_, bool shares_) public {
        vm.assume(asset_ != address(_asset));
        uint256 count = _core.getAssetCount();
        vm.expectEmit(true, false, false, true, address(_core));
        emit IBurnerLoansCore.AssetRegistered(asset_);
        vm.prank(address(_config));
        _core.registerMarket(asset_, id_, shares_);
        assertEq(_core.getAssetCount(), count + 1, "Exactly one appended asset");
        assertEq(_core.getAssetAt(count), asset_, "Append order preserved");
        assertEq(_core.marketId(asset_), id_, "Trusted uint32 id stored without truncation");
        assertTrue(_core.isAssetRegistered(asset_), "Registration visible");
    }

    // Scenarios: BLCORE-MARKET-P01.
    function test_whenMarketIdBoundarySeeds() public {
        uint256 snapshot = vm.snapshotState();
        test_givenNewAsset_whenRegistered(address(0), 0, false);
        vm.revertToState(snapshot);
        snapshot = vm.snapshotState();
        test_givenNewAsset_whenRegistered(address(1), 1, true);
        vm.revertToState(snapshot);
        test_givenNewAsset_whenRegistered(address(2), type(uint32).max, false);
    }

    // Scenarios: BLCORE-MARKET-L03, BLCORE-MARKET-L04.
    function test_givenCoreInactive_whenRegistered_reverts(bool enabled_) public {
        _setCoreLifecycle(false, enabled_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_core)
            )
        );
        vm.prank(address(_config));
        _core.registerMarket(address(0), 0, false);
    }

    // Scenarios: BLCORE-MARKET-D01, BLCORE-MARKET-D02, BLCORE-MARKET-D03, BLCORE-MARKET-D04.
    function test_givenConfigUnavailable_whenRegistered(bool active_, bool enabled_) public {
        if (!enabled_) _config.disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        vm.mockCallRevert(
            address(_config),
            bytes(""),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        vm.prank(address(_config));
        _core.registerMarket(address(0xCAFE), 123, false);
        assertEq(_core.marketId(address(0xCAFE)), 123, "Selected authority is not introspected");
    }

    // Scenarios: BLCORE-MARKET-I01.
    function test_givenExistingAsset_whenMarketIdChanges_reverts(uint32 proposed_) public {
        uint32 current = _core.marketId(address(_asset));
        vm.assume(proposed_ != current);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_MarketMismatch.selector,
                address(_asset),
                current,
                proposed_
            )
        );
        vm.prank(address(_config));
        _core.registerMarket(address(_asset), proposed_, false);
        assertEq(
            _core.marketId(address(_asset)),
            current,
            "Mismatched update cannot rebind market"
        );
    }

    // Scenarios: BLCORE-MARKET-P02, BLCORE-MARKET-P03.
    function test_givenExistingAsset_whenModeUpdated(bool shares_) public {
        uint32 id = _core.marketId(address(_asset));
        uint256 count = _core.getAssetCount();
        bytes32 market = keccak256(abi.encode(_floan.getMarket(id)));
        vm.recordLogs();
        vm.prank(address(_config));
        _core.registerMarket(address(_asset), id, shares_);
        assertEq(_core.getAssetCount(), count, "Mode update never duplicates asset");
        assertEq(vm.getRecordedLogs().length, 0, "No duplicate registration event");
        assertEq(keccak256(abi.encode(_floan.getMarket(id))), market, "No FLOAN mutation");
        _rolesAdmin.grantRole(BL_YIELD_CLAIMER_ROLE, address(_collateral));
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature(
                "claimYield(address,address,uint256,bool)",
                address(_asset),
                _recipient,
                1,
                shares_
            ),
            abi.encode(address(_asset), uint256(0))
        );
        vm.expectCall(
            address(_depositManager),
            abi.encodeWithSignature(
                "claimYield(address,address,uint256,bool)",
                address(_asset),
                _recipient,
                1,
                shares_
            )
        );
        vm.prank(address(_collateral));
        _core.settleYield(address(_asset), 1, _recipient);
    }

    // Scenarios: BLCORE-MARKET-L02.
    function test_givenCoreDisabled_whenRegistered_reverts(
        address asset_,
        uint32 market_,
        bool shares_
    ) public {
        _core.disable("");
        bytes32 beforeState = _state();
        uint256 count = _core.getAssetCount();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(address(_config));
        _core.registerMarket(asset_, market_, shares_);
        assertEq(
            _state(),
            beforeState,
            "Disabled registration preserves accounting and configuration"
        );
        assertEq(_core.getAssetCount(), count, "Disabled registration cannot append an asset");
    }

    // Scenarios: BLCORE-MARKET-L02.
    function test_givenExistingAssetAndDisabledCore_whenModeUpdated_reverts(bool shares_) public {
        uint32 market = _core.marketId(address(_asset));
        _core.disable("");
        bytes32 beforeState = _state();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(address(_config));
        _core.registerMarket(address(_asset), market, shares_);
        assertEq(
            _state(),
            beforeState,
            "Pause blocks both changed-mode updates and unchanged no-ops"
        );
    }
}
