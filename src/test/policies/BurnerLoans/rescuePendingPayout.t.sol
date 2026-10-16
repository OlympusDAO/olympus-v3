// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansRescue} from "src/policies/interfaces/IBurnerLoansRescue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ReentrancyGuard} from "@openzeppelin-5.3.0/utils/ReentrancyGuard.sol";
import {Actions} from "src/Kernel.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {ReentrantPayoutToken} from "src/test/mocks/ReentrantPayoutToken.sol";
import {BurnerLoansRescuePendingTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansRescuePendingTest.sol";

// forge-lint: disable-start(literal-instead-of-constant,calls-loop,unused-return,unsafe-typecast)

/// @dev Scenario IDs map to rescuePendingPayout.md. Ordinary fixtures use exact 10/20/30
/// reward/fee/seizure debts. Tests choose recipient, lifecycle and amount explicitly; each
/// allocation test supplies its own expected payments instead of a shared debit algorithm.
/// @dev bucketMask_ chooses globally populated debt buckets: reward bit = 1, fee bit = 2,
///      seizure bit = 4. Combine with OR: 0 = empty, 3 = reward + fee, 7 = all. This selects
///      presence, not recipient eligibility; layout_ sets owners and recipient_ selects one.
/// @dev Unless the test varies policy membership explicitly, the policy remains active.
///      disabled_ varies only the facility's local enabled/disabled state.
contract BurnerLoansRescuePendingPayoutTest is BurnerLoansRescuePendingTestBase {
    address internal constant _NO_CODE_TOKEN = address(0xC0DE);

    enum Recipient {
        Keeper,
        FeeRecipient,
        Treasury,
        Unrelated
    }
    enum ForbiddenDestination {
        Facility,
        Token,
        Configurator,
        Kernel
    }
    enum NestedAction {
        RescueSurplus,
        RescuePendingPayout,
        SetPriceCacheMaxAge,
        RetryPendingPayout
    }

    /// @dev	Resolve the selected role to its address; Unrelated is nonzero and owns no debt.
    function _selectRescueRecipient(
        Ledger memory l,
        Recipient role_
    ) internal pure returns (address) {
        if (role_ == Recipient.Keeper) return l.keepers[0];
        if (role_ == Recipient.FeeRecipient) return l.feeRecipient;
        if (role_ == Recipient.Treasury) return l.treasury;
        return address(0xBEEF);
    }

    /// @dev	Use fixed role addresses (with the chosen overlaps), then record bucketMask_: reward
    ///      uses 10, fee 20, seizure 30 base units. Unselected buckets are zero.
    function _createFixedPendingPayoutLedger(
        RoleLayout layout_,
        uint8 bucketMask_
    ) internal returns (Ledger memory) {
        return
            _createPendingPayoutLedger(
                _configurePayoutRoles(layout_),
                bucketMask_ & _REWARD_BUCKET != 0 ? _REWARD : 0,
                bucketMask_ & _FEE_BUCKET != 0 ? _FEE : 0,
                bucketMask_ & _SEIZURE_BUCKET != 0 ? _SEIZURE : 0
            );
    }

    /// @dev Resolve one explicitly forbidden destination; keep this choice separate from amount.
    function _selectForbiddenDestination(
        Ledger memory l,
        ForbiddenDestination destination_
    ) internal view returns (address) {
        if (destination_ == ForbiddenDestination.Facility) return address(burnerLoans);
        if (destination_ == ForbiddenDestination.Token) return address(l.token);
        if (destination_ == ForbiddenDestination.Configurator) return address(burnerLoansConfig);
        return address(kernel);
    }

    // Invalid input tests vary role identities/presence without fuzzing debt quantities.
    // Each deterministic test fixes its role layout and input error; its helper seeds compatible state and amount boundaries.

    // Scenarios: I-01.
    // Fuzz layout, bucket presence, selected role and enabled/disabled state; vary amount across 0..MAX.
    function test_invalidInputs_whenTokenIsZero_reverts(
        RoleLayout layout_,
        uint8 bucketMask_,
        Recipient recipient_,
        uint256 amount_,
        bool disabled_
    ) public {
        Ledger memory l = _createFixedPendingPayoutLedger(
            layout_,
            uint8(bound(bucketMask_, 0, _ALL_BUCKETS))
        );
        _disableFacilityIf(disabled_);
        Request memory request = _createRescueRequest(
            l,
            _selectRescueRecipient(l, recipient_),
            alice,
            amount_
        );
        request.token = address(0);
        _assertPendingRescueInputError(l, request, _invalidAssetError(address(0)));
    }

    // Scenarios: I-01.
    // Fuzz layout, bucket presence, selected role and enabled/disabled state; vary amount across 0..MAX.
    function test_invalidInputs_whenTokenHasNoCode_reverts(
        RoleLayout layout_,
        uint8 bucketMask_,
        Recipient recipient_,
        uint256 amount_,
        bool disabled_
    ) public {
        Ledger memory l = _createFixedPendingPayoutLedger(
            layout_,
            uint8(bound(bucketMask_, 0, _ALL_BUCKETS))
        );
        _disableFacilityIf(disabled_);
        Request memory request = _createRescueRequest(
            l,
            _selectRescueRecipient(l, recipient_),
            alice,
            amount_
        );
        request.token = _NO_CODE_TOKEN;
        assertEq(_NO_CODE_TOKEN.code.length, 0, "invalid token has no code");
        _assertPendingRescueInputError(l, request, _invalidAssetError(_NO_CODE_TOKEN));
    }

    // Scenarios: I-02.
    // Fuzz layout, bucket presence and enabled/disabled state; recipient is zero, amount varies across 0..MAX.
    function test_invalidInputs_whenRecipientIsZero_reverts(
        RoleLayout layout_,
        uint8 bucketMask_,
        uint256 amount_,
        bool disabled_
    ) public {
        Ledger memory l = _createFixedPendingPayoutLedger(
            layout_,
            uint8(bound(bucketMask_, 0, _ALL_BUCKETS))
        );
        _disableFacilityIf(disabled_);
        Request memory request = _createRescueRequest(l, address(0), alice, amount_);

        _assertPendingRescueInputError(l, request, _zeroAddressError());
    }

    // Scenarios: I-03.
    // Fuzz layout, bucket presence, selected role and enabled/disabled state; vary amount across 0..MAX.
    function test_invalidInputs_whenDestinationIsZero_reverts(
        RoleLayout layout_,
        uint8 bucketMask_,
        Recipient recipient_,
        uint256 amount_,
        bool disabled_
    ) public {
        Ledger memory l = _createFixedPendingPayoutLedger(
            layout_,
            uint8(bound(bucketMask_, 0, _ALL_BUCKETS))
        );
        _disableFacilityIf(disabled_);
        Request memory request = _createRescueRequest(
            l,
            _selectRescueRecipient(l, recipient_),
            alice,
            amount_
        );
        request.destination = address(0);
        _assertPendingRescueInputError(
            l,
            request,
            abi.encodeWithSelector(
                IBurnerLoansRescue.BurnerLoans_InvalidRescueDestination.selector,
                address(0)
            )
        );
    }

    // Scenarios: I-04.
    // Fuzz layout, bucket presence, selected role and enabled/disabled state; select one of the four forbidden destinations.
    function test_invalidInputs_whenDestinationIsForbidden_reverts(
        RoleLayout layout_,
        uint8 bucketMask_,
        Recipient recipient_,
        uint256 amount_,
        ForbiddenDestination destination_,
        bool disabled_
    ) public {
        Ledger memory l = _createFixedPendingPayoutLedger(
            layout_,
            uint8(bound(bucketMask_, 0, _ALL_BUCKETS))
        );
        _disableFacilityIf(disabled_);
        Request memory request = _createRescueRequest(
            l,
            _selectRescueRecipient(l, recipient_),
            _selectForbiddenDestination(l, destination_),
            amount_
        );

        _assertPendingRescueInputError(
            l,
            request,
            abi.encodeWithSelector(
                IBurnerLoansRescue.BurnerLoans_InvalidRescueDestination.selector,
                request.destination
            )
        );
    }

    // Scenarios: I-05.
    // Fuzz layout, bucket presence, selected role and enabled/disabled state; fix amount at zero.
    function test_invalidInputs_whenAmountIsZero_reverts(
        RoleLayout layout_,
        uint8 bucketMask_,
        Recipient recipient_,
        bool disabled_
    ) public {
        Ledger memory l = _createFixedPendingPayoutLedger(
            layout_,
            uint8(bound(bucketMask_, 0, _ALL_BUCKETS))
        );
        _disableFacilityIf(disabled_);
        Request memory request = _createRescueRequest(
            l,
            _selectRescueRecipient(l, recipient_),
            alice,
            0
        );

        _assertPendingRescueInputError(l, request, _zeroAmountError());
    }

    // Scenarios: I-06.
    // Fuzz layout, bucket presence, selected role and enabled/disabled state; bound amount to E+1..MAX.
    function test_invalidInputs_whenAmountExceedsEntitlement_reverts(
        RoleLayout layout_,
        uint8 bucketMask_,
        Recipient recipient_,
        uint256 amount_,
        bool disabled_
    ) public {
        Ledger memory l = _createFixedPendingPayoutLedger(
            layout_,
            uint8(bound(bucketMask_, 0, _ALL_BUCKETS))
        );
        _disableFacilityIf(disabled_);
        Request memory request = _createRescueRequest(
            l,
            _selectRescueRecipient(l, recipient_),
            alice,
            amount_
        );
        uint256 entitlement = _expectedRecipientPayout(l, request.recipient);
        request.amount = bound(amount_, entitlement + 1, _MAX);
        _assertPendingRescueInputError(
            l,
            request,
            _insufficientPayoutError(request.token, request.amount, entitlement)
        );
    }

    /// @dev The test supplies the complete invalid request and exact error. This helper only checks preview, execution and rollback.
    function _assertPendingRescueInputError(
        Ledger memory l,
        Request memory request_,
        bytes memory failure_
    ) internal {
        _assertRescueReverts(l, request_, address(burnerLoansConfig), failure_, failure_);
    }

    function _invalidAssetError(address token_) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IBurnerLoansRescue.BurnerLoans_InvalidAsset.selector, token_);
    }

    function _zeroAddressError() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
    }

    function _zeroAmountError() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IBurnerLoans.BurnerLoans_ZeroAmount.selector);
    }

    // Scenarios: I-01.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenDistinct_whenTokenIsZero_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkTokenIsZeroBoundaries(RoleLayout.Distinct);
    }

    // Scenarios: I-01.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenDistinct_whenTokenHasNoCode_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkTokenHasNoCodeBoundaries(RoleLayout.Distinct);
    }

    // Scenarios: I-02.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenDistinct_whenRecipientIsZero_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkRecipientIsZeroBoundaries(RoleLayout.Distinct);
    }

    // Scenarios: I-03.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenDistinct_whenDestinationIsZero_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkDestinationIsZeroBoundaries(RoleLayout.Distinct);
    }

    // Scenarios: I-04.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenDistinct_whenDestinationIsForbidden_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkDestinationIsForbiddenBoundaries(RoleLayout.Distinct);
    }

    // Scenarios: I-05.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenDistinct_whenAmountIsZero_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkAmountIsZeroBoundaries(RoleLayout.Distinct);
    }

    // Scenarios: I-06.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenDistinct_whenAmountExceedsEntitlement_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkAmountExceedsEntitlementBoundaries(RoleLayout.Distinct);
    }

    // Scenarios: I-01.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenKeeperIsFeeRecipient_whenTokenIsZero_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkTokenIsZeroBoundaries(RoleLayout.KeeperIsFeeRecipient);
    }

    // Scenarios: I-01.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenKeeperIsFeeRecipient_whenTokenHasNoCode_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkTokenHasNoCodeBoundaries(RoleLayout.KeeperIsFeeRecipient);
    }

    // Scenarios: I-02.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenKeeperIsFeeRecipient_whenRecipientIsZero_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkRecipientIsZeroBoundaries(RoleLayout.KeeperIsFeeRecipient);
    }

    // Scenarios: I-03.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenKeeperIsFeeRecipient_whenDestinationIsZero_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkDestinationIsZeroBoundaries(RoleLayout.KeeperIsFeeRecipient);
    }

    // Scenarios: I-04.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenKeeperIsFeeRecipient_whenDestinationIsForbidden_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkDestinationIsForbiddenBoundaries(RoleLayout.KeeperIsFeeRecipient);
    }

    // Scenarios: I-05.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenKeeperIsFeeRecipient_whenAmountIsZero_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkAmountIsZeroBoundaries(RoleLayout.KeeperIsFeeRecipient);
    }

    // Scenarios: I-06.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenKeeperIsFeeRecipient_whenAmountExceedsEntitlement_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkAmountExceedsEntitlementBoundaries(RoleLayout.KeeperIsFeeRecipient);
    }

    // Scenarios: I-01.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenKeeperIsTreasury_whenTokenIsZero_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkTokenIsZeroBoundaries(RoleLayout.KeeperIsTreasury);
    }

    // Scenarios: I-01.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenKeeperIsTreasury_whenTokenHasNoCode_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkTokenHasNoCodeBoundaries(RoleLayout.KeeperIsTreasury);
    }

    // Scenarios: I-02.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenKeeperIsTreasury_whenRecipientIsZero_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkRecipientIsZeroBoundaries(RoleLayout.KeeperIsTreasury);
    }

    // Scenarios: I-03.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenKeeperIsTreasury_whenDestinationIsZero_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkDestinationIsZeroBoundaries(RoleLayout.KeeperIsTreasury);
    }

    // Scenarios: I-04.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenKeeperIsTreasury_whenDestinationIsForbidden_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkDestinationIsForbiddenBoundaries(RoleLayout.KeeperIsTreasury);
    }

    // Scenarios: I-05.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenKeeperIsTreasury_whenAmountIsZero_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkAmountIsZeroBoundaries(RoleLayout.KeeperIsTreasury);
    }

    // Scenarios: I-06.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenKeeperIsTreasury_whenAmountExceedsEntitlement_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkAmountExceedsEntitlementBoundaries(RoleLayout.KeeperIsTreasury);
    }

    // Scenarios: I-01.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenFeeRecipientIsTreasury_whenTokenIsZero_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkTokenIsZeroBoundaries(RoleLayout.FeeRecipientIsTreasury);
    }

    // Scenarios: I-01.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenFeeRecipientIsTreasury_whenTokenHasNoCode_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkTokenHasNoCodeBoundaries(RoleLayout.FeeRecipientIsTreasury);
    }

    // Scenarios: I-02.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenFeeRecipientIsTreasury_whenRecipientIsZero_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkRecipientIsZeroBoundaries(RoleLayout.FeeRecipientIsTreasury);
    }

    // Scenarios: I-03.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenFeeRecipientIsTreasury_whenDestinationIsZero_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkDestinationIsZeroBoundaries(RoleLayout.FeeRecipientIsTreasury);
    }

    // Scenarios: I-04.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenFeeRecipientIsTreasury_whenDestinationIsForbidden_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkDestinationIsForbiddenBoundaries(RoleLayout.FeeRecipientIsTreasury);
    }

    // Scenarios: I-05.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenFeeRecipientIsTreasury_whenAmountIsZero_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkAmountIsZeroBoundaries(RoleLayout.FeeRecipientIsTreasury);
    }

    // Scenarios: I-06.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenFeeRecipientIsTreasury_whenAmountExceedsEntitlement_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkAmountExceedsEntitlementBoundaries(RoleLayout.FeeRecipientIsTreasury);
    }

    // Scenarios: I-01.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenAllRolesOverlap_whenTokenIsZero_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkTokenIsZeroBoundaries(RoleLayout.AllRolesOverlap);
    }

    // Scenarios: I-01.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenAllRolesOverlap_whenTokenHasNoCode_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkTokenHasNoCodeBoundaries(RoleLayout.AllRolesOverlap);
    }

    // Scenarios: I-02.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenAllRolesOverlap_whenRecipientIsZero_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkRecipientIsZeroBoundaries(RoleLayout.AllRolesOverlap);
    }

    // Scenarios: I-03.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenAllRolesOverlap_whenDestinationIsZero_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkDestinationIsZeroBoundaries(RoleLayout.AllRolesOverlap);
    }

    // Scenarios: I-04.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenAllRolesOverlap_whenDestinationIsForbidden_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkDestinationIsForbiddenBoundaries(RoleLayout.AllRolesOverlap);
    }

    // Scenarios: I-05.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenAllRolesOverlap_whenAmountIsZero_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkAmountIsZeroBoundaries(RoleLayout.AllRolesOverlap);
    }

    // Scenarios: I-06.
    // Fixed role layout and one input error; seed bucket subsets, recipients, local states and amount boundaries.
    function test_invalidInputs_givenAllRolesOverlap_whenAmountExceedsEntitlement_whenDomainBoundariesAreSeeded_reverts()
        public
    {
        _checkAmountExceedsEntitlementBoundaries(RoleLayout.AllRolesOverlap);
    }

    /// @dev Check only TokenIsZero in the supplied fixed layout; preview, execution and rollback share the explicit expected error.
    function _checkTokenIsZeroBoundaries(RoleLayout layout_) internal {
        uint256 rootSnapshot = vm.snapshotState();
        uint256[3] memory amounts = [uint256(0), 1, _MAX];
        for (uint8 bucketMask; bucketMask <= _ALL_BUCKETS; ++bucketMask) {
            Ledger memory l = _createFixedPendingPayoutLedger(layout_, bucketMask);
            uint256 fixtureSnapshot = vm.snapshotState();
            for (uint256 disabled; disabled < 2; ++disabled) {
                _disableFacilityIf(disabled != 0);
                for (uint8 role; role <= uint8(Recipient.Unrelated); ++role) {
                    for (uint256 a; a < amounts.length; ++a) {
                        Request memory request = _createRescueRequest(
                            l,
                            _selectRescueRecipient(l, Recipient(role)),
                            alice,
                            amounts[a]
                        );
                        request.token = address(0);
                        _assertPendingRescueInputError(l, request, _invalidAssetError(address(0)));
                    }
                }
                _restoreSnapshot(fixtureSnapshot);
            }
            _restoreSnapshot(rootSnapshot);
        }
    }

    /// @dev Check only TokenHasNoCode in the supplied fixed layout; preview, execution and rollback share the explicit expected error.
    function _checkTokenHasNoCodeBoundaries(RoleLayout layout_) internal {
        uint256 rootSnapshot = vm.snapshotState();
        uint256[3] memory amounts = [uint256(0), 1, _MAX];
        for (uint8 bucketMask; bucketMask <= _ALL_BUCKETS; ++bucketMask) {
            Ledger memory l = _createFixedPendingPayoutLedger(layout_, bucketMask);
            uint256 fixtureSnapshot = vm.snapshotState();
            for (uint256 disabled; disabled < 2; ++disabled) {
                _disableFacilityIf(disabled != 0);
                for (uint8 role; role <= uint8(Recipient.Unrelated); ++role) {
                    for (uint256 a; a < amounts.length; ++a) {
                        Request memory request = _createRescueRequest(
                            l,
                            _selectRescueRecipient(l, Recipient(role)),
                            alice,
                            amounts[a]
                        );
                        request.token = _NO_CODE_TOKEN;
                        assertEq(_NO_CODE_TOKEN.code.length, 0, "invalid token has no code");
                        _assertPendingRescueInputError(
                            l,
                            request,
                            _invalidAssetError(_NO_CODE_TOKEN)
                        );
                    }
                }
                _restoreSnapshot(fixtureSnapshot);
            }
            _restoreSnapshot(rootSnapshot);
        }
    }

    /// @dev Check only RecipientIsZero in the supplied fixed layout; preview, execution and rollback share the explicit expected error.
    function _checkRecipientIsZeroBoundaries(RoleLayout layout_) internal {
        uint256 rootSnapshot = vm.snapshotState();
        uint256[3] memory amounts = [uint256(0), 1, _MAX];
        for (uint8 bucketMask; bucketMask <= _ALL_BUCKETS; ++bucketMask) {
            Ledger memory l = _createFixedPendingPayoutLedger(layout_, bucketMask);
            uint256 fixtureSnapshot = vm.snapshotState();
            for (uint256 disabled; disabled < 2; ++disabled) {
                _disableFacilityIf(disabled != 0);
                for (uint256 a; a < amounts.length; ++a) {
                    Request memory request = _createRescueRequest(l, address(0), alice, amounts[a]);

                    _assertPendingRescueInputError(l, request, _zeroAddressError());
                }
                _restoreSnapshot(fixtureSnapshot);
            }
            _restoreSnapshot(rootSnapshot);
        }
    }

    /// @dev Check only DestinationIsZero in the supplied fixed layout; preview, execution and rollback share the explicit expected error.
    function _checkDestinationIsZeroBoundaries(RoleLayout layout_) internal {
        uint256 rootSnapshot = vm.snapshotState();
        uint256[3] memory amounts = [uint256(0), 1, _MAX];
        for (uint8 bucketMask; bucketMask <= _ALL_BUCKETS; ++bucketMask) {
            Ledger memory l = _createFixedPendingPayoutLedger(layout_, bucketMask);
            uint256 fixtureSnapshot = vm.snapshotState();
            for (uint256 disabled; disabled < 2; ++disabled) {
                _disableFacilityIf(disabled != 0);
                for (uint8 role; role <= uint8(Recipient.Unrelated); ++role) {
                    for (uint256 a; a < amounts.length; ++a) {
                        Request memory request = _createRescueRequest(
                            l,
                            _selectRescueRecipient(l, Recipient(role)),
                            alice,
                            amounts[a]
                        );
                        request.destination = address(0);
                        _assertPendingRescueInputError(
                            l,
                            request,
                            abi.encodeWithSelector(
                                IBurnerLoansRescue.BurnerLoans_InvalidRescueDestination.selector,
                                address(0)
                            )
                        );
                    }
                }
                _restoreSnapshot(fixtureSnapshot);
            }
            _restoreSnapshot(rootSnapshot);
        }
    }

    /// @dev Check only DestinationIsForbidden in the supplied fixed layout; preview, execution and rollback share the explicit expected error.
    function _checkDestinationIsForbiddenBoundaries(RoleLayout layout_) internal {
        uint256 rootSnapshot = vm.snapshotState();
        uint256[3] memory amounts = [uint256(0), 1, _MAX];
        for (uint8 bucketMask; bucketMask <= _ALL_BUCKETS; ++bucketMask) {
            Ledger memory l = _createFixedPendingPayoutLedger(layout_, bucketMask);
            uint256 fixtureSnapshot = vm.snapshotState();
            for (uint256 disabled; disabled < 2; ++disabled) {
                _disableFacilityIf(disabled != 0);
                for (uint8 role; role <= uint8(Recipient.Unrelated); ++role) {
                    for (
                        uint8 forbidden;
                        forbidden <= uint8(ForbiddenDestination.Kernel);
                        ++forbidden
                    ) {
                        for (uint256 a; a < amounts.length; ++a) {
                            Request memory request = _createRescueRequest(
                                l,
                                _selectRescueRecipient(l, Recipient(role)),
                                _selectForbiddenDestination(l, ForbiddenDestination(forbidden)),
                                amounts[a]
                            );

                            _assertPendingRescueInputError(
                                l,
                                request,
                                abi.encodeWithSelector(
                                    IBurnerLoansRescue
                                        .BurnerLoans_InvalidRescueDestination
                                        .selector,
                                    request.destination
                                )
                            );
                        }
                    }
                }
                _restoreSnapshot(fixtureSnapshot);
            }
            _restoreSnapshot(rootSnapshot);
        }
    }

    /// @dev Check only AmountIsZero in the supplied fixed layout; preview, execution and rollback share the explicit expected error.
    function _checkAmountIsZeroBoundaries(RoleLayout layout_) internal {
        uint256 rootSnapshot = vm.snapshotState();
        for (uint8 bucketMask; bucketMask <= _ALL_BUCKETS; ++bucketMask) {
            Ledger memory l = _createFixedPendingPayoutLedger(layout_, bucketMask);
            uint256 fixtureSnapshot = vm.snapshotState();
            for (uint256 disabled; disabled < 2; ++disabled) {
                _disableFacilityIf(disabled != 0);
                for (uint8 role; role <= uint8(Recipient.Unrelated); ++role) {
                    Request memory request = _createRescueRequest(
                        l,
                        _selectRescueRecipient(l, Recipient(role)),
                        alice,
                        0
                    );

                    _assertPendingRescueInputError(l, request, _zeroAmountError());
                }
                _restoreSnapshot(fixtureSnapshot);
            }
            _restoreSnapshot(rootSnapshot);
        }
    }

    /// @dev Check only AmountExceedsEntitlement in the supplied fixed layout; preview, execution and rollback share the explicit expected error.
    function _checkAmountExceedsEntitlementBoundaries(RoleLayout layout_) internal {
        uint256 rootSnapshot = vm.snapshotState();
        for (uint8 bucketMask; bucketMask <= _ALL_BUCKETS; ++bucketMask) {
            Ledger memory l = _createFixedPendingPayoutLedger(layout_, bucketMask);
            uint256 fixtureSnapshot = vm.snapshotState();
            for (uint256 disabled; disabled < 2; ++disabled) {
                _disableFacilityIf(disabled != 0);
                for (uint8 role; role <= uint8(Recipient.Unrelated); ++role) {
                    address recipient = _selectRescueRecipient(l, Recipient(role));
                    uint256 entitlement = _expectedRecipientPayout(l, recipient);
                    uint256[3] memory amounts = [entitlement + 1, entitlement + 2, _MAX];
                    for (uint256 a; a < amounts.length; ++a) {
                        Request memory request = _createRescueRequest(
                            l,
                            recipient,
                            alice,
                            amounts[a]
                        );
                        _assertPendingRescueInputError(
                            l,
                            request,
                            _insufficientPayoutError(address(l.token), amounts[a], entitlement)
                        );
                    }
                }
                _restoreSnapshot(fixtureSnapshot);
            }
            _restoreSnapshot(rootSnapshot);
        }
    }

    // Scenarios: I-01, I-02, I-03, I-04, I-05.
    // With all roles shared and 60 owed, combine invalid addresses and zero amount; check the first failing validation.
    function test_invalidInputs_whenFaultsCompete_reverts() public {
        Ledger memory l = _createFixedPendingPayoutLedger(RoleLayout.AllRolesOverlap, _ALL_BUCKETS);
        Request memory request = _createRescueRequest(l, address(0), address(burnerLoans), 0);
        bytes memory forbidden = abi.encodeWithSelector(
            IBurnerLoansRescue.BurnerLoans_InvalidRescueDestination.selector,
            address(burnerLoans)
        );
        _assertRescueReverts(l, request, address(burnerLoansConfig), forbidden, forbidden);
        request.token = address(0);
        _assertRescueReverts(
            l,
            request,
            address(burnerLoansConfig),
            _invalidAssetError(request.token),
            _invalidAssetError(request.token)
        );
        request.token = _NO_CODE_TOKEN;
        _assertRescueReverts(
            l,
            request,
            address(burnerLoansConfig),
            _invalidAssetError(request.token),
            _invalidAssetError(request.token)
        );
        request.token = address(l.token);
        request.destination = address(0);
        bytes memory zeroDestination = abi.encodeWithSelector(
            IBurnerLoansRescue.BurnerLoans_InvalidRescueDestination.selector,
            address(0)
        );
        _assertRescueReverts(
            l,
            request,
            address(burnerLoansConfig),
            zeroDestination,
            zeroDestination
        );
        request.destination = alice;
        _assertRescueReverts(
            l,
            request,
            address(burnerLoansConfig),
            _zeroAddressError(),
            _zeroAddressError()
        );
        request.recipient = l.keepers[0];
        _assertRescueReverts(
            l,
            request,
            address(burnerLoansConfig),
            _zeroAmountError(),
            _zeroAmountError()
        );
    }

    // Authorization and policy gates use one readable valid fixture. Each L-row crosses
    // valid inputs with all single faults and simultaneous faults; role allocation is separate.

    /// @notice Direct admin rescue uses the same input checks in every BL local/membership state.
    // Scenarios: L-21, L-22.
    function test_authorization_givenActiveFacility_whenAdminCallsDirectly() public {
        for (uint256 disabled; disabled < 2; ++disabled) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _createFixedPendingPayoutLedger(
                RoleLayout.AllRolesOverlap,
                _ALL_BUCKETS
            );
            _disableFacilityIf(disabled != 0);

            _assertRescueSucceedsAs(l, l.keepers[0], alice, 1, [uint256(1), 0, 0], admin);
            _restoreSnapshot(snapshot);
        }
    }

    // Scenarios: L-28, L-29.
    function test_authorization_givenActiveFacility_whenAdminCallsDirectly_whenInputsInvalid_reverts()
        public
    {
        for (uint256 disabled; disabled < 2; ++disabled) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _createFixedPendingPayoutLedger(
                RoleLayout.AllRolesOverlap,
                _ALL_BUCKETS
            );
            _disableFacilityIf(disabled != 0);

            _assertActiveInputFailures(l, admin);
            _restoreSnapshot(snapshot);
        }
    }

    // Scenarios: L-23, L-24.
    function test_authorization_givenInactiveFacility_whenAdminCallsDirectly_reverts() public {
        for (uint256 disabled; disabled < 2; ++disabled) {
            uint256 snapshot = vm.snapshotState();
            Ledger memory l = _createFixedPendingPayoutLedger(
                RoleLayout.AllRolesOverlap,
                _ALL_BUCKETS
            );
            _disableFacilityIf(disabled != 0);

            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoans));

            _assertInactiveRequests(
                l,
                admin,
                abi.encodeWithSelector(IBurnerLoans.BurnerLoans_PolicyInactive.selector)
            );
            _restoreSnapshot(snapshot);
        }
    }

    /// @notice Direct rescue authority follows the live admin role rather than a fixed governance address.
    // Scenarios: L-25.
    function test_authorization_givenAdminRoleGranted_whenNewAdminCalls() public {
        address newAdmin = makeAddr("new rescue admin");
        Ledger memory l = _createFixedPendingPayoutLedger(RoleLayout.AllRolesOverlap, _ALL_BUCKETS);
        vm.prank(admin);
        rolesAdmin.grantRole(ADMIN_ROLE, newAdmin);
        _assertRescueSucceedsAs(l, l.keepers[0], alice, 1, [uint256(1), 0, 0], newAdmin);
    }

    // Scenarios: L-30.
    function test_authorization_givenAdminRoleNotGranted_whenCallerRescues_reverts() public {
        address newAdmin = makeAddr("new rescue admin");
        Ledger memory l = _createFixedPendingPayoutLedger(RoleLayout.AllRolesOverlap, _ALL_BUCKETS);
        _assertRescueReverts(
            l,
            _createRescueRequest(l, l.keepers[0], alice, 1),
            newAdmin,
            "",
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: L-30.
    function test_authorization_givenAdminRoleRevoked_whenFormerAdminRescues_reverts() public {
        address formerAdmin = makeAddr("former rescue admin");
        Ledger memory l = _createFixedPendingPayoutLedger(RoleLayout.AllRolesOverlap, _ALL_BUCKETS);
        vm.startPrank(admin);
        rolesAdmin.grantRole(ADMIN_ROLE, formerAdmin);
        rolesAdmin.revokeRole(ADMIN_ROLE, formerAdmin);
        vm.stopPrank();
        _assertRescueReverts(
            l,
            _createRescueRequest(l, l.keepers[0], alice, 1),
            formerAdmin,
            "",
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    /// @notice Direct admin recovery bypasses disabled/inactive BLC and BLCT while BL remains active.
    // Scenarios: A-01.
    function test_givenConfigAndTimelockUnavailable_whenAdminRescuesDirectly() public {
        for (uint256 disabledBL; disabledBL < 2; ++disabledBL) {
            for (uint256 inactiveConfig; inactiveConfig < 2; ++inactiveConfig) {
                for (uint256 inactiveTimelock; inactiveTimelock < 2; ++inactiveTimelock) {
                    uint256 snapshot = vm.snapshotState();
                    Ledger memory l = _createFixedPendingPayoutLedger(
                        RoleLayout.Distinct,
                        _ALL_BUCKETS
                    );
                    vm.startPrank(admin);
                    burnerLoansConfig.disable("");
                    assertFalse(configTimelock.isEnabled(), "fixture timelock is already disabled");
                    if (inactiveConfig != 0)
                        kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoansConfig));
                    if (inactiveTimelock != 0)
                        kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
                    vm.stopPrank();
                    _disableFacilityIf(disabledBL != 0);
                    _assertRescueSucceedsAs(l, l.keepers[0], alice, 4, [uint256(4), 0, 0], admin);
                    assertFalse(
                        burnerLoansConfig.isEnabled() || configTimelock.isEnabled(),
                        "direct recovery does not re-enable upstream contracts"
                    );
                    assertEq(
                        configTimelock.nextActionId(),
                        1,
                        "direct recovery creates no queued action"
                    );
                    _restoreSnapshot(snapshot);
                }
            }
        }
    }

    // Scenarios: L-01.
    function test_authorization_givenEnabled_givenPolicyActive_whenCallerIsConfigurator() public {
        Ledger memory l = _createFixedPendingPayoutLedger(RoleLayout.AllRolesOverlap, _ALL_BUCKETS);

        _assertRescueSucceedsAs(
            l,
            l.keepers[0],
            alice,
            1,
            [uint256(1), 0, 0],
            address(burnerLoansConfig)
        );
    }

    // Scenarios: L-26.
    function test_authorization_givenEnabled_givenPolicyActive_whenCallerIsConfigurator_whenInputsInvalid_reverts()
        public
    {
        Ledger memory l = _createFixedPendingPayoutLedger(RoleLayout.AllRolesOverlap, _ALL_BUCKETS);

        _assertActiveInputFailures(l, address(burnerLoansConfig));
    }

    // Scenarios: L-02.
    // Fuzz callers outside the bound Configurator and admin; cross valid inputs, each fault and combined faults with the named lifecycle state.
    function test_authorization_givenEnabled_givenPolicyActive_whenCallerIsUnauthorized_reverts(
        address caller_
    ) public {
        vm.assume(caller_ != address(burnerLoansConfig) && caller_ != admin);
        Ledger memory l = _createFixedPendingPayoutLedger(RoleLayout.AllRolesOverlap, _ALL_BUCKETS);

        _assertUnauthorizedActiveRequests(l, caller_);
    }

    // Scenarios: L-07.
    function test_authorization_givenDisabled_givenPolicyActive_whenCallerIsConfigurator() public {
        Ledger memory l = _createFixedPendingPayoutLedger(RoleLayout.AllRolesOverlap, _ALL_BUCKETS);
        _disableFacilityIf(true);

        _assertRescueSucceedsAs(
            l,
            l.keepers[0],
            alice,
            1,
            [uint256(1), 0, 0],
            address(burnerLoansConfig)
        );
    }

    // Scenarios: L-27.
    function test_authorization_givenDisabled_givenPolicyActive_whenCallerIsConfigurator_whenInputsInvalid_reverts()
        public
    {
        Ledger memory l = _createFixedPendingPayoutLedger(RoleLayout.AllRolesOverlap, _ALL_BUCKETS);
        _disableFacilityIf(true);

        _assertActiveInputFailures(l, address(burnerLoansConfig));
    }

    // Scenarios: L-08.
    // Fuzz callers outside the bound Configurator and admin; cross valid inputs, each fault and combined faults with the named lifecycle state.
    function test_authorization_givenDisabled_givenPolicyActive_whenCallerIsUnauthorized_reverts(
        address caller_
    ) public {
        vm.assume(caller_ != address(burnerLoansConfig) && caller_ != admin);
        Ledger memory l = _createFixedPendingPayoutLedger(RoleLayout.AllRolesOverlap, _ALL_BUCKETS);
        _disableFacilityIf(true);

        _assertUnauthorizedActiveRequests(l, caller_);
    }

    // Scenarios: L-13.
    // Use the bound Configurator; cross valid inputs, each fault and combined faults with the named lifecycle state.
    function test_authorization_givenEnabled_givenPolicyInactive_whenCallerIsConfigurator_reverts()
        public
    {
        Ledger memory l = _createFixedPendingPayoutLedger(RoleLayout.AllRolesOverlap, _ALL_BUCKETS);

        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoans));
        _assertInactiveRequests(
            l,
            address(burnerLoansConfig),
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_PolicyInactive.selector)
        );
    }

    // Scenarios: L-14.
    // Fuzz callers outside the bound Configurator and admin; cross valid inputs, each fault and combined faults with the named lifecycle state.
    function test_authorization_givenEnabled_givenPolicyInactive_whenCallerIsUnauthorized_reverts(
        address caller_
    ) public {
        vm.assume(caller_ != address(burnerLoansConfig) && caller_ != admin);
        Ledger memory l = _createFixedPendingPayoutLedger(RoleLayout.AllRolesOverlap, _ALL_BUCKETS);

        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoans));
        _assertInactiveRequests(
            l,
            caller_,
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: L-19.
    // Use the bound Configurator; cross valid inputs, each fault and combined faults with the named lifecycle state.
    function test_authorization_givenDisabled_givenPolicyInactive_whenCallerIsConfigurator_reverts()
        public
    {
        Ledger memory l = _createFixedPendingPayoutLedger(RoleLayout.AllRolesOverlap, _ALL_BUCKETS);
        _disableFacilityIf(true);
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoans));
        _assertInactiveRequests(
            l,
            address(burnerLoansConfig),
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_PolicyInactive.selector)
        );
    }

    // Scenarios: L-20.
    // Fuzz callers outside the bound Configurator and admin; cross valid inputs, each fault and combined faults with the named lifecycle state.
    function test_authorization_givenDisabled_givenPolicyInactive_whenCallerIsUnauthorized_reverts(
        address caller_
    ) public {
        vm.assume(caller_ != address(burnerLoansConfig) && caller_ != admin);
        Ledger memory l = _createFixedPendingPayoutLedger(RoleLayout.AllRolesOverlap, _ALL_BUCKETS);
        _disableFacilityIf(true);
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoans));
        _assertInactiveRequests(
            l,
            caller_,
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    /// @dev	Cross one valid request, each input fault and combined faults with the chosen caller
    ///      and policy membership. Preview checks inputs; execution first checks caller/policy.
    function _authorizationRequests(
        Ledger memory l
    ) internal view returns (Request[9] memory requests, bytes[9] memory errors) {
        address keeper = l.keepers[0];
        address asset = address(l.token);
        requests = [
            Request({token: asset, recipient: keeper, destination: alice, amount: 1}),
            Request({token: address(0), recipient: keeper, destination: alice, amount: 1}),
            Request({token: _NO_CODE_TOKEN, recipient: keeper, destination: alice, amount: 1}),
            Request({token: asset, recipient: address(0), destination: alice, amount: 1}),
            Request({token: asset, recipient: keeper, destination: address(0), amount: 1}),
            Request({
                token: asset,
                recipient: keeper,
                destination: address(burnerLoans),
                amount: 1
            }),
            Request({token: asset, recipient: keeper, destination: alice, amount: 0}),
            Request({
                token: asset,
                recipient: keeper,
                destination: alice,
                amount: (_TOTAL_FIXED_PENDING + 1)
            }),
            Request({
                token: address(0),
                recipient: address(0),
                destination: address(burnerLoans),
                amount: 0
            })
        ];
        errors[1] = _invalidAssetError(address(0));
        errors[2] = _invalidAssetError(_NO_CODE_TOKEN);
        errors[3] = _zeroAddressError();
        errors[4] = abi.encodeWithSelector(
            IBurnerLoansRescue.BurnerLoans_InvalidRescueDestination.selector,
            address(0)
        );
        errors[5] = abi.encodeWithSelector(
            IBurnerLoansRescue.BurnerLoans_InvalidRescueDestination.selector,
            address(burnerLoans)
        );
        errors[6] = _zeroAmountError();
        errors[7] = _insufficientPayoutError(
            asset,
            (_TOTAL_FIXED_PENDING + 1),
            _TOTAL_FIXED_PENDING
        );
        errors[8] = _invalidAssetError(address(0));
    }

    function _assertActiveInputFailures(Ledger memory l, address caller_) internal {
        (Request[9] memory requests, bytes[9] memory errors) = _authorizationRequests(l);
        for (uint256 i = 1; i < requests.length; ++i)
            _assertRescueReverts(l, requests[i], caller_, errors[i], errors[i]);
    }

    function _assertUnauthorizedActiveRequests(Ledger memory l, address caller_) internal {
        (Request[9] memory requests, bytes[9] memory errors) = _authorizationRequests(l);
        bytes memory unauthorized = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);
        for (uint256 i; i < requests.length; ++i)
            _assertRescueReverts(l, requests[i], caller_, errors[i], unauthorized);
    }

    function _assertInactiveRequests(
        Ledger memory l,
        address caller_,
        bytes memory executionError_
    ) internal {
        (Request[9] memory requests, ) = _authorizationRequests(l);
        bytes memory policyError = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_PolicyInactive.selector
        );
        for (uint256 i; i < requests.length; ++i)
            _assertRescueReverts(l, requests[i], caller_, policyError, executionError_);
    }

    // Scenarios: L-02, L-08, L-14, L-20.
    // Explicitly check zero, emergency-only, delegated operator, Treasury and Alice across all four local/policy states.
    function test_authorization_whenUnauthorizedIdentitiesAreSeeded() public {
        vm.prank(admin);
        burnerLoansConfig.setConfigOperator(makeAddr("delegated operator"));
        address[5] memory callers = [
            address(0),
            emergency,
            burnerLoansConfig.configOperator(),
            address(trsry),
            alice
        ];
        uint256 snapshot = vm.snapshotState();
        for (uint256 i; i < callers.length; ++i) {
            test_authorization_givenEnabled_givenPolicyActive_whenCallerIsUnauthorized_reverts(
                callers[i]
            );
            _restoreSnapshot(snapshot);
            test_authorization_givenDisabled_givenPolicyActive_whenCallerIsUnauthorized_reverts(
                callers[i]
            );
            _restoreSnapshot(snapshot);
            test_authorization_givenEnabled_givenPolicyInactive_whenCallerIsUnauthorized_reverts(
                callers[i]
            );
            _restoreSnapshot(snapshot);
            test_authorization_givenDisabled_givenPolicyInactive_whenCallerIsUnauthorized_reverts(
                callers[i]
            );
            _restoreSnapshot(snapshot);
        }
    }

    // Ordinary allocation tests: constants establish the debt; amount is the only numeric
    // fuzz input. Loops enumerate compatible role layouts and optional unrelated buckets.

    // Scenarios: P-01, TX-01.
    // The selected keeper always owns reward; fee/seizure may be eligible or owed to other roles. Only reward is debited in this interval.
    // Fuzz amount within 1..10; enumerate compatible layouts and vary local enabled/disabled state.
    function test_payoutAllocation_givenReward_whenAmountIsWithinItsInterval(
        uint256 amount_,
        bool disabled_
    ) public {
        uint256 amount = bound(amount_, 1, _REWARD);
        uint256 snapshot = vm.snapshotState();
        for (uint8 layoutIndex; layoutIndex <= uint8(RoleLayout.AllRolesOverlap); ++layoutIndex)
            for (uint256 fee; fee < 2; ++fee)
                for (uint256 seizure; seizure < 2; ++seizure) {
                    Ledger memory l = _createPendingPayoutLedger(
                        _configurePayoutRoles(RoleLayout(layoutIndex)),
                        _REWARD,
                        fee * _FEE,
                        seizure * _SEIZURE
                    );
                    _disableFacilityIf(disabled_);
                    _assertRescueSucceeds(l, l.keepers[0], alice, amount, [amount, uint256(0), 0]);
                    _restoreSnapshot(snapshot);
                }
    }

    // Scenarios: P-01, TX-01.
    // Run the interval test at min, min+1, max-1 and max, with the facility both enabled and disabled.
    function test_payoutAllocation_givenReward_whenBoundariesAreSeeded() public {
        uint256[4] memory amounts = [uint256(1), 2, 9, _REWARD];
        for (uint256 disabled; disabled < 2; ++disabled)
            for (uint256 i; i < amounts.length; ++i)
                test_payoutAllocation_givenReward_whenAmountIsWithinItsInterval(
                    amounts[i],
                    disabled != 0
                );
    }

    // Scenarios: P-02, TX-01.
    // When K=F, its reward bucket must be absent. Otherwise a reward may remain owed to the distinct keeper; seizure may also remain pending.
    // Fuzz amount within 1..20 and transfer/read addresses; enumerate compatible layouts and vary local enabled/disabled state.
    function test_payoutAllocation_givenFee_whenAmountIsWithinItsInterval(
        uint256 amount_,
        bool disabled_
    ) public {
        uint256 amount = bound(amount_, 1, _FEE);
        uint256 snapshot = vm.snapshotState();
        for (uint8 layoutIndex; layoutIndex <= uint8(RoleLayout.AllRolesOverlap); ++layoutIndex) {
            bool keeperIsFee = layoutIndex == uint8(RoleLayout.KeeperIsFeeRecipient) ||
                layoutIndex == uint8(RoleLayout.AllRolesOverlap);
            for (uint256 reward; reward < (keeperIsFee ? 1 : 2); ++reward)
                for (uint256 seizure; seizure < 2; ++seizure) {
                    Ledger memory l = _createPendingPayoutLedger(
                        _configurePayoutRoles(RoleLayout(layoutIndex)),
                        reward * _REWARD,
                        _FEE,
                        seizure * _SEIZURE
                    );
                    _disableFacilityIf(disabled_);
                    _assertRescueSucceeds(
                        l,
                        l.feeRecipient,
                        alice,
                        amount,
                        [uint256(0), amount, 0]
                    );
                    _restoreSnapshot(snapshot);
                }
        }
    }

    // Scenarios: P-02, TX-01.
    // Run the interval test at min, min+1, max-1 and max, with the facility both enabled and disabled.
    function test_payoutAllocation_givenFee_whenBoundariesAreSeeded() public {
        uint256[4] memory amounts = [uint256(1), 2, 19, _FEE];
        for (uint256 disabled; disabled < 2; ++disabled)
            for (uint256 i; i < amounts.length; ++i)
                test_payoutAllocation_givenFee_whenAmountIsWithinItsInterval(
                    amounts[i],
                    disabled != 0
                );
    }

    // Scenarios: P-03, TX-01.
    // If K=T or F=T, that earlier bucket must be absent. Earlier buckets owed to distinct identities may remain pending and must not be debited.
    // Fuzz amount within 1..30 and transfer/read addresses; enumerate compatible layouts and vary local enabled/disabled state.
    function test_payoutAllocation_givenSeizure_whenAmountIsWithinItsInterval(
        uint256 amount_,
        bool disabled_
    ) public {
        uint256 amount = bound(amount_, 1, _SEIZURE);
        uint256 snapshot = vm.snapshotState();
        for (uint8 layoutIndex; layoutIndex <= uint8(RoleLayout.AllRolesOverlap); ++layoutIndex) {
            bool keeperIsTreasury = layoutIndex == uint8(RoleLayout.KeeperIsTreasury) ||
                layoutIndex == uint8(RoleLayout.AllRolesOverlap);
            bool feeIsTreasury = layoutIndex == uint8(RoleLayout.FeeRecipientIsTreasury) ||
                layoutIndex == uint8(RoleLayout.AllRolesOverlap);
            for (uint256 reward; reward < (keeperIsTreasury ? 1 : 2); ++reward)
                for (uint256 fee; fee < (feeIsTreasury ? 1 : 2); ++fee) {
                    Ledger memory l = _createPendingPayoutLedger(
                        _configurePayoutRoles(RoleLayout(layoutIndex)),
                        reward * _REWARD,
                        fee * _FEE,
                        _SEIZURE
                    );
                    _disableFacilityIf(disabled_);
                    _assertRescueSucceeds(l, l.treasury, alice, amount, [uint256(0), 0, amount]);
                    _restoreSnapshot(snapshot);
                }
        }
    }

    // Scenarios: P-03, TX-01.
    // Run the interval test at min, min+1, max-1 and max, with the facility both enabled and disabled.
    function test_payoutAllocation_givenSeizure_whenBoundariesAreSeeded() public {
        uint256[4] memory amounts = [uint256(1), 2, 29, _SEIZURE];
        for (uint256 disabled; disabled < 2; ++disabled)
            for (uint256 i; i < amounts.length; ++i)
                test_payoutAllocation_givenSeizure_whenAmountIsWithinItsInterval(
                    amounts[i],
                    disabled != 0
                );
    }

    // Scenarios: P-04, TX-01.
    // Only KF/KFT can own both buckets. Seizure may be absent or pending; this interval must leave it unchanged.
    // Fuzz amount within 11..30 and transfer/read addresses; enumerate compatible layouts and vary local enabled/disabled state.
    function test_payoutAllocation_givenRewardAndFee_whenAmountIsWithinItsInterval(
        uint256 amount_,
        bool disabled_
    ) public {
        uint256 amount = bound(amount_, 11, _SEIZURE);
        uint256 snapshot = vm.snapshotState();
        RoleLayout[2] memory layouts = [
            RoleLayout.KeeperIsFeeRecipient,
            RoleLayout.AllRolesOverlap
        ];
        for (uint256 layoutIndex; layoutIndex < layouts.length; ++layoutIndex)
            for (uint256 seizure; seizure < 2; ++seizure) {
                Ledger memory l = _createPendingPayoutLedger(
                    _configurePayoutRoles(layouts[layoutIndex]),
                    _REWARD,
                    _FEE,
                    seizure * _SEIZURE
                );
                _disableFacilityIf(disabled_);
                _assertRescueSucceeds(
                    l,
                    l.keepers[0],
                    alice,
                    amount,
                    [_REWARD, amount - _REWARD, uint256(0)]
                );
                _restoreSnapshot(snapshot);
            }
    }

    // Scenarios: P-04, TX-01.
    // Run the interval test at min, min+1, max-1 and max, with the facility both enabled and disabled.
    function test_payoutAllocation_givenRewardAndFee_whenBoundariesAreSeeded() public {
        uint256[4] memory amounts = [uint256(11), 12, 29, _SEIZURE];
        for (uint256 disabled; disabled < 2; ++disabled)
            for (uint256 i; i < amounts.length; ++i)
                test_payoutAllocation_givenRewardAndFee_whenAmountIsWithinItsInterval(
                    amounts[i],
                    disabled != 0
                );
    }

    // Scenarios: P-05, TX-01.
    // Only KT/KFT can own both buckets. KFT requires an absent fee bucket; KT may leave fees owed to the distinct fee recipient.
    // Fuzz amount within 11..40 and transfer/read addresses; enumerate compatible layouts and vary local enabled/disabled state.
    function test_payoutAllocation_givenRewardAndSeizure_whenAmountIsWithinItsInterval(
        uint256 amount_,
        bool disabled_
    ) public {
        uint256 amount = bound(amount_, 11, 40);
        uint256 snapshot = vm.snapshotState();
        RoleLayout[2] memory layouts = [RoleLayout.KeeperIsTreasury, RoleLayout.AllRolesOverlap];
        for (uint256 layoutIndex; layoutIndex < layouts.length; ++layoutIndex)
            for (
                uint256 fee;
                fee < (layouts[layoutIndex] == RoleLayout.AllRolesOverlap ? 1 : 2);
                ++fee
            ) {
                Ledger memory l = _createPendingPayoutLedger(
                    _configurePayoutRoles(layouts[layoutIndex]),
                    _REWARD,
                    fee * _FEE,
                    _SEIZURE
                );
                _disableFacilityIf(disabled_);
                _assertRescueSucceeds(
                    l,
                    l.keepers[0],
                    alice,
                    amount,
                    [_REWARD, uint256(0), amount - _REWARD]
                );
                _restoreSnapshot(snapshot);
            }
    }

    // Scenarios: P-05, TX-01.
    // Run the interval test at min, min+1, max-1 and max, with the facility both enabled and disabled.
    function test_payoutAllocation_givenRewardAndSeizure_whenBoundariesAreSeeded() public {
        uint256[4] memory amounts = [uint256(11), 12, 39, 40];
        for (uint256 disabled; disabled < 2; ++disabled)
            for (uint256 i; i < amounts.length; ++i)
                test_payoutAllocation_givenRewardAndSeizure_whenAmountIsWithinItsInterval(
                    amounts[i],
                    disabled != 0
                );
    }

    // Scenarios: P-06, TX-01.
    // Only FT/KFT can own both buckets. KFT requires absent reward; FT may leave a distinct keeper reward owed.
    // Fuzz amount within 21..50 and transfer/read addresses; enumerate compatible layouts and vary local enabled/disabled state.
    function test_payoutAllocation_givenFeeAndSeizure_whenAmountIsWithinItsInterval(
        uint256 amount_,
        bool disabled_
    ) public {
        uint256 amount = bound(amount_, 21, 50);
        uint256 snapshot = vm.snapshotState();
        RoleLayout[2] memory layouts = [
            RoleLayout.FeeRecipientIsTreasury,
            RoleLayout.AllRolesOverlap
        ];
        for (uint256 layoutIndex; layoutIndex < layouts.length; ++layoutIndex)
            for (
                uint256 reward;
                reward < (layouts[layoutIndex] == RoleLayout.AllRolesOverlap ? 1 : 2);
                ++reward
            ) {
                Ledger memory l = _createPendingPayoutLedger(
                    _configurePayoutRoles(layouts[layoutIndex]),
                    reward * _REWARD,
                    _FEE,
                    _SEIZURE
                );
                _disableFacilityIf(disabled_);
                _assertRescueSucceeds(
                    l,
                    l.treasury,
                    alice,
                    amount,
                    [uint256(0), _FEE, amount - _FEE]
                );
                _restoreSnapshot(snapshot);
            }
    }

    // Scenarios: P-06, TX-01.
    // Run the interval test at min, min+1, max-1 and max, with the facility both enabled and disabled.
    function test_payoutAllocation_givenFeeAndSeizure_whenBoundariesAreSeeded() public {
        uint256[4] memory amounts = [uint256(21), 22, 49, 50];
        for (uint256 disabled; disabled < 2; ++disabled)
            for (uint256 i; i < amounts.length; ++i)
                test_payoutAllocation_givenFeeAndSeizure_whenAmountIsWithinItsInterval(
                    amounts[i],
                    disabled != 0
                );
    }

    // Scenarios: P-07, TX-01.
    // KFT owns every bucket. Amount 31..60 clears reward and fee, then deducts seizure; 60 removes the final pending token.
    // Fuzz amount within 31..60 and transfer/read addresses; enumerate compatible layouts and vary local enabled/disabled state.
    function test_payoutAllocation_givenRewardFeeAndSeizure_whenAmountIsWithinItsInterval(
        uint256 amount_,
        bool disabled_
    ) public {
        uint256 amount = bound(amount_, 31, _TOTAL_FIXED_PENDING);
        uint256 snapshot = vm.snapshotState();
        {
            Ledger memory l = _createPendingPayoutLedger(
                _configurePayoutRoles(RoleLayout.AllRolesOverlap),
                _REWARD,
                _FEE,
                _SEIZURE
            );
            _disableFacilityIf(disabled_);
            _assertRescueSucceeds(
                l,
                l.keepers[0],
                alice,
                amount,
                [_REWARD, _FEE, amount - _REWARD - _FEE]
            );
            _restoreSnapshot(snapshot);
        }
    }

    // Scenarios: P-07, TX-01.
    // Run the interval test at min, min+1, max-1 and max, with the facility both enabled and disabled.
    function test_payoutAllocation_givenRewardFeeAndSeizure_whenBoundariesAreSeeded() public {
        uint256[4] memory amounts = [uint256(31), 32, 59, _TOTAL_FIXED_PENDING];
        for (uint256 disabled; disabled < 2; ++disabled)
            for (uint256 i; i < amounts.length; ++i)
                test_payoutAllocation_givenRewardFeeAndSeizure_whenAmountIsWithinItsInterval(
                    amounts[i],
                    disabled != 0
                );
    }

    // Scenarios: P-01.
    // All roles share one recipient: rescue 10 from reward/fee/seizure debts of 10/20/30; only reward drains.
    function test_payoutAllocation_givenKeeperFeeAndTreasuryOverlap_whenAmountEqualsKeeperReward()
        public
    {
        Ledger memory l = _createFixedPendingPayoutLedger(RoleLayout.AllRolesOverlap, _ALL_BUCKETS);
        // 10 reward + 20 fee + 30 seizure; pay 10, leaving 0 / 20 / 30.
        _assertRescueSucceeds(l, l.keepers[0], alice, _REWARD, [uint256(_REWARD), 0, 0]);
        _assertPendingPayouts(address(l.token), l.keepers[0], _FEE, _SEIZURE, 0);
    }

    // Scenarios: P-04.
    // All roles share one recipient: rescue 30 from debts of 10/20/30; reward and fee drain, seizure remains.
    function test_payoutAllocation_givenKeeperFeeAndTreasuryOverlap_whenAmountEqualsRewardAndFee()
        public
    {
        Ledger memory l = _createFixedPendingPayoutLedger(RoleLayout.AllRolesOverlap, _ALL_BUCKETS);
        // Pay 30 = 10 reward + 20 fee, leaving 0 / 0 / 30.
        _assertRescueSucceeds(l, l.keepers[0], alice, _SEIZURE, [uint256(_REWARD), _FEE, 0]);
        _assertPendingPayouts(address(l.token), l.keepers[0], 0, _SEIZURE, 0);
    }

    // Numerical generators are confined to numerical/isolation tests, separate from setup.
    // Reserve one unit for each later populated bucket. Every returned amount is passed
    // explicitly to _createPendingPayoutLedger; ordinary allocation tests never use this generator.
    /// @dev	Bound present buckets to positive amounts whose sum is at most budget_. Absent
    /// @dev	buckets stay zero; reserve one unit for each later present bucket before bounding.
    ///
    /// @param	bucketMask_	Populated global buckets: reward = 1, fee = 2, seizure = 4.
    /// @param	reward_		Raw fuzz input for the reward quantity.
    /// @param	fee_		Raw fuzz input for the fee quantity.
    /// @param	seizure_	Raw fuzz input for the seizure quantity.
    /// @param	budget_		Maximum combined debt in base units; must allow one unit per present bucket.
    /// @return	b			Exact [reward, fee, seizure] amounts to pass into ledger creation.
    function _boundSolventBucketAmounts(
        uint8 bucketMask_,
        uint256 reward_,
        uint256 fee_,
        uint256 seizure_,
        uint256 budget_
    ) internal pure returns (uint256[3] memory b) {
        bool hasFee = bucketMask_ & _FEE_BUCKET != 0;
        bool hasSeizure = bucketMask_ & _SEIZURE_BUCKET != 0;
        if (bucketMask_ & _REWARD_BUCKET != 0)
            b[0] = bound(reward_, 1, budget_ - (hasFee ? 1 : 0) - (hasSeizure ? 1 : 0));
        if (hasFee) b[1] = bound(fee_, 1, budget_ - b[0] - (hasSeizure ? 1 : 0));
        if (hasSeizure) b[2] = bound(seizure_, 1, budget_ - b[0] - b[1]);
    }

    /// @dev	Choose overlapping identities so one recipient owns every populated bucket.
    function _roleLayoutForSingleDebtOwner(uint8 bucketMask_) internal pure returns (RoleLayout) {
        if (bucketMask_ == (_REWARD_BUCKET | _FEE_BUCKET)) return RoleLayout.KeeperIsFeeRecipient;
        if (bucketMask_ == (_REWARD_BUCKET | _SEIZURE_BUCKET)) return RoleLayout.KeeperIsTreasury;
        if (bucketMask_ == (_FEE_BUCKET | _SEIZURE_BUCKET))
            return RoleLayout.FeeRecipientIsTreasury;
        return RoleLayout.AllRolesOverlap;
    }

    /// @dev	Select the debt owner after configuring a compatible single-owner layout.
    function _singleDebtOwner(Ledger memory l, uint8 bucketMask_) internal pure returns (address) {
        if (bucketMask_ & _REWARD_BUCKET != 0) return l.keepers[0];
        if (bucketMask_ & _FEE_BUCKET != 0) return l.feeRecipient;
        return l.treasury;
    }

    // Scenarios: N-01.
    // Enumerate all seven nonempty bucket combinations; fuzz positive splits totaling MAX, with one owner and full rescue.
    function test_numericExtremes_givenMaxEntitlement_whenFullDebtIsRescued(
        uint256 reward_,
        uint256 fee_
    ) public {
        uint256 snapshot = vm.snapshotState();
        for (uint8 bucketMask = 1; bucketMask <= _ALL_BUCKETS; ++bucketMask) {
            uint256[3] memory b = _boundSolventBucketAmounts(bucketMask, reward_, fee_, 1, _MAX);
            // The last present bucket is determined by total = MAX; a separate fuzz input
            // for that bucket would be overwritten. Earlier buckets retain their fuzzed splits.
            uint256 extra = _MAX - b[0] - b[1] - b[2];
            if (bucketMask & _SEIZURE_BUCKET != 0) b[2] += extra;
            else if (bucketMask & _FEE_BUCKET != 0) b[1] += extra;
            else b[0] += extra;
            Ledger memory l = _createPendingPayoutLedger(
                _configurePayoutRoles(_roleLayoutForSingleDebtOwner(bucketMask)),
                b[0],
                b[1],
                b[2]
            );
            _assertRescueSucceeds(l, _singleDebtOwner(l, bucketMask), alice, _MAX, b);
            _restoreSnapshot(snapshot);
        }
    }

    // Scenarios: N-01.
    // Each single bucket independently owes 1, MAX-1 or MAX; rescue its full debt.
    function test_numericExtremes_givenSingleBucket_whenExactEntitlementIsRescued() public {
        uint256[3] memory debts = [uint256(1), _MAX - 1, _MAX];
        uint256 snapshot = vm.snapshotState();
        for (uint8 bucket = _REWARD_BUCKET; bucket <= _SEIZURE_BUCKET; bucket *= 2)
            for (uint256 i; i < debts.length; ++i) {
                uint256 debt = debts[i];
                uint256[3] memory buckets = [
                    bucket == _REWARD_BUCKET ? debt : 0,
                    bucket == _FEE_BUCKET ? debt : 0,
                    bucket == _SEIZURE_BUCKET ? debt : 0
                ];
                Ledger memory l = _createPendingPayoutLedger(
                    _configurePayoutRoles(RoleLayout.AllRolesOverlap),
                    buckets[0],
                    buckets[1],
                    buckets[2]
                );
                _assertRescueSucceeds(l, l.keepers[0], alice, debt, buckets);
                _restoreSnapshot(snapshot);
            }
    }

    // Scenarios: I-06.
    // Each bucket independently owes 0, 1 or MAX-1. Both E+1 and MAX exceed entitlement.
    function test_numericExtremes_givenSingleBucket_whenAmountExceedsEntitlement_reverts() public {
        uint256[3] memory debts = [uint256(0), 1, _MAX - 1];
        uint256 snapshot = vm.snapshotState();
        for (uint8 bucket = _REWARD_BUCKET; bucket <= _SEIZURE_BUCKET; bucket *= 2)
            for (uint256 i; i < debts.length; ++i) {
                uint256 debt = debts[i];
                Ledger memory l = _createPendingPayoutLedger(
                    _configurePayoutRoles(RoleLayout.AllRolesOverlap),
                    bucket == _REWARD_BUCKET ? debt : 0,
                    bucket == _FEE_BUCKET ? debt : 0,
                    bucket == _SEIZURE_BUCKET ? debt : 0
                );
                uint256[2] memory amounts = [debt + 1, _MAX];
                for (uint256 a; a < amounts.length; ++a) {
                    bytes memory failure = _insufficientPayoutError(
                        address(l.token),
                        amounts[a],
                        debt
                    );
                    _assertRescueReverts(
                        l,
                        _createRescueRequest(l, l.keepers[0], alice, amounts[a]),
                        address(burnerLoansConfig),
                        failure,
                        failure
                    );
                }
                _restoreSnapshot(snapshot);
            }
    }

    // Scenarios: N-01.
    // Guarantee MAX is rescued for every nonempty bucket subset, independent of fuzz sampling.
    function test_numericExtremes_givenMaxEntitlement_whenBucketSubsetsAreSeeded() public {
        test_numericExtremes_givenMaxEntitlement_whenFullDebtIsRescued(_REWARD, _FEE);
    }

    // Scenarios: N-02.
    // Fixed 1/1/1 and MAX-2/1/1 debts seed minimum and near-MAX allocation boundaries.
    function test_numericExtremes_givenMixedBuckets_whenValidAmountBoundariesAreSeeded() public {
        uint256 snapshot = vm.snapshotState();
        uint256[4] memory amounts = [uint256(1), _MAX - 2, _MAX - 1, _MAX];
        for (uint256 i; i < amounts.length; ++i) {
            test_numericExtremes_givenVariableSolventBuckets_whenAmountIsWithinEntitlement(
                _MAX - 2,
                1,
                1,
                amounts[i]
            );
            _restoreSnapshot(snapshot);
        }
        test_numericExtremes_givenVariableSolventBuckets_whenAmountIsWithinEntitlement(1, 1, 1, 1);
    }

    // Scenarios: N-02, P-01, P-04, P-07.
    // With all roles shared, fuzz three positive debts totaling at most MAX and amount 1..E.
    function test_numericExtremes_givenVariableSolventBuckets_whenAmountIsWithinEntitlement(
        uint256 reward_,
        uint256 fee_,
        uint256 seizure_,
        uint256 amount_
    ) public {
        uint256[3] memory b = _boundSolventBucketAmounts(
            _ALL_BUCKETS,
            reward_,
            fee_,
            seizure_,
            _MAX
        );
        Ledger memory l = _createPendingPayoutLedger(
            _configurePayoutRoles(RoleLayout.AllRolesOverlap),
            b[0],
            b[1],
            b[2]
        );
        uint256 amount = bound(amount_, 1, b[0] + b[1] + b[2]);
        // Three numerical intervals; ordinary P-row tests check the same arithmetic
        // independently using constant debts and explicit event expectations.
        uint256 rewardPaid = amount <= b[0] ? amount : b[0];
        uint256 feePaid = amount <= b[0] ? 0 : (amount <= b[0] + b[1] ? amount - b[0] : b[1]);
        _assertRescueSucceeds(
            l,
            l.keepers[0],
            alice,
            amount,
            [rewardPaid, feePaid, amount - rewardPaid - feePaid]
        );
    }

    // Scenarios: TX-01, TX-05.
    // All roles overlap with debts 10/20/30; fuzz amount 1..60 and destination, whose starting balance is 7.
    function test_transfers_givenExistingDestinationBalance_whenAmountIsRescued(
        uint256 amount_,
        address destination_
    ) public {
        Ledger memory l = _createFixedPendingPayoutLedger(RoleLayout.AllRolesOverlap, _ALL_BUCKETS);
        vm.assume(_isPermittedDestination(destination_, address(l.token)));
        l.token.mint(destination_, 7);
        uint256 amount = bound(amount_, 1, _TOTAL_FIXED_PENDING);
        uint256 rewardPaid = amount <= _REWARD ? amount : _REWARD;
        uint256 feePaid = amount <= _REWARD ? 0 : (amount <= _SEIZURE ? amount - _REWARD : _FEE);
        _assertRescueSucceeds(
            l,
            l.keepers[0],
            destination_,
            amount,
            [rewardPaid, feePaid, amount - rewardPaid - feePaid]
        );
    }

    // Scenarios: TX-03.
    // Fuzz layout, bucket presence and a role with positive E; block Alice as destination and request 1..E.
    function test_transfers_givenBlockedDestination_whenAmountIsRescued_reverts(
        RoleLayout layout_,
        uint8 bucketMask_,
        Recipient recipient_,
        uint256 amount_
    ) public {
        Ledger memory l = _createFixedPendingPayoutLedger(
            layout_,
            uint8(bound(bucketMask_, 0, _ALL_BUCKETS))
        );
        address recipient = _selectRescueRecipient(l, recipient_);
        uint256 entitlement = _expectedRecipientPayout(l, recipient);
        // Reject generator inputs outside this success-shaped transfer scenario. Unlike an
        // early return, an accepted fuzz run always reaches the token's transfer failure.
        vm.assume(entitlement != 0);
        uint256 amount = bound(amount_, 1, entitlement);
        l.token.setTransferBlocked(alice, true);
        bytes memory expectedError = abi.encodeWithSelector(
            ReentrantPayoutToken.TransferBlocked.selector,
            alice
        );
        _assertRescueReverts(
            l,
            _createRescueRequest(l, recipient, alice, amount),
            address(burnerLoansConfig),
            "",
            expectedError
        );
    }

    // Scenarios: TX-04.
    // Keep debts 10/20/30 owed to one recipient, burn all custody, then fuzz an otherwise valid amount 1..60.
    function test_transfers_givenDebtWithoutCustody_whenAmountIsRescued_reverts(
        uint256 amount_
    ) public {
        Ledger memory l = _createFixedPendingPayoutLedger(RoleLayout.AllRolesOverlap, _ALL_BUCKETS);
        l.token.burn(address(burnerLoans), _TOTAL_FIXED_PENDING);
        uint256 amount = bound(amount_, 1, _TOTAL_FIXED_PENDING);
        bytes memory expectedError = abi.encodeWithSignature(
            "ERC20InsufficientBalance(address,uint256,uint256)",
            address(burnerLoans),
            0,
            amount
        );
        _assertRescueReverts(
            l,
            _createRescueRequest(l, l.keepers[0], alice, amount),
            address(burnerLoansConfig),
            "",
            expectedError
        );
    }

    // Scenarios: TX-01, TX-05.
    // Standard transfers at the fixed allocation boundaries, with a pre-existing destination balance.
    function test_transfers_givenExistingDestinationBalance_whenAmountBoundariesAreSeeded() public {
        uint256 snapshot = vm.snapshotState();
        uint256[5] memory amounts = [
            uint256(1),
            _REWARD,
            _REWARD + 1,
            _REWARD + _FEE,
            _TOTAL_FIXED_PENDING
        ];
        for (uint256 i; i < amounts.length; ++i) {
            test_transfers_givenExistingDestinationBalance_whenAmountIsRescued(amounts[i], alice);
            _restoreSnapshot(snapshot);
        }
    }

    // Scenarios: TX-04.
    // Valid requests at the allocation boundaries all fail because custody is zero.
    function test_transfers_givenDebtWithoutCustody_whenAmountBoundariesAreSeeded_reverts() public {
        uint256 snapshot = vm.snapshotState();
        uint256[5] memory amounts = [
            uint256(1),
            _REWARD,
            _REWARD + 1,
            _REWARD + _FEE,
            _TOTAL_FIXED_PENDING
        ];
        for (uint256 i; i < amounts.length; ++i) {
            test_transfers_givenDebtWithoutCustody_whenAmountIsRescued_reverts(amounts[i]);
            _restoreSnapshot(snapshot);
        }
    }

    // Scenarios: TX-03.
    // Seed every eligible layout/bucket/role combination with blocked transfers at 1 and E.
    function test_transfers_givenBlockedDestination_whenRecipientAndAmountBoundariesAreSeeded_reverts()
        public
    {
        uint256 snapshot = vm.snapshotState();
        for (uint8 layoutIndex; layoutIndex <= uint8(RoleLayout.AllRolesOverlap); ++layoutIndex)
            for (uint8 bucketMask = 1; bucketMask <= _ALL_BUCKETS; ++bucketMask) {
                Ledger memory l = _createFixedPendingPayoutLedger(
                    RoleLayout(layoutIndex),
                    bucketMask
                );
                for (uint8 role; role <= uint8(Recipient.Treasury); ++role) {
                    address recipient = _selectRescueRecipient(l, Recipient(role));
                    uint256 entitlement = _expectedRecipientPayout(l, recipient);
                    if (entitlement == 0) continue; // This recipient has no valid transfer request.
                    l.token.setTransferBlocked(alice, true);
                    bytes memory expectedError = abi.encodeWithSelector(
                        ReentrantPayoutToken.TransferBlocked.selector,
                        alice
                    );
                    _assertRescueReverts(
                        l,
                        _createRescueRequest(l, recipient, alice, 1),
                        address(burnerLoansConfig),
                        "",
                        expectedError
                    );
                    _assertRescueReverts(
                        l,
                        _createRescueRequest(l, recipient, alice, entitlement),
                        address(burnerLoansConfig),
                        "",
                        expectedError
                    );
                }
                _restoreSnapshot(snapshot);
            }
    }

    // Scenarios: ISO-01, I-06, TX-05.
    // Fuzz solvent debts and first-keeper role overlap; select each of three keepers and vary destinations, partial/full and excess amounts.
    function test_keeperIsolation_givenThreeKeepers_whenEachIsSelected(
        RoleLayout layout_,
        uint8 bucketMask_,
        uint256[3] memory rewards_,
        uint256 fee_,
        uint256 seizure_,
        uint256 amount_,
        address destination_
    ) public {
        // Reserve exactly two units for the other two positive keeper debts. Optional fee
        // and seizure remain absent/present, and the aggregate can reach uint256 MAX.
        uint8 bucketMask = uint8(bound(bucketMask_, 0, _ALL_BUCKETS)) | _REWARD_BUCKET;
        uint256[3] memory b = _boundSolventBucketAmounts(
            bucketMask,
            rewards_[0],
            fee_,
            seizure_,
            _MAX - 2
        );
        Ledger memory l = _createPendingPayoutLedger(
            _configurePayoutRoles(layout_),
            b[0],
            b[1],
            b[2]
        );
        uint256 second = bound(rewards_[1], 1, _MAX - _totalPendingDebt(l) - 1);
        l = _addPendingKeeperReward(l, makeAddr("second keeper"), second);
        uint256 third = bound(rewards_[2], 1, _MAX - _totalPendingDebt(l));
        l = _addPendingKeeperReward(l, makeAddr("third keeper"), third);
        vm.assume(_isPermittedDestination(destination_, address(l.token)));
        _checkKeeperIsolation(l, amount_, destination_);
    }

    function _checkKeeperIsolation(
        Ledger memory l,
        uint256 amount_,
        address destination_
    ) internal {
        address[6] memory destinations = [
            l.keepers[0],
            l.feeRecipient,
            l.treasury,
            l.keepers[1],
            l.keepers[2],
            destination_
        ];
        uint256 snapshot = vm.snapshotState();
        for (uint256 i; i < 3; ++i)
            for (uint256 d; d < destinations.length; ++d) {
                _assertKeeperPayoutIsolation(l, i, destinations[d], amount_);
                _restoreSnapshot(snapshot);
            }
    }

    /// @dev	Reject E+1, rescue an amount within 1..E, then restore and fully drain this keeper;
    ///      shared assertions verify that other keepers' rewards remain untouched.
    function _assertKeeperPayoutIsolation(
        Ledger memory l,
        uint256 index_,
        address destination_,
        uint256 amount_
    ) internal {
        address recipient = l.keepers[index_];
        uint256 reward = l.rewards[index_];
        uint256 fee = recipient == l.feeRecipient ? l.fee : 0;
        uint256 seizure = recipient == l.treasury ? l.seizure : 0;
        uint256 entitlement = reward + fee + seizure;
        if (entitlement < _MAX) {
            bytes memory expectedError = _insufficientPayoutError(
                address(l.token),
                entitlement + 1,
                entitlement
            );
            _assertRescueReverts(
                l,
                _createRescueRequest(l, recipient, destination_, entitlement + 1),
                address(burnerLoansConfig),
                expectedError,
                expectedError
            );
        }
        uint256 snapshot = vm.snapshotState();
        uint256 amount = bound(amount_, 1, entitlement);
        uint256 rewardPaid = amount <= reward ? amount : reward;
        uint256 feePaid = amount <= reward ? 0 : (amount <= reward + fee ? amount - reward : fee);
        _assertRescueSucceeds(
            l,
            recipient,
            destination_,
            amount,
            [rewardPaid, feePaid, amount - rewardPaid - feePaid]
        );
        _restoreSnapshot(snapshot);
        _assertRescueSucceeds(l, recipient, destination_, entitlement, [reward, fee, seizure]);
    }

    // Scenarios: ISO-01, I-06, TX-05.
    // For this layout, guarantee reward-only and optional fee/seizure combinations, plus aggregates at MAX across three keepers.
    function test_keeperIsolation_givenDistinct_whenMaskAndMaximumBoundariesAreSeeded() public {
        uint256 snapshot = vm.snapshotState();
        for (uint8 bucketMask = 1; bucketMask <= _ALL_BUCKETS; bucketMask += 2) {
            test_keeperIsolation_givenThreeKeepers_whenEachIsSelected(
                RoleLayout.Distinct,
                bucketMask,
                [uint256(_REWARD), 7, 9],
                _FEE,
                _SEIZURE,
                1,
                alice
            );
            _restoreSnapshot(snapshot);
        }
        test_keeperIsolation_givenThreeKeepers_whenEachIsSelected(
            RoleLayout.Distinct,
            1,
            [_MAX - 2, uint256(1), 1],
            0,
            0,
            1,
            alice
        );
        _restoreSnapshot(snapshot);
        test_keeperIsolation_givenThreeKeepers_whenEachIsSelected(
            RoleLayout.Distinct,
            7,
            [_MAX - 4, uint256(1), 1],
            1,
            1,
            1,
            alice
        );
    }

    // Scenarios: ISO-01, I-06, TX-05.
    // For this layout, guarantee reward-only and optional fee/seizure combinations, plus aggregates at MAX across three keepers.
    function test_keeperIsolation_givenKeeperIsFeeRecipient_whenMaskAndMaximumBoundariesAreSeeded()
        public
    {
        uint256 snapshot = vm.snapshotState();
        for (uint8 bucketMask = 1; bucketMask <= _ALL_BUCKETS; bucketMask += 2) {
            test_keeperIsolation_givenThreeKeepers_whenEachIsSelected(
                RoleLayout.KeeperIsFeeRecipient,
                bucketMask,
                [uint256(_REWARD), 7, 9],
                _FEE,
                _SEIZURE,
                1,
                alice
            );
            _restoreSnapshot(snapshot);
        }
        test_keeperIsolation_givenThreeKeepers_whenEachIsSelected(
            RoleLayout.KeeperIsFeeRecipient,
            1,
            [_MAX - 2, uint256(1), 1],
            0,
            0,
            1,
            alice
        );
        _restoreSnapshot(snapshot);
        test_keeperIsolation_givenThreeKeepers_whenEachIsSelected(
            RoleLayout.KeeperIsFeeRecipient,
            7,
            [_MAX - 4, uint256(1), 1],
            1,
            1,
            1,
            alice
        );
    }

    // Scenarios: ISO-01, I-06, TX-05.
    // For this layout, guarantee reward-only and optional fee/seizure combinations, plus aggregates at MAX across three keepers.
    function test_keeperIsolation_givenKeeperIsTreasury_whenMaskAndMaximumBoundariesAreSeeded()
        public
    {
        uint256 snapshot = vm.snapshotState();
        for (uint8 bucketMask = 1; bucketMask <= _ALL_BUCKETS; bucketMask += 2) {
            test_keeperIsolation_givenThreeKeepers_whenEachIsSelected(
                RoleLayout.KeeperIsTreasury,
                bucketMask,
                [uint256(_REWARD), 7, 9],
                _FEE,
                _SEIZURE,
                1,
                alice
            );
            _restoreSnapshot(snapshot);
        }
        test_keeperIsolation_givenThreeKeepers_whenEachIsSelected(
            RoleLayout.KeeperIsTreasury,
            1,
            [_MAX - 2, uint256(1), 1],
            0,
            0,
            1,
            alice
        );
        _restoreSnapshot(snapshot);
        test_keeperIsolation_givenThreeKeepers_whenEachIsSelected(
            RoleLayout.KeeperIsTreasury,
            7,
            [_MAX - 4, uint256(1), 1],
            1,
            1,
            1,
            alice
        );
    }

    // Scenarios: ISO-01, I-06, TX-05.
    // For this layout, guarantee reward-only and optional fee/seizure combinations, plus aggregates at MAX across three keepers.
    function test_keeperIsolation_givenFeeRecipientIsTreasury_whenMaskAndMaximumBoundariesAreSeeded()
        public
    {
        uint256 snapshot = vm.snapshotState();
        for (uint8 bucketMask = 1; bucketMask <= _ALL_BUCKETS; bucketMask += 2) {
            test_keeperIsolation_givenThreeKeepers_whenEachIsSelected(
                RoleLayout.FeeRecipientIsTreasury,
                bucketMask,
                [uint256(_REWARD), 7, 9],
                _FEE,
                _SEIZURE,
                1,
                alice
            );
            _restoreSnapshot(snapshot);
        }
        test_keeperIsolation_givenThreeKeepers_whenEachIsSelected(
            RoleLayout.FeeRecipientIsTreasury,
            1,
            [_MAX - 2, uint256(1), 1],
            0,
            0,
            1,
            alice
        );
        _restoreSnapshot(snapshot);
        test_keeperIsolation_givenThreeKeepers_whenEachIsSelected(
            RoleLayout.FeeRecipientIsTreasury,
            7,
            [_MAX - 4, uint256(1), 1],
            1,
            1,
            1,
            alice
        );
    }

    // Scenarios: ISO-01, I-06, TX-05.
    // For this layout, guarantee reward-only and optional fee/seizure combinations, plus aggregates at MAX across three keepers.
    function test_keeperIsolation_givenAllRolesOverlap_whenMaskAndMaximumBoundariesAreSeeded()
        public
    {
        uint256 snapshot = vm.snapshotState();
        for (uint8 bucketMask = 1; bucketMask <= _ALL_BUCKETS; bucketMask += 2) {
            test_keeperIsolation_givenThreeKeepers_whenEachIsSelected(
                RoleLayout.AllRolesOverlap,
                bucketMask,
                [uint256(_REWARD), 7, 9],
                _FEE,
                _SEIZURE,
                1,
                alice
            );
            _restoreSnapshot(snapshot);
        }
        test_keeperIsolation_givenThreeKeepers_whenEachIsSelected(
            RoleLayout.AllRolesOverlap,
            1,
            [_MAX - 2, uint256(1), 1],
            0,
            0,
            1,
            alice
        );
        _restoreSnapshot(snapshot);
        test_keeperIsolation_givenThreeKeepers_whenEachIsSelected(
            RoleLayout.AllRolesOverlap,
            7,
            [_MAX - 4, uint256(1), 1],
            1,
            1,
            1,
            alice
        );
    }

    // Scenarios: ISO-02, I-06.
    // Fuzz the selected token's layout/buckets/recipient and amount 1..E; the other token is independently empty or owed 1/2/3.
    function test_tokenIsolation_givenTwoTokens_whenOneIsRescued(
        RoleLayout layout_,
        uint8 bucketMask_,
        Recipient recipient_,
        bool otherPending_,
        uint256 amount_
    ) public {
        Ledger memory l = _createFixedPendingPayoutLedger(
            layout_,
            uint8(bound(bucketMask_, 0, _ALL_BUCKETS))
        );
        Ledger memory other = _createPendingPayoutLedger(
            l.keepers[0],
            otherPending_ ? 1 : 0,
            otherPending_ ? 2 : 0,
            otherPending_ ? 3 : 0
        );
        _assertTokenPayoutIsolation(l, other, _selectRescueRecipient(l, recipient_), amount_);
    }

    /// @dev	Reject E+1 and rescue within 1..E when nonempty; the second token's ledger and
    ///      custody/destination balances must remain unchanged after both operations.
    function _assertTokenPayoutIsolation(
        Ledger memory l,
        Ledger memory other,
        address recipient_,
        uint256 amount_
    ) internal {
        uint256 custody = other.token.balanceOf(address(burnerLoans));
        uint256 destinationBalance = other.token.balanceOf(alice);
        uint256 entitlement = _expectedRecipientPayout(l, recipient_);
        bytes memory expectedError = _insufficientPayoutError(
            address(l.token),
            entitlement + 1,
            entitlement
        );
        _assertRescueReverts(
            l,
            _createRescueRequest(l, recipient_, alice, entitlement + 1),
            address(burnerLoansConfig),
            expectedError,
            expectedError
        );
        if (entitlement != 0)
            _assertSelectedRecipientRescue(l, recipient_, bound(amount_, 1, entitlement));
        _assertPendingPayoutLedger(other);
        assertEq(
            other.token.balanceOf(address(burnerLoans)),
            custody,
            "other token custody unchanged"
        );
        assertEq(
            other.token.balanceOf(alice),
            destinationBalance,
            "other token destination balance unchanged"
        );
    }

    /// @dev	Check eligible debits for a single-keeper ledger in token-isolation and callback scenarios.
    /// @dev P-01..P-07 independently verify each allocation interval with explicit payments.
    function _assertSelectedRecipientRescue(
        Ledger memory l,
        address recipient_,
        uint256 amount_
    ) internal {
        uint256 reward = recipient_ == l.keepers[0] ? l.rewards[0] : 0;
        uint256 fee = recipient_ == l.feeRecipient ? l.fee : 0;
        uint256 rewardPaid = amount_ <= reward ? amount_ : reward;
        uint256 feePaid = amount_ <= reward
            ? 0
            : (amount_ <= reward + fee ? amount_ - reward : fee);
        _assertRescueSucceeds(
            l,
            recipient_,
            alice,
            amount_,
            [rewardPaid, feePaid, amount_ - rewardPaid - feePaid]
        );
    }

    // Only these bucket-presence combinations can have one owner of all debt under the chosen layout.
    // Enumeration constructs compatible cases directly instead of skipping generated ones.
    function _bucketMasksForSingleDebtOwner(
        RoleLayout layout_
    ) internal pure returns (uint8[] memory bucketMasks) {
        bucketMasks = new uint8[](
            layout_ == RoleLayout.AllRolesOverlap ? 7 : layout_ == RoleLayout.Distinct ? 3 : 4
        );
        bucketMasks[0] = _REWARD_BUCKET;
        bucketMasks[1] = _FEE_BUCKET;
        bucketMasks[2] = _SEIZURE_BUCKET;
        if (layout_ == RoleLayout.KeeperIsFeeRecipient)
            bucketMasks[3] = _REWARD_BUCKET | _FEE_BUCKET;
        if (layout_ == RoleLayout.KeeperIsTreasury)
            bucketMasks[3] = _REWARD_BUCKET | _SEIZURE_BUCKET;
        if (layout_ == RoleLayout.FeeRecipientIsTreasury)
            bucketMasks[3] = _FEE_BUCKET | _SEIZURE_BUCKET;
        if (layout_ == RoleLayout.AllRolesOverlap) {
            bucketMasks[3] = _REWARD_BUCKET | _FEE_BUCKET;
            bucketMasks[4] = _REWARD_BUCKET | _SEIZURE_BUCKET;
            bucketMasks[5] = _FEE_BUCKET | _SEIZURE_BUCKET;
            bucketMasks[6] = _ALL_BUCKETS;
        }
    }

    // Scenarios: ISO-04.
    // Fuzz compatible single-owner buckets and solvent quantities/surplus; drain all debt while another token stays owed.
    function test_surplusIsolation_givenOneDebtOwner_whenTokenIsFullyDrained(
        RoleLayout layout_,
        uint8 bucketMaskIndex_,
        uint256 reward_,
        uint256 fee_,
        uint256 seizure_,
        uint256 surplus_
    ) public {
        uint8[] memory bucketMasks = _bucketMasksForSingleDebtOwner(layout_);
        uint8 bucketMask = bucketMasks[bound(bucketMaskIndex_, 0, bucketMasks.length - 1)];
        uint256[3] memory b = _boundSolventBucketAmounts(bucketMask, reward_, fee_, seizure_, _MAX);
        Ledger memory l = _createPendingPayoutLedger(
            _configurePayoutRoles(layout_),
            b[0],
            b[1],
            b[2]
        );
        address recipient = _singleDebtOwner(l, bucketMask);
        uint256 total = b[0] + b[1] + b[2];
        assertEq(
            _expectedRecipientPayout(l, recipient),
            total,
            "chosen identity owns all remaining debt"
        );
        Ledger memory other = _createPendingPayoutLedger(l.keepers[0], 1, 2, 3);
        uint256 surplus = bound(surplus_, 0, _MAX - total);
        l.token.mint(address(burnerLoans), surplus);
        _assertRescueSucceeds(l, recipient, alice, total, b);
        assertEq(
            l.token.balanceOf(address(burnerLoans)),
            surplus,
            "surplus remains after pending token removal"
        );
        _assertPendingPayoutLedger(other);
        assertEq(
            other.token.balanceOf(address(burnerLoans)),
            6,
            "other token custody stays intact"
        );
        assertEq(other.token.balanceOf(alice), 0, "other token destination stays intact");
    }

    // Scenarios: ISO-04, I-06.
    // For this layout, enumerate single-owner buckets with surplus 0/1/5 and representable custody near MAX.
    function test_surplusIsolation_givenDistinct_whenMasksAndCustodyBoundariesAreSeeded() public {
        _checkSurplusBoundaries(RoleLayout.Distinct);
    }

    // Scenarios: ISO-04, I-06.
    // For this layout, enumerate single-owner buckets with surplus 0/1/5 and representable custody near MAX.
    function test_surplusIsolation_givenKeeperIsFeeRecipient_whenMasksAndCustodyBoundariesAreSeeded()
        public
    {
        _checkSurplusBoundaries(RoleLayout.KeeperIsFeeRecipient);
    }

    // Scenarios: ISO-04, I-06.
    // For this layout, enumerate single-owner buckets with surplus 0/1/5 and representable custody near MAX.
    function test_surplusIsolation_givenKeeperIsTreasury_whenMasksAndCustodyBoundariesAreSeeded()
        public
    {
        _checkSurplusBoundaries(RoleLayout.KeeperIsTreasury);
    }

    // Scenarios: ISO-04, I-06.
    // For this layout, enumerate single-owner buckets with surplus 0/1/5 and representable custody near MAX.
    function test_surplusIsolation_givenFeeRecipientIsTreasury_whenMasksAndCustodyBoundariesAreSeeded()
        public
    {
        _checkSurplusBoundaries(RoleLayout.FeeRecipientIsTreasury);
    }

    // Scenarios: ISO-04, I-06.
    // For this layout, enumerate single-owner buckets with surplus 0/1/5 and representable custody near MAX.
    function test_surplusIsolation_givenAllRolesOverlap_whenMasksAndCustodyBoundariesAreSeeded()
        public
    {
        _checkSurplusBoundaries(RoleLayout.AllRolesOverlap);
    }

    /// @dev	Enumerate compatible single-owner buckets with surplus 0/1/5, then representable
    ///      custody near MAX; full debt drainage must remove the token despite surplus.
    function _checkSurplusBoundaries(RoleLayout layout_) internal {
        uint8[] memory bucketMasks = _bucketMasksForSingleDebtOwner(layout_);
        uint256 snapshot = vm.snapshotState();
        uint256[3] memory surpluses = [uint256(0), 1, 5];
        for (uint256 m; m < bucketMasks.length; ++m)
            for (uint256 s; s < surpluses.length; ++s) {
                test_surplusIsolation_givenOneDebtOwner_whenTokenIsFullyDrained(
                    layout_,
                    uint8(m),
                    _REWARD,
                    _FEE,
                    _SEIZURE,
                    surpluses[s]
                );
                _restoreSnapshot(snapshot);
            }
        uint256[3] memory debts = [_MAX, _MAX - 1, _MAX - 5];
        for (uint8 m; m < 3; ++m)
            for (uint256 d; d < debts.length; ++d)
                for (uint256 s; s < surpluses.length; ++s) {
                    if (surpluses[s] > _MAX - debts[d]) continue; // Unrepresentable custody, not a valid fixture.
                    test_surplusIsolation_givenOneDebtOwner_whenTokenIsFullyDrained(
                        layout_,
                        m,
                        debts[d],
                        debts[d],
                        debts[d],
                        surpluses[s]
                    );
                    _restoreSnapshot(snapshot);
                }
    }

    // Scenarios: ISO-02, I-06.
    // Enumerate every layout/bucket/recipient with the other token empty or owed 1/2/3; check amount 1, full E and E+1.
    function test_tokenIsolation_whenEmptyPopulatedAndDrainBoundariesAreSeeded() public {
        uint256 snapshot = vm.snapshotState();
        for (uint8 layoutIndex; layoutIndex <= uint8(RoleLayout.AllRolesOverlap); ++layoutIndex)
            for (uint8 bucketMask; bucketMask <= _ALL_BUCKETS; ++bucketMask)
                for (uint256 populated; populated < 2; ++populated) {
                    Ledger memory l = _createFixedPendingPayoutLedger(
                        RoleLayout(layoutIndex),
                        bucketMask
                    );
                    Ledger memory other = _createPendingPayoutLedger(
                        l.keepers[0],
                        populated != 0 ? 1 : 0,
                        populated != 0 ? 2 : 0,
                        populated != 0 ? 3 : 0
                    );
                    uint256 fixtureSnapshot = vm.snapshotState();
                    for (uint8 role; role <= uint8(Recipient.Unrelated); ++role) {
                        address recipient = _selectRescueRecipient(l, Recipient(role));
                        _assertTokenPayoutIsolation(l, other, recipient, 1);
                        _restoreSnapshot(fixtureSnapshot);
                        uint256 entitlement = _expectedRecipientPayout(l, recipient);
                        _assertTokenPayoutIsolation(l, other, recipient, entitlement);
                        _restoreSnapshot(fixtureSnapshot);
                    }
                    _restoreSnapshot(snapshot);
                }
    }

    /// @dev	Nested recipient is independent of the outer rescue recipient. The real Config
    /// authorizes this token so nested writes reach the shared facility guard.
    function _configureNestedWriteCallback(
        Ledger memory l,
        NestedAction action_,
        address nestedRecipient_,
        bool invalid_,
        bool bubble_
    ) internal {
        vm.prank(admin);
        burnerLoansConfig.setConfigOperator(address(l.token));
        address token = invalid_ ? address(0) : address(l.token);
        address recipient = invalid_ ? address(0) : nestedRecipient_;
        address destination = invalid_ ? address(0) : alice;
        address target = address(burnerLoansConfig);
        bytes memory data;
        if (action_ == NestedAction.RescueSurplus)
            data = abi.encodeCall(burnerLoansConfig.rescue, (token, destination));
        else if (action_ == NestedAction.RescuePendingPayout)
            data = abi.encodeCall(
                burnerLoansConfig.rescuePendingPayout,
                (token, recipient, destination, invalid_ ? 0 : 1)
            );
        else if (action_ == NestedAction.SetPriceCacheMaxAge)
            data = abi.encodeCall(burnerLoansConfig.setPriceCacheMaxAge, (uint48(13)));
        else {
            target = address(burnerLoans);
            data = abi.encodeCall(burnerLoans.transferPendingPayout, (token, recipient));
        }
        l.token.setCallbackFrom(address(burnerLoans), target, data);
        l.token.setBubbleCallbackFailure(bubble_);
    }

    // Scenarios: CB-01.
    // Fuzz outer layout/buckets/role, nested action/validity and local state; enumerate all nested roles at outer amount 1..E.
    function test_callbacks_whenNestedWriteFailureIsCaught(
        RoleLayout layout_,
        uint8 bucketMask_,
        Recipient outer_,
        NestedAction action_,
        uint256 amount_,
        bool invalid_,
        bool disabled_
    ) public {
        Ledger memory l = _createFixedPendingPayoutLedger(
            layout_,
            uint8(bound(bucketMask_, 1, _ALL_BUCKETS))
        );
        address recipient = _selectRescueRecipient(l, outer_);
        uint256 entitlement = _expectedRecipientPayout(l, recipient);
        vm.assume(entitlement != 0);
        _disableFacilityIf(disabled_);
        uint256 amount = bound(amount_, 1, entitlement);
        uint256 snapshot = vm.snapshotState();
        for (uint8 nested; nested <= uint8(Recipient.Unrelated); ++nested) {
            // Invalid inputs overwrite the recipient; surplus/configuration calls have no recipient input.
            if (
                nested != 0 &&
                (invalid_ ||
                    action_ == NestedAction.RescueSurplus ||
                    action_ == NestedAction.SetPriceCacheMaxAge)
            ) continue;
            _assertCaughtNestedWriteCallback(
                l,
                recipient,
                _selectRescueRecipient(l, Recipient(nested)),
                action_,
                amount,
                invalid_
            );
            _restoreSnapshot(snapshot);
        }
    }

    /// @dev	Catch the authorized nested write's guard error; the outer rescue still succeeds
    ///      once, with configuration and authority unchanged.
    function _assertCaughtNestedWriteCallback(
        Ledger memory l,
        address recipient_,
        address nestedRecipient_,
        NestedAction action_,
        uint256 amount_,
        bool invalid_
    ) internal {
        _configureNestedWriteCallback(l, action_, nestedRecipient_, invalid_, false);
        bytes32 configuration = _configurationHash();
        _assertSelectedRecipientRescue(l, recipient_, amount_);
        assertEq(
            _configurationHash(),
            configuration,
            "caught callback preserves configuration and authority"
        );
        assertFalse(l.token.callbackSucceeded(), "authorized nested action fails");
        assertEq(
            l.token.callbackRevertData(),
            abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
            "nested write hits guard before any input/state check"
        );
    }

    // Scenarios: CB-02.
    // Fuzz outer layout/buckets/role, nested action/validity and local state; enumerate all nested roles at outer amount 1..E.
    function test_callbacks_whenNestedWriteFailureIsPropagated(
        RoleLayout layout_,
        uint8 bucketMask_,
        Recipient outer_,
        NestedAction action_,
        uint256 amount_,
        bool invalid_,
        bool disabled_
    ) public {
        Ledger memory l = _createFixedPendingPayoutLedger(
            layout_,
            uint8(bound(bucketMask_, 1, _ALL_BUCKETS))
        );
        address recipient = _selectRescueRecipient(l, outer_);
        uint256 entitlement = _expectedRecipientPayout(l, recipient);
        vm.assume(entitlement != 0);
        _disableFacilityIf(disabled_);
        uint256 amount = bound(amount_, 1, entitlement);
        uint256 snapshot = vm.snapshotState();
        for (uint8 nested; nested <= uint8(Recipient.Unrelated); ++nested) {
            // Invalid inputs overwrite the recipient; surplus/configuration calls have no recipient input.
            if (
                nested != 0 &&
                (invalid_ ||
                    action_ == NestedAction.RescueSurplus ||
                    action_ == NestedAction.SetPriceCacheMaxAge)
            ) continue;
            _assertPropagatedNestedWriteCallback(
                l,
                recipient,
                _selectRescueRecipient(l, Recipient(nested)),
                action_,
                amount,
                invalid_
            );
            _restoreSnapshot(snapshot);
        }
    }

    /// @dev	Propagate the nested guard failure through the token; outer debts, balances and
    ///      callback outcomes must all roll back.
    function _assertPropagatedNestedWriteCallback(
        Ledger memory l,
        address recipient_,
        address nestedRecipient_,
        NestedAction action_,
        uint256 amount_,
        bool invalid_
    ) internal {
        _configureNestedWriteCallback(l, action_, nestedRecipient_, invalid_, true);
        _assertRescueReverts(
            l,
            _createRescueRequest(l, recipient_, alice, amount_),
            address(burnerLoansConfig),
            "",
            abi.encodeWithSelector(ReentrantFeeToken.CallbackFailed.selector)
        );
    }

    // Scenarios: CB-01.
    function test_callbacks_givenDistinct_whenCaughtCasesAreSeeded() public {
        _checkCaughtWriteCallbacks(RoleLayout.Distinct);
    }

    // Scenarios: CB-02.
    function test_callbacks_givenDistinct_whenPropagatedCasesAreSeeded() public {
        _checkPropagatedWriteCallbacks(RoleLayout.Distinct);
    }

    // Scenarios: CB-03.
    function test_callbacks_givenDistinct_whenPartialReadCasesAreSeeded() public {
        _checkPartialReadCallbacks(RoleLayout.Distinct);
    }

    // Scenarios: CB-04.
    function test_callbacks_givenDistinct_whenFullReadCasesAreSeeded() public {
        _checkFullReadCallbacks(RoleLayout.Distinct);
    }

    // Scenarios: CB-01.
    function test_callbacks_givenKeeperIsFeeRecipient_whenCaughtCasesAreSeeded() public {
        _checkCaughtWriteCallbacks(RoleLayout.KeeperIsFeeRecipient);
    }

    // Scenarios: CB-02.
    function test_callbacks_givenKeeperIsFeeRecipient_whenPropagatedCasesAreSeeded() public {
        _checkPropagatedWriteCallbacks(RoleLayout.KeeperIsFeeRecipient);
    }

    // Scenarios: CB-03.
    function test_callbacks_givenKeeperIsFeeRecipient_whenPartialReadCasesAreSeeded() public {
        _checkPartialReadCallbacks(RoleLayout.KeeperIsFeeRecipient);
    }

    // Scenarios: CB-04.
    function test_callbacks_givenKeeperIsFeeRecipient_whenFullReadCasesAreSeeded() public {
        _checkFullReadCallbacks(RoleLayout.KeeperIsFeeRecipient);
    }

    // Scenarios: CB-01.
    function test_callbacks_givenKeeperIsTreasury_whenCaughtCasesAreSeeded() public {
        _checkCaughtWriteCallbacks(RoleLayout.KeeperIsTreasury);
    }

    // Scenarios: CB-02.
    function test_callbacks_givenKeeperIsTreasury_whenPropagatedCasesAreSeeded() public {
        _checkPropagatedWriteCallbacks(RoleLayout.KeeperIsTreasury);
    }

    // Scenarios: CB-03.
    function test_callbacks_givenKeeperIsTreasury_whenPartialReadCasesAreSeeded() public {
        _checkPartialReadCallbacks(RoleLayout.KeeperIsTreasury);
    }

    // Scenarios: CB-04.
    function test_callbacks_givenKeeperIsTreasury_whenFullReadCasesAreSeeded() public {
        _checkFullReadCallbacks(RoleLayout.KeeperIsTreasury);
    }

    // Scenarios: CB-01.
    function test_callbacks_givenFeeRecipientIsTreasury_whenCaughtCasesAreSeeded() public {
        _checkCaughtWriteCallbacks(RoleLayout.FeeRecipientIsTreasury);
    }

    // Scenarios: CB-02.
    function test_callbacks_givenFeeRecipientIsTreasury_whenPropagatedCasesAreSeeded() public {
        _checkPropagatedWriteCallbacks(RoleLayout.FeeRecipientIsTreasury);
    }

    // Scenarios: CB-03.
    function test_callbacks_givenFeeRecipientIsTreasury_whenPartialReadCasesAreSeeded() public {
        _checkPartialReadCallbacks(RoleLayout.FeeRecipientIsTreasury);
    }

    // Scenarios: CB-04.
    function test_callbacks_givenFeeRecipientIsTreasury_whenFullReadCasesAreSeeded() public {
        _checkFullReadCallbacks(RoleLayout.FeeRecipientIsTreasury);
    }

    // Scenarios: CB-01.
    function test_callbacks_givenAllRolesOverlap_whenCaughtCasesAreSeeded() public {
        _checkCaughtWriteCallbacks(RoleLayout.AllRolesOverlap);
    }

    // Scenarios: CB-02.
    function test_callbacks_givenAllRolesOverlap_whenPropagatedCasesAreSeeded() public {
        _checkPropagatedWriteCallbacks(RoleLayout.AllRolesOverlap);
    }

    // Scenarios: CB-03.
    function test_callbacks_givenAllRolesOverlap_whenPartialReadCasesAreSeeded() public {
        _checkPartialReadCallbacks(RoleLayout.AllRolesOverlap);
    }

    // Scenarios: CB-04.
    function test_callbacks_givenAllRolesOverlap_whenFullReadCasesAreSeeded() public {
        _checkFullReadCallbacks(RoleLayout.AllRolesOverlap);
    }

    /// @dev	Enumerate local states, outer/nested K/F/T recipients, all nested actions and
    ///      valid/invalid nested inputs; check caught/propagated errors and read callbacks.
    function _checkCaughtWriteCallbacks(RoleLayout layout_) internal {
        Ledger memory l = _createFixedPendingPayoutLedger(layout_, _ALL_BUCKETS);
        uint256 snapshot = vm.snapshotState();
        for (uint256 disabled; disabled < 2; ++disabled)
            for (uint8 outer; outer <= uint8(Recipient.Treasury); ++outer)
                for (uint256 full; full < 2; ++full) {
                    address recipient = _selectRescueRecipient(l, Recipient(outer));
                    uint256 amount = full == 0 ? 1 : _expectedRecipientPayout(l, recipient);
                    for (uint8 nested; nested <= uint8(Recipient.Treasury); ++nested)
                        for (
                            uint8 action;
                            action <= uint8(NestedAction.RetryPendingPayout);
                            ++action
                        )
                            for (uint256 invalid; invalid < 2; ++invalid) {
                                if (
                                    nested != 0 &&
                                    (invalid != 0 ||
                                        action == uint8(NestedAction.RescueSurplus) ||
                                        action == uint8(NestedAction.SetPriceCacheMaxAge))
                                ) continue;
                                _disableFacilityIf(disabled != 0);
                                _assertCaughtNestedWriteCallback(
                                    l,
                                    recipient,
                                    _selectRescueRecipient(l, Recipient(nested)),
                                    NestedAction(action),
                                    amount,
                                    invalid != 0
                                );
                                _restoreSnapshot(snapshot);
                            }
                }
    }

    function _checkPropagatedWriteCallbacks(RoleLayout layout_) internal {
        Ledger memory l = _createFixedPendingPayoutLedger(layout_, _ALL_BUCKETS);
        uint256 snapshot = vm.snapshotState();
        for (uint256 disabled; disabled < 2; ++disabled)
            for (uint8 outer; outer <= uint8(Recipient.Treasury); ++outer)
                for (uint256 full; full < 2; ++full) {
                    address recipient = _selectRescueRecipient(l, Recipient(outer));
                    uint256 amount = full == 0 ? 1 : _expectedRecipientPayout(l, recipient);
                    for (uint8 nested; nested <= uint8(Recipient.Treasury); ++nested)
                        for (
                            uint8 action;
                            action <= uint8(NestedAction.RetryPendingPayout);
                            ++action
                        )
                            for (uint256 invalid; invalid < 2; ++invalid) {
                                if (
                                    nested != 0 &&
                                    (invalid != 0 ||
                                        action == uint8(NestedAction.RescueSurplus) ||
                                        action == uint8(NestedAction.SetPriceCacheMaxAge))
                                ) continue;
                                _disableFacilityIf(disabled != 0);
                                _assertPropagatedNestedWriteCallback(
                                    l,
                                    recipient,
                                    _selectRescueRecipient(l, Recipient(nested)),
                                    NestedAction(action),
                                    amount,
                                    invalid != 0
                                );
                                _restoreSnapshot(snapshot);
                            }
                }
    }

    function _checkPartialReadCallbacks(RoleLayout layout_) internal {
        Ledger memory l = _createFixedPendingPayoutLedger(layout_, _ALL_BUCKETS);
        uint256 snapshot = vm.snapshotState();
        for (uint256 disabled; disabled < 2; ++disabled)
            for (uint8 outer; outer <= uint8(Recipient.Treasury); ++outer) {
                address recipient = _selectRescueRecipient(l, Recipient(outer));
                _disableFacilityIf(disabled != 0);
                _assertReadCallbackState(l, recipient, 1);
                _restoreSnapshot(snapshot);
            }
    }

    function _checkFullReadCallbacks(RoleLayout layout_) internal {
        Ledger memory l = _createFixedPendingPayoutLedger(layout_, _ALL_BUCKETS);
        uint256 snapshot = vm.snapshotState();
        for (uint256 disabled; disabled < 2; ++disabled)
            for (uint8 outer; outer <= uint8(Recipient.Treasury); ++outer) {
                address recipient = _selectRescueRecipient(l, Recipient(outer));
                _disableFacilityIf(disabled != 0);
                _assertReadCallbackState(l, recipient, _expectedRecipientPayout(l, recipient));
                _restoreSnapshot(snapshot);
            }
    }

    // Scenarios: CB-03.
    function test_callbacks_whenReadsObservePartialRescue(
        RoleLayout layout_,
        uint8 bucketMask_,
        Recipient recipient_,
        uint256 amount_,
        bool disabled_
    ) public {
        Ledger memory l = _createFixedPendingPayoutLedger(
            layout_,
            uint8(bound(bucketMask_, 1, _ALL_BUCKETS))
        );
        address recipient = _selectRescueRecipient(l, recipient_);
        uint256 available = _expectedRecipientPayout(l, recipient);
        vm.assume(available != 0);
        _disableFacilityIf(disabled_);
        // Constants are >= 10, so every positive entitlement has a genuine partial interval.
        _assertReadCallbackState(l, recipient, bound(amount_, 1, available - 1));
    }

    // Scenarios: CB-04.
    function test_callbacks_whenReadsObserveFullRescue(
        RoleLayout layout_,
        uint8 bucketMask_,
        Recipient recipient_,
        bool disabled_
    ) public {
        Ledger memory l = _createFixedPendingPayoutLedger(
            layout_,
            uint8(bound(bucketMask_, 1, _ALL_BUCKETS))
        );
        address recipient = _selectRescueRecipient(l, recipient_);
        uint256 available = _expectedRecipientPayout(l, recipient);
        vm.assume(available != 0);
        _disableFacilityIf(disabled_);
        // Constants are >= 10, so every positive entitlement has a genuine partial interval.
        _assertReadCallbackState(l, recipient, available);
    }

    /// @dev	A callback after transfer must see final accounting: remaining entitlement after
    ///      a partial rescue, or an insufficient-payout preview after full drainage.
    function _assertReadCallbackState(
        Ledger memory l,
        address recipient_,
        uint256 amount_
    ) internal {
        uint256 available = _expectedRecipientPayout(l, recipient_);
        l.token.setCallbackFrom(
            address(burnerLoans),
            address(l.token),
            abi.encodeCall(l.token.observe, (burnerLoans, recipient_, alice))
        );
        _assertSelectedRecipientRescue(l, recipient_, amount_);
        assertTrue(l.token.callbackSucceeded(), "read-only callback succeeds");
        assertEq(
            l.token.observedEntitlement(),
            available - amount_,
            "callback sees remaining entitlement"
        );
        assertEq(
            l.token.observedState(),
            l.token.observation(burnerLoans, recipient_, alice),
            "callback observes final ledger/indexes/custody"
        );
        if (amount_ == available)
            assertEq(
                l.token.observedFailure(),
                _insufficientPayoutError(address(l.token), 1, 0),
                "full-drain callback gets exact preview error"
            );
        else {
            assertEq(
                l.token.observedPreview(),
                available - amount_,
                "partial callback preview sees residual entitlement"
            );
            assertEq(l.token.observedFailure().length, 0, "partial callback preview succeeds");
        }
    }
}
// forge-lint: disable-end(literal-instead-of-constant,calls-loop,unused-return,unsafe-typecast)
