// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansAuth} from "src/policies/interfaces/burnerloans/IBurnerLoansAuth.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansAuth} from "src/policies/burnerloans/BurnerLoansAuth.sol";
import {BurnerLoansAuthTest} from "src/test/policies/BurnerLoansAuth/BurnerLoansAuthTest.sol";
import {AuthKernelMock} from "src/test/policies/BurnerLoansAuth/fixtures/AuthKernelMock.sol";

contract BurnerLoansAuthApproveGrantTest is BurnerLoansAuthTest {
    // Scenarios: BLAUTH-APPROVE-D02.
    function test_givenTrustedKernelInactive_whenForeignKernelReportsActive_reverts() public {
        test_givenForeignKernelReportsActive_whenGrantCreated_reverts(false, true);
    }

    // Scenarios: BLAUTH-APPROVE-D03.
    function test_whenCoreReadinessMetadataReverts_reverts(bool kernel_) public {
        IOperatorAuth.Grant memory grant = _grant(15, true);
        vm.mockCallRevert(
            address(_core),
            kernel_ ? abi.encodeWithSignature("kernel()") : abi.encodeWithSignature("isEnabled()"),
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidContext.selector)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_core)
            )
        );
        _approve(grant);
        assertEq(
            _auth.pairEpochs(_account, _operator),
            0,
            "Unreadable metadata consumes no grant epoch"
        );
    }

    // Scenarios: BLAUTH-APPROVE-D02.
    function test_givenForeignKernelReportsActive_whenGrantCreated_reverts(
        bool active_,
        bool enabled_
    ) public {
        IOperatorAuth.Grant memory grant = _grant(15, true);
        AuthKernelMock foreignKernel = new AuthKernelMock();
        _kernel.setActive(active_);
        _core.setEnabled(enabled_);
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
        _approve(grant);
        assertEq(_auth.pairEpochs(_account, _operator), 0, "Wrong Kernel consumes no grant epoch");
        assertEq(_auth.accountEpochs(_account), 0, "Wrong Kernel preserves account epoch");
    }

    // Scenarios: BLAUTH-APPROVE-I01.
    function test_whenPermissionLengthIsNotCanonical_reverts(uint16 length_) public {
        vm.assume(length_ != 320);
        IOperatorAuth.Grant memory grant = _grant(1, true);
        grant.permissions = new bytes(length_);
        vm.expectRevert(IBurnerLoansAuth.BurnerLoansAuth_InvalidPermissions.selector);
        _approve(grant);
    }

    // Scenarios: BLAUTH-APPROVE-I01.
    function test_whenPermissionLengthBoundarySeeds_reverts() public {
        test_whenPermissionLengthIsNotCanonical_reverts(0);
        test_whenPermissionLengthIsNotCanonical_reverts(1);
        test_whenPermissionLengthIsNotCanonical_reverts(319);
        test_whenPermissionLengthIsNotCanonical_reverts(321);
        test_whenPermissionLengthIsNotCanonical_reverts(type(uint16).max);
    }

    // Scenarios: BLAUTH-APPROVE-I02.
    function test_whenSelectedAssetIsZero_reverts(uint8 action_) public {
        uint256 index = bound(action_, 0, 3);
        IOperatorAuth.Grant memory grant = _grant(uint8(1) << index, true);
        uint256[10] memory words = abi.decode(grant.permissions, (uint256[10]));
        uint256[4] memory assetWords = [uint256(0), 2, 5, 8];
        words[assetWords[index]] = 0;
        grant.permissions = abi.encode(words);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansAuth.BurnerLoansAuth_InvalidAsset.selector,
                address(0)
            )
        );
        _approve(grant);
        assertEq(_auth.pairEpochs(_account, _operator), 0, "Zero asset consumes no pair epoch");
        assertEq(_auth.accountEpochs(_account), 0, "Zero asset preserves account epoch");
    }

    // Scenarios: BLAUTH-APPROVE-I02.
    function test_whenSelectedAssetZeroActionSeeds_reverts() public {
        test_whenSelectedAssetIsZero_reverts(0);
        test_whenSelectedAssetIsZero_reverts(1);
        test_whenSelectedAssetIsZero_reverts(2);
        test_whenSelectedAssetIsZero_reverts(3);
    }

    // Scenarios: BLAUTH-APPROVE-I03.
    function test_whenSelectedAssetIsUnconfigured_reverts() public {
        IOperatorAuth.Grant memory grant = _grant(2, true);
        _core.setAsset(_asset, false);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansAuth.BurnerLoansAuth_InvalidAsset.selector, _asset)
        );
        _approve(grant);
    }

    // Scenarios: BLAUTH-APPROVE-I04.
    function test_whenNarrowIntegerHasDirtyPadding_reverts() public {
        IOperatorAuth.Grant memory grant = _grant(1, true);
        bytes memory data = grant.permissions;
        // maxCollateral occupies ABI word 1; bit 128 is outside uint128.
        assembly ("memory-safe") {
            mstore(add(data, 64), shl(128, 1))
        }
        vm.expectRevert(IBurnerLoansAuth.BurnerLoansAuth_InvalidPermissions.selector);
        _approve(grant);
    }

    // Scenarios: BLAUTH-APPROVE-I05.
    // These calls enumerate bounded test actors/assets, including fixture helpers called by the loops.
    // Yul shl(shift, value) sets the first out-of-width bit to deliberately corrupt ABI padding.
    // forge-lint: disable-start(calls-loop, incorrect-shift)
    function test_whenAnyRecordHasDirtyPadding_reverts(uint8 word_) public {
        uint256 word = bound(word_, 0, 9);
        uint256 width = word == 1 || word == 4 || word == 7 ? 128 : word == 9 ? 48 : 160;
        IOperatorAuth.Grant memory grant = _grant(1, true);
        bytes memory data = grant.permissions;
        assembly ("memory-safe") {
            mstore(add(add(data, 32), mul(word, 32)), shl(width, 1))
        }
        vm.expectRevert(IBurnerLoansAuth.BurnerLoansAuth_InvalidPermissions.selector);
        _approve(grant);
    }

    // forge-lint: disable-end(calls-loop, incorrect-shift)

    // Scenarios: BLAUTH-APPROVE-I05.
    function test_whenEveryPaddingBoundarySeed_reverts() public {
        for (uint8 word; word < 10; ++word) test_whenAnyRecordHasDirtyPadding_reverts(word);
    }

    // Scenarios: BLAUTH-APPROVE-I06.
    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
    function test_whenEachSelectedAssetIsUnconfigured_reverts(uint8 action_) public {
        IOperatorAuth.Grant memory grant = _grant(uint8(1 << bound(action_, 0, 3)), true);
        _core.setAsset(_asset, false);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansAuth.BurnerLoansAuth_InvalidAsset.selector, _asset)
        );
        _approve(grant);
    }

    // forge-lint: disable-end(unsafe-typecast)

    // Scenarios: BLAUTH-APPROVE-L01.
    function test_givenDisabledCore_whenGrantCreated_reverts() public {
        IOperatorAuth.Grant memory grant = _grant(15, true);
        _core.setEnabled(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            )
        );
        _approve(grant);
    }

    // Scenarios: BLAUTH-APPROVE-L02.
    function test_givenInactiveCore_whenGrantCreated_reverts() public {
        IOperatorAuth.Grant memory grant = _grant(15, true);
        _kernel.setActive(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            )
        );
        _approve(grant);
    }

    // Scenarios: BLAUTH-APPROVE-D01.
    function test_givenRetiredAuth_whenGrantCreated_reverts() public {
        _core.select(address(new BurnerLoansAuth(address(_kernel), address(_core))));
        IOperatorAuth.Grant memory grant = _grant(15, true);
        vm.expectRevert(IBurnerLoansAuth.BurnerLoansAuth_NotSelected.selector);
        _approve(grant);
    }

    // Scenarios: BLAUTH-APPROVE-P01.
    function test_whenUnselectedRecordsContainZeroAssets() public {
        IOperatorAuth.Grant memory grant = _grant(1, true);
        IBurnerLoansAuth.Permissions memory p;
        p.depositAsset = _asset;
        p.maxCollateral = type(uint128).max;
        grant.permissions = abi.encode(p);
        _approve(grant);
        assertEq(
            _auth.pairEpochs(_account, _operator),
            1,
            "Acceptance consumes exactly one pair epoch"
        );
        assertEq(
            _auth.getGrant(_account, _operator).permissions,
            grant.permissions,
            "Canonical records are retained exactly"
        );
    }

    // Scenarios: BLAUTH-APPROVE-P02.
    function test_givenCoreReenabled_whenGrantCreated() public {
        _core.setEnabled(false);
        _core.setEnabled(true);
        _approve(_grant(15, true));
        assertEq(_auth.pairEpochs(_account, _operator), 1, "Reenabled Core permits acceptance");
    }
}
