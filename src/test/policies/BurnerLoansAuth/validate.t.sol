// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IBurnerLoansAuth} from "src/policies/interfaces/burnerloans/IBurnerLoansAuth.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansAuthTest} from "src/test/policies/BurnerLoansAuth/BurnerLoansAuthTest.sol";
import {AuthKernelMock} from "src/test/policies/BurnerLoansAuth/fixtures/AuthKernelMock.sol";

contract BurnerLoansAuthValidateTest is BurnerLoansAuthTest {
    // Scenarios: BLAUTH-VALIDATE-D01.
    function test_givenForeignKernelReportsActive_whenAuthorityCaptured_reverts(
        bool owner_
    ) public {
        _approve(_grant(15, true));
        AuthKernelMock foreignKernel = new AuthKernelMock();
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(foreignKernel))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_core),
                address(_kernel),
                address(foreignKernel)
            )
        );
        _auth.captureAuthorization(_account, owner_ ? _account : _operator, 1);
    }

    // Scenarios: BLAUTH-VALIDATE-D01.
    function test_givenForeignKernelReportsActive_whenAuthorityValidated_reverts(
        bool owner_
    ) public {
        _approve(_grant(15, true));
        address operator = owner_ ? _account : _operator;
        bytes32 stamp = _auth.captureAuthorization(_account, operator, 1);
        AuthKernelMock foreignKernel = new AuthKernelMock();
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(foreignKernel))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_core),
                address(_kernel),
                address(foreignKernel)
            )
        );
        _auth.validate(_account, operator, 1, _asset, address(0), stamp);
    }

    // Scenarios: BLAUTH-VALIDATE-I01.
    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
    function test_whenDifferentAssetChecked_reverts(uint8 action_) public {
        uint8 action = uint8(1 << bound(action_, 0, 3));
        _approve(_grant(15, true));
        bytes32 stamp = _auth.captureAuthorization(_account, _operator, action);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansAuth.BurnerLoansAuth_AssetMismatch.selector,
                _asset,
                _otherAsset
            )
        );
        _auth.validate(_account, _operator, action, _otherAsset, _recipient, stamp);
    }

    // forge-lint: disable-end(unsafe-typecast)

    // Scenarios: BLAUTH-VALIDATE-I02.
    function test_whenDifferentRecipientChecked_reverts(bool withdraw_) public {
        uint8 action = withdraw_ ? 4 : 2;
        _approve(_grant(15, true));
        bytes32 stamp = _auth.captureAuthorization(_account, _operator, action);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansAuth.BurnerLoansAuth_RecipientMismatch.selector,
                _recipient,
                address(1)
            )
        );
        _auth.validate(_account, _operator, action, _asset, address(1), stamp);
    }

    // Scenarios: BLAUTH-VALIDATE-A01.
    function test_whenUnrelatedOperatorChecked_reverts(address operator_) public {
        vm.assume(operator_ != _account && operator_ != _operator && operator_ != address(0));
        _approve(_grant(15, true));
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        _auth.captureAuthorization(_account, operator_, 1);
    }

    // Scenarios: BLAUTH-VALIDATE-A02.
    function test_whenPermissionlessViewerChecksAuthorizedOperator(address viewer_) public {
        _approve(_grant(15, true));
        vm.prank(viewer_);
        bytes32 stamp = _auth.captureAuthorization(_account, _operator, 2);
        vm.prank(viewer_);
        assertEq(
            _auth.validate(_account, _operator, 2, _asset, _recipient, stamp),
            type(uint128).max,
            "View caller identity does not become operator authority"
        );
        assertEq(_auth.pairEpochs(_account, _operator), 1, "Views never consume another epoch");
    }

    // Scenarios: BLAUTH-VALIDATE-A03.
    function test_whenOwnerChecksUnsupportedAction_reverts(uint8 action_) public {
        vm.assume(action_ != 1 && action_ != 2 && action_ != 4 && action_ != 8);
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidAction.selector, action_)
        );
        _auth.validate(_account, _account, action_, address(0), address(0), bytes32(0));
    }

    // Scenarios: BLAUTH-VALIDATE-P01.
    function test_whenIndependentActionRecordsUsed() public {
        IOperatorAuth.Grant memory grant = _grant(15, true);
        IBurnerLoansAuth.Permissions memory p = _permissions();
        p.borrowAsset = _otherAsset;
        p.withdrawAsset = _otherAsset;
        p.withdrawRecipient = address(0xD00D);
        p.maxCollateral = 11;
        p.maxDebt = 22;
        p.minCollateral = 33;
        p.maxMaturity = 44;
        grant.permissions = abi.encode(p);
        _approve(grant);
        // Values are literal raw-unit resulting-position bounds; no decimal conversion occurs.
        assertEq(
            _check(1, _asset, address(0)),
            11,
            "Deposit resolves its independent collateral maximum"
        );
        assertEq(
            _check(2, _otherAsset, _recipient),
            22,
            "Borrow resolves raw OHM principal maximum"
        );
        assertEq(
            _check(4, _otherAsset, address(0xD00D)),
            33,
            "Withdrawal resolves remaining collateral minimum"
        );
        assertEq(_check(8, _asset, address(0)), 44, "Extension resolves absolute maturity maximum");
    }

    // Scenarios: BLAUTH-VALIDATE-P02.
    function test_whenRecipientWildcardUsed(address recipient_) public {
        IOperatorAuth.Grant memory grant = _grant(6, true);
        IBurnerLoansAuth.Permissions memory p = _permissions();
        p.borrowRecipient = address(0);
        p.withdrawRecipient = address(0);
        grant.permissions = abi.encode(p);
        _approve(grant);
        assertEq(
            _check(2, _asset, recipient_),
            type(uint128).max,
            "Zero borrow recipient does not restrict destination"
        );
        assertEq(
            _check(4, _asset, recipient_),
            0,
            "Zero withdrawal recipient does not restrict destination"
        );
    }

    // Scenarios: BLAUTH-VALIDATE-N01.
    function test_whenNumericLimitsAreZero() public {
        IOperatorAuth.Grant memory grant = _grant(15, true);
        IBurnerLoansAuth.Permissions memory p = _permissions();
        p.maxCollateral = 0;
        p.maxDebt = 0;
        p.minCollateral = 0;
        p.maxMaturity = 0;
        grant.permissions = abi.encode(p);
        _approve(grant);
        assertEq(_check(1, _asset, address(0)), 0, "Zero collateral maximum is literal");
        assertEq(_check(2, _asset, _recipient), 0, "Zero debt maximum is literal");
        assertEq(
            _check(4, _asset, _recipient),
            0,
            "Zero collateral floor imposes no positive minimum"
        );
        assertEq(_check(8, _asset, address(0)), 0, "Zero maturity maximum is literal");
    }

    // Scenarios: BLAUTH-VALIDATE-N02.
    function test_whenNumericLimitsAreMaximum() public {
        IOperatorAuth.Grant memory grant = _grant(15, true);
        IBurnerLoansAuth.Permissions memory p = _permissions();
        p.minCollateral = type(uint128).max;
        grant.permissions = abi.encode(p);
        _approve(grant);
        assertEq(
            _check(1, _asset, address(0)),
            type(uint128).max,
            "Maximum deposit bound retained"
        );
        assertEq(_check(2, _asset, _recipient), type(uint128).max, "Maximum OHM bound retained");
        assertEq(_check(4, _asset, _recipient), type(uint128).max, "Maximum floor retained");
        assertEq(
            _check(8, _asset, address(0)),
            type(uint48).max,
            "Maximum absolute maturity retained"
        );
    }

    // Scenarios: BLAUTH-VALIDATE-N03, BLAUTH-APPROVE-N01, BLAUTH-APPROVE-N02, BLAUTH-APPROVE-N03, BLAUTH-APPROVE-N04, BLAUTH-APPROVE-P04.
    function test_whenNumericLimitsVary(
        uint128 collateral_,
        uint128 debt_,
        uint128 floor_,
        uint48 maturity_,
        address borrowRecipient_,
        address withdrawRecipient_
    ) public {
        IOperatorAuth.Grant memory grant = _grant(15, true);
        IBurnerLoansAuth.Permissions memory p = _permissions();
        p.maxCollateral = collateral_;
        p.maxDebt = debt_;
        p.minCollateral = floor_;
        p.maxMaturity = maturity_;
        p.borrowRecipient = borrowRecipient_;
        p.withdrawRecipient = withdrawRecipient_;
        grant.permissions = abi.encode(p);
        _approve(grant);
        assertEq(
            abi.encode(_auth.getGrant(_account, _operator)),
            abi.encode(grant),
            "Accepted constraints and grant metadata round-trip unchanged"
        );
        assertEq(
            _auth.pairEpochs(_account, _operator),
            grant.pairEpoch + 1,
            "Approval consumes one pair epoch"
        );
        assertEq(_auth.accountEpochs(_account), grant.accountEpoch, "Account epoch is unchanged");
        assertEq(
            _check(1, _asset, address(0)),
            collateral_,
            "Entire collateral bound range retained"
        );
        assertEq(_check(2, _asset, borrowRecipient_), debt_, "Entire debt bound range retained");
        assertEq(_check(4, _asset, withdrawRecipient_), floor_, "Entire floor range retained");
        assertEq(_check(8, _asset, address(0)), maturity_, "Entire maturity range retained");
    }

    // Scenarios: BLAUTH-VALIDATE-N03, BLAUTH-APPROVE-N01, BLAUTH-APPROVE-N02, BLAUTH-APPROVE-N03, BLAUTH-APPROVE-N04, BLAUTH-APPROVE-P04.
    function test_whenConstraintBoundarySeeds() public {
        test_whenNumericLimitsVary(0, 0, 0, 0, address(0), address(0));
        test_whenNumericLimitsVary(1, 1, 1, 1, address(1), address(1));
        test_whenNumericLimitsVary(
            type(uint128).max - 1,
            type(uint128).max - 1,
            type(uint128).max - 1,
            type(uint48).max - 1,
            address(type(uint160).max - 1),
            address(type(uint160).max - 1)
        );
        test_whenNumericLimitsVary(
            type(uint128).max,
            type(uint128).max,
            type(uint128).max,
            type(uint48).max,
            address(type(uint160).max),
            address(type(uint160).max)
        );
    }

    // Scenarios: BLAUTH-VALIDATE-P03.
    function test_whenOwnerUsesIntrinsicAuthority() public view {
        assertEq(
            _auth.validate(_account, _account, 1, address(0), address(0), bytes32(0)),
            type(uint128).max,
            "Owner bypasses delegated maximum"
        );
        assertEq(
            _auth.validate(_account, _account, 4, address(0), address(0), bytes32(0)),
            0,
            "Owner bypasses delegated minimum"
        );
    }

    // Scenarios: BLAUTH-VALIDATE-L01.
    function test_givenDisabledCore_whenOwnerChecks_reverts() public {
        _core.setEnabled(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            )
        );
        _auth.captureAuthorization(_account, _account, 1);
    }

    function _check(
        uint8 action_,
        address asset_,
        address recipient_
    ) private view returns (uint128) {
        return
            _auth.validate(
                _account,
                _operator,
                action_,
                asset_,
                recipient_,
                _auth.captureAuthorization(_account, _operator, action_)
            );
    }
}
// forge-lint: disable-end(unused-return)
