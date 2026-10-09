// SPDX-License-Identifier: Unlicense
// solhint-disable one-contract-per-file
pragma solidity >=0.8.24;

import {IERC20Errors} from "@openzeppelin-5.7.0/interfaces/draft-IERC6093.sol";
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC20FeeOnTransfer} from "src/test/mocks/MockERC20FeeOnTransfer.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {SafeERC20Exact} from "src/libraries/SafeERC20Exact.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

import {BurnerLoansBorrowTestBase} from "./fixtures/BurnerLoansBorrowTestBase.sol";

// Test actions assert effects directly; test inputs prove casts fit or select fixed-width values.
// forge-lint: disable-start(unused-return,unsafe-typecast)

contract BurnerLoansExtendTest is BurnerLoansBorrowTestBase {
    address internal operator;

    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function setUp() public override {
        super.setUp();
        operator = makeAddr("operator");
    }

    // Scenarios: EXT-P01, EXT-P04, EXT-N01
    function test_givenValidPositiveFeeExtension_routesExactFeeForEveryAuthorizedCaller(
        bool sendFeesToDistributor_,
        bool useOperator_,
        bool useMaximumFeeCap_
    ) public {
        _borrowForAlice();
        address caller = alice;
        if (useOperator_) {
            caller = operator;
            _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));
            usds.mint(operator, 100e18);
            vm.prank(operator);
            usds.approve(address(burnerLoans), type(uint256).max);
        }

        address recipient = _configureFeeRecipientForTest(sendFeesToDistributor_, address(usds));

        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        uint256 payerBefore = usds.balanceOf(caller);
        uint256 recipientBefore = usds.balanceOf(recipient);
        uint256 maxFee = useMaximumFeeCap_ ? type(uint256).max : preview.fee;

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.PayoutTransferred(
            address(usds),
            recipient,
            IBurnerLoans.PayoutKind.Fee,
            preview.fee
        );
        vm.prank(caller);
        (uint256 fee, uint48 maturity, uint256 health) = burnerLoans.extend(
            address(usds),
            alice,
            1,
            maxFee
        );

        assertGt(preview.fee, 0, "fixture charges a positive fee");
        assertEq(fee, preview.fee, "execution fee matches preview");
        assertEq(maturity, preview.maturity, "execution maturity matches preview");
        assertEq(health, preview.healthFactor, "execution health matches preview");
        assertEq(payerBefore - usds.balanceOf(caller), preview.fee, "caller pays exact fee");
        assertEq(
            usds.balanceOf(recipient) - recipientBefore,
            preview.fee,
            "live destination receives exact fee"
        );
        assertEq(burnerLoans.pendingPayout(address(usds), recipient), 0, "no fee remains owed");
        assertEq(burnerLoans.totalPendingForTest(address(usds)), 0, "no fee reserve remains");
        assertEq(burnerLoans.getPendingPayoutTokens().length, 0, "no token is indexed");
    }

    // Scenarios: EXT-L03
    function test_givenFeeTokenUnlistedByDistributor_extensionStillPaysDistributor(
        bool useOperator_
    ) public {
        _borrowForAlice();
        address caller = alice;
        if (useOperator_) {
            caller = operator;
            _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));
            usds.mint(operator, 100e18);
            vm.prank(operator);
            usds.approve(address(burnerLoans), type(uint256).max);
        }
        RevenueDistributor distributor = _installRevenueDistributorForTest(new address[](0));
        _setSendFeesToDistributor(true);
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        uint256 distributorBefore = usds.balanceOf(address(distributor));

        vm.prank(caller);
        burnerLoans.extend(address(usds), alice, 1, preview.fee);

        assertGt(preview.fee, 0, "extension fee is positive");
        assertEq(
            usds.balanceOf(address(distributor)) - distributorBefore,
            preview.fee,
            "unlisted fee reaches distributor"
        );
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(distributor)),
            0,
            "no fee remains pending"
        );
    }

    // Scenarios: EXT-N03, EXT-N04
    function test_givenOneUnitExtensionFee_routesExactUnit(
        bool sendFeesToDistributor_,
        bool useOperator_
    ) public {
        _configurePrice(address(ohm), 1);
        backingOracle.setBacking(1);
        usds.mint(alice, 100e18 + 2);
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), 2, alice);
        IBurnerLoans.BorrowPreview memory borrowPreview = burnerLoans.previewBorrow(
            address(usds),
            1,
            alice
        );
        burnerLoans.borrow(address(usds), 1, alice, alice, borrowPreview.fee);
        vm.stopPrank();

        address caller = alice;
        if (useOperator_) {
            caller = operator;
            _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));
            usds.mint(operator, 10);
            vm.prank(operator);
            usds.approve(address(burnerLoans), type(uint256).max);
        }

        address recipient = _configureFeeRecipientForTest(sendFeesToDistributor_, address(usds));
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        uint256 recipientBefore = usds.balanceOf(recipient);

        vm.prank(caller);
        burnerLoans.extend(address(usds), alice, 1, preview.fee);

        assertEq(preview.fee, 1, "extension fee rounds up to one collateral unit");
        assertEq(
            usds.balanceOf(recipient) - recipientBefore,
            1,
            "selected recipient receives one unit"
        );
        assertEq(burnerLoans.totalPendingForTest(address(usds)), 0, "no fee remains pending");
    }

    // Scenarios: EXT-P02
    function test_givenDeferredFee_laterExtensionSweepsBothToLiveDestination(
        bool priorSendFeesToDistributor_,
        bool currentSendFeesToDistributor_
    ) public {
        _borrowForAlice();
        RevenueDistributor distributor = _installRevenueDistributorForTest(address(usds));
        _setSendFeesToDistributor(priorSendFeesToDistributor_);
        address priorRecipient = priorSendFeesToDistributor_
            ? address(distributor)
            : address(trsry);
        uint256 treasuryBefore = usds.balanceOf(address(trsry));
        uint256 distributorBefore = usds.balanceOf(address(distributor));
        uint256 firstFee = burnerLoans.previewExtend(address(usds), alice, 1).fee;
        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, priorRecipient),
            abi.encodeWithSignature("Error(string)", "blocked")
        );
        vm.prank(alice);
        burnerLoans.extend(address(usds), alice, 1, firstFee);
        vm.clearMockedCalls();

        _setSendFeesToDistributor(currentSendFeesToDistributor_);
        address currentRecipient = currentSendFeesToDistributor_
            ? address(distributor)
            : address(trsry);
        uint256 secondFee = burnerLoans.previewExtend(address(usds), alice, 1).fee;

        vm.prank(alice);
        burnerLoans.extend(address(usds), alice, 1, secondFee);

        uint256 expectedTreasury = currentRecipient == address(trsry) ? firstFee + secondFee : 0;
        uint256 expectedDistributor = currentRecipient == address(distributor)
            ? firstFee + secondFee
            : 0;
        assertEq(
            usds.balanceOf(address(trsry)) - treasuryBefore,
            expectedTreasury,
            "Treasury receives only live-routed fees"
        );
        assertEq(
            usds.balanceOf(address(distributor)) - distributorBefore,
            expectedDistributor,
            "distributor receives only live-routed fees"
        );
        assertEq(burnerLoans.totalPendingForTest(address(usds)), 0, "combined reserve clears");
        assertEq(burnerLoans.getPendingPayoutTokens().length, 0, "token index clears");
    }

    // Scenarios: EXT-L01, EXT-L02
    function test_givenDistributorUnavailable_extensionStillPaysExactFee(
        bool kernelInactive_,
        bool useOperator_
    ) public {
        _borrowForAlice();
        address caller = alice;
        if (useOperator_) {
            caller = operator;
            _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));
            usds.mint(operator, 100e18);
            vm.prank(operator);
            usds.approve(address(burnerLoans), type(uint256).max);
        }
        RevenueDistributor distributor = _installFeeDistributorForTest(address(usds));
        if (kernelInactive_) {
            _deactivatePolicy(address(distributor));
        } else {
            vm.prank(admin);
            distributor.disable("");
        }
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        uint256 maturityBefore = burnerLoans.getPosition(address(usds), alice).maturity;
        uint256 payerBefore = usds.balanceOf(caller);
        uint256 distributorBefore = usds.balanceOf(address(distributor));
        uint256 treasuryBefore = usds.balanceOf(address(trsry));
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.PayoutTransferred(
            address(usds),
            address(distributor),
            IBurnerLoans.PayoutKind.Fee,
            preview.fee
        );

        vm.prank(caller);
        (uint256 fee, uint48 maturity, uint256 health) = burnerLoans.extend(
            address(usds),
            alice,
            1,
            preview.fee
        );

        assertEq(fee, preview.fee, "exact fee returned");
        assertEq(maturity, preview.maturity, "exact maturity returned");
        assertEq(health, preview.healthFactor, "exact health returned");
        assertGt(maturity, maturityBefore, "maturity advances");
        assertEq(payerBefore - usds.balanceOf(caller), preview.fee, "caller pays exact fee");
        assertEq(
            usds.balanceOf(address(distributor)) - distributorBefore,
            preview.fee,
            "unavailable distributor receives exact fee"
        );
        assertEq(usds.balanceOf(address(trsry)), treasuryBefore, "Treasury remains unchanged");
        assertEq(burnerLoans.totalPendingForTest(address(usds)), 0, "no pending reserve");
        assertEq(burnerLoans.getPendingPayoutTokens().length, 0, "no pending index");
    }

    // Scenarios: EXT-L04, EXT-L06
    function test_givenExtensionLifecycleGuard_rollsBackEveryRouteAndCaller(
        bool localDisable_,
        bool sendFeesToDistributor_,
        bool useOperator_
    ) public {
        _borrowForAlice();
        address caller = alice;
        if (useOperator_) {
            caller = operator;
            _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));
            usds.mint(operator, 100e18);
            vm.prank(operator);
            usds.approve(address(burnerLoans), type(uint256).max);
        }
        address recipient = _configureFeeRecipientForTest(sendFeesToDistributor_, address(usds));
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        IBurnerLoans.Position memory positionBefore = burnerLoans.getPosition(address(usds), alice);
        uint256 payerBefore = usds.balanceOf(caller);
        uint256 allowanceBefore = usds.allowance(caller, address(burnerLoans));
        uint256 recipientBefore = usds.balanceOf(recipient);
        bytes memory expectedError;
        if (localDisable_) {
            _disableBurnerLoans(emergency);
            expectedError = abi.encodeWithSelector(IEnabler.NotEnabled.selector);
        } else {
            _setAssetOriginationsEnabled(address(usds), false);
            expectedError = abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetOriginationsDisabled.selector,
                address(usds)
            );
        }

        vm.expectRevert(expectedError);
        burnerLoans.previewExtend(address(usds), alice, 1);
        vm.prank(caller);
        vm.expectRevert(expectedError);
        burnerLoans.extend(address(usds), alice, 1, preview.fee);

        IBurnerLoans.Position memory positionAfter = burnerLoans.getPosition(address(usds), alice);
        assertEq(positionAfter.debtOhm, positionBefore.debtOhm, "debt unchanged");
        assertEq(positionAfter.maturity, positionBefore.maturity, "maturity unchanged");
        assertEq(usds.balanceOf(caller), payerBefore, "payer balance unchanged");
        assertEq(
            usds.allowance(caller, address(burnerLoans)),
            allowanceBefore,
            "allowance unchanged"
        );
        assertEq(usds.balanceOf(recipient), recipientBefore, "recipient unchanged");
        assertEq(burnerLoans.totalPendingForTest(address(usds)), 0, "no pending reserve");
        assertEq(burnerLoans.getPendingPayoutTokens().length, 0, "no pending index");
    }

    // Scenarios: EXT-I01, EXT-I03, EXT-I04
    function test_givenRejectedFeeInput_extensionRollsBackEveryRouteAndCaller(
        uint8 failureMode_,
        bool sendFeesToDistributor_,
        bool useOperator_,
        uint128 maxFeeSeed_
    ) public {
        uint8 failureMode = uint8(bound(failureMode_, 0, 2));
        _borrowForAlice();
        address caller = alice;
        if (useOperator_) {
            caller = operator;
            _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));
            usds.mint(operator, 100e18);
            vm.prank(operator);
            usds.approve(address(burnerLoans), type(uint256).max);
        }
        address recipient = _configureFeeRecipientForTest(sendFeesToDistributor_, address(usds));
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        uint256 maxFee = preview.fee;
        bytes memory expectedError;
        if (failureMode == 0) {
            maxFee = bound(maxFeeSeed_, 0, preview.fee - 1);
            expectedError = abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_FeeExceedsMax.selector,
                preview.fee,
                maxFee
            );
        } else if (failureMode == 1) {
            vm.prank(caller);
            usds.approve(address(burnerLoans), 0);
            expectedError = abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(burnerLoans),
                0,
                preview.fee
            );
        } else {
            uint256 balance = usds.balanceOf(caller);
            usds.burn(caller, balance - (preview.fee - 1));
            expectedError = abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                caller,
                preview.fee - 1,
                preview.fee
            );
        }
        IBurnerLoans.Position memory positionBefore = burnerLoans.getPosition(address(usds), alice);
        uint256 payerBefore = usds.balanceOf(caller);
        uint256 allowanceBefore = usds.allowance(caller, address(burnerLoans));
        uint256 recipientBefore = usds.balanceOf(recipient);

        vm.prank(caller);
        vm.expectRevert(expectedError);
        burnerLoans.extend(address(usds), alice, 1, maxFee);

        IBurnerLoans.Position memory positionAfter = burnerLoans.getPosition(address(usds), alice);
        assertEq(positionAfter.debtOhm, positionBefore.debtOhm, "debt rolls back");
        assertEq(positionAfter.maturity, positionBefore.maturity, "maturity rolls back");
        assertEq(usds.balanceOf(caller), payerBefore, "payer balance rolls back");
        assertEq(
            usds.allowance(caller, address(burnerLoans)),
            allowanceBefore,
            "allowance rolls back"
        );
        assertEq(usds.balanceOf(recipient), recipientBefore, "recipient unchanged");
        assertEq(burnerLoans.totalPendingForTest(address(usds)), 0, "reserve rolls back");
        assertEq(burnerLoans.getPendingPayoutTokens().length, 0, "pending index rolls back");
        assertEq(
            burnerLoans.previewExtend(address(usds), alice, 1).fee,
            preview.fee,
            "preview remains available"
        );
    }

    // Scenarios: EXT-T02, EXT-T04
    function test_givenFeeDestinationRejects_extensionDefersCombinedFeeExactly(
        bool sendFeesToDistributor_,
        bool useOperator_,
        uint96 priorPendingSeed_
    ) public {
        _borrowForAlice();
        address caller = alice;
        if (useOperator_) {
            caller = operator;
            _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));
            usds.mint(operator, 100e18);
            vm.prank(operator);
            usds.approve(address(burnerLoans), type(uint256).max);
        }
        address recipient = _configureFeeRecipientForTest(sendFeesToDistributor_, address(usds));
        uint256 priorPending = bound(priorPendingSeed_, 0, 10e18);
        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, recipient),
            abi.encodeWithSignature("Error(string)", "blocked")
        );
        if (priorPending != 0) {
            burnerLoans.recordPendingFeeForTest(address(usds), alice, recipient, priorPending);
        }
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        uint48 maturityBefore = burnerLoans.getPosition(address(usds), alice).maturity;
        uint256 payerBefore = usds.balanceOf(caller);
        uint256 recipientBefore = usds.balanceOf(recipient);
        uint256 combinedFee = priorPending + preview.fee;
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.PayoutDeferred(
            address(usds),
            recipient,
            IBurnerLoans.PayoutKind.Fee,
            combinedFee
        );

        vm.prank(caller);
        burnerLoans.extend(address(usds), alice, 1, preview.fee);

        assertEq(payerBefore - usds.balanceOf(caller), preview.fee, "new fee collected exactly");
        assertEq(usds.balanceOf(recipient), recipientBefore, "recipient receives nothing");
        assertEq(
            burnerLoans.pendingPayout(address(usds), recipient),
            combinedFee,
            "combined fee remains owed"
        );
        assertEq(burnerLoans.totalPendingForTest(address(usds)), combinedFee, "reserve is exact");
        assertEq(usds.balanceOf(address(burnerLoans)), combinedFee, "custody is exact");
        assertEq(burnerLoans.getPendingPayoutTokens().length, 1, "token indexed once");
        address[] memory recipients = burnerLoans.getPendingPayoutRecipients(address(usds));
        assertEq(recipients.length, 1, "recipient indexed once");
        assertEq(recipients[0], recipient, "live recipient indexed");
        assertGt(
            burnerLoans.getPosition(address(usds), alice).maturity,
            maturityBefore,
            "extension remains committed"
        );
    }

    // Scenarios: EXT-N02
    function test_givenZeroConfiguredFee_extensionDoesNotTouchExistingFeeReserve(
        bool sendFeesToDistributor_,
        bool useOperator_,
        bool seedPendingFee_
    ) public {
        _borrowForAlice();
        address caller = alice;
        if (useOperator_) {
            caller = operator;
            _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));
        }

        address recipient = _configureFeeRecipientForTest(sendFeesToDistributor_, address(usds));

        uint256 pending = seedPendingFee_ ? 7 : 0;
        if (pending != 0) {
            vm.mockCallRevert(
                address(usds),
                abi.encodeWithSelector(usds.transfer.selector, recipient),
                abi.encodeWithSignature("Error(string)", "blocked")
            );
            burnerLoans.recordPendingFeeForTest(address(usds), alice, recipient, pending);
            vm.clearMockedCalls();
        }
        vm.prank(admin);
        burnerLoansConfig.setAssetFeeConfig(
            address(usds),
            IBurnerLoans.AssetFeeConfig({
                baseFeeBps: 0,
                kinkBps: 0,
                preKinkSlopeBps: 0,
                postKinkSlopeBps: 0
            })
        );
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        uint256 callerBefore = usds.balanceOf(caller);
        uint256 recipientBefore = usds.balanceOf(recipient);
        uint48 maturityBefore = burnerLoans.getPosition(address(usds), alice).maturity;

        vm.prank(caller);
        burnerLoans.extend(address(usds), alice, 1, 0);

        assertEq(preview.fee, 0, "preview fee is zero");
        assertEq(usds.balanceOf(caller), callerBefore, "no fee is collected");
        assertEq(usds.balanceOf(recipient), recipientBefore, "no fee is paid");
        assertEq(
            burnerLoans.pendingPayout(address(usds), recipient),
            pending,
            "existing fee remains untouched"
        );
        assertEq(burnerLoans.totalPendingForTest(address(usds)), pending, "reserve is unchanged");
        assertGt(
            burnerLoans.getPosition(address(usds), alice).maturity,
            maturityBefore,
            "extension still succeeds"
        );
    }

    // Scenarios: EXT-I02
    function test_givenInexactIncomingFee_extensionRevertsAndRollsBack(
        bool sendFeesToDistributor_,
        bool useOperator_
    ) public {
        _borrowForAlice();
        address caller = alice;
        if (useOperator_) {
            caller = operator;
            _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));
            usds.mint(operator, 100e18);
            vm.prank(operator);
            usds.approve(address(burnerLoans), type(uint256).max);
        }
        if (sendFeesToDistributor_) {
            _installFeeDistributorForTest(address(usds));
        }

        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        IBurnerLoans.Position memory positionBefore = burnerLoans.getPosition(address(usds), alice);
        uint256 payerBefore = usds.balanceOf(caller);
        uint256 allowanceBefore = usds.allowance(caller, address(burnerLoans));
        address feeRecipient = makeAddr("transfer fee recipient");
        MockERC20FeeOnTransfer implementation = new MockERC20FeeOnTransfer(
            "Fee token",
            "FEE",
            feeRecipient
        );
        vm.etch(address(usds), address(implementation).code);
        uint256 transferFee = (preview.fee * implementation.FEE()) /
            implementation.FEE_DENOMINATOR();

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(usds),
                address(burnerLoans),
                preview.fee,
                preview.fee - transferFee
            )
        );
        burnerLoans.extend(address(usds), alice, 1, preview.fee);

        IBurnerLoans.Position memory positionAfter = burnerLoans.getPosition(address(usds), alice);
        assertEq(positionAfter.debtOhm, positionBefore.debtOhm, "debt rolls back");
        assertEq(positionAfter.maturity, positionBefore.maturity, "maturity rolls back");
        assertEq(usds.balanceOf(caller), payerBefore, "payer balance rolls back");
        assertEq(
            usds.allowance(caller, address(burnerLoans)),
            allowanceBefore,
            "allowance rolls back"
        );
        assertEq(usds.balanceOf(feeRecipient), 0, "transfer fee rolls back");
        assertEq(burnerLoans.totalPendingForTest(address(usds)), 0, "no fee reserve remains");
    }

    // Scenarios: EXT-C01, EXT-C02, EXT-C03, EXT-C04
    function test_givenFeeTokenCallback_extensionHandlesIncomingAndOutgoingReentrancy(
        bool outgoingCallback_,
        bool bubbleFailure_,
        bool sendFeesToDistributor_,
        bool useOperator_
    ) public {
        _borrowForAlice();
        address caller = alice;
        if (useOperator_) {
            caller = operator;
            _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));
            usds.mint(operator, 100e18);
            vm.prank(operator);
            usds.approve(address(burnerLoans), type(uint256).max);
        }
        address recipient = _configureFeeRecipientForTest(sendFeesToDistributor_, address(usds));

        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        uint48 maturityBefore = burnerLoans.getPosition(address(usds), alice).maturity;
        uint256 payerBefore = usds.balanceOf(caller);
        uint256 recipientBefore = usds.balanceOf(recipient);
        ReentrantFeeToken implementation = new ReentrantFeeToken();
        vm.etch(address(usds), address(implementation).code);
        ReentrantFeeToken liveToken = ReentrantFeeToken(address(usds));
        liveToken.setCallbackFrom(
            address(burnerLoans),
            address(burnerLoans),
            abi.encodeCall(burnerLoans.transferPendingPayout, (address(usds), recipient))
        );
        liveToken.setCallbackPhases(outgoingCallback_, !outgoingCallback_);
        liveToken.setBubbleCallbackFailure(bubbleFailure_);

        if (!outgoingCallback_ && bubbleFailure_) {
            vm.prank(caller);
            vm.expectRevert(ReentrantFeeToken.CallbackFailed.selector);
            burnerLoans.extend(address(usds), alice, 1, preview.fee);
            assertEq(
                burnerLoans.getPosition(address(usds), alice).maturity,
                maturityBefore,
                "incoming callback failure rolls maturity back"
            );
            assertEq(usds.balanceOf(caller), payerBefore, "incoming fee rolls back");
            assertEq(usds.balanceOf(recipient), recipientBefore, "recipient stays unchanged");
            assertEq(
                burnerLoans.totalPendingForTest(address(usds)),
                0,
                "incoming failure creates no reserve"
            );
            return;
        }

        vm.prank(caller);
        burnerLoans.extend(address(usds), alice, 1, preview.fee);

        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            preview.maturity,
            "outer extension executes once"
        );
        assertEq(payerBefore - usds.balanceOf(caller), preview.fee, "fee collected once");
        if (outgoingCallback_ && bubbleFailure_) {
            assertEq(
                burnerLoans.pendingPayout(address(usds), recipient),
                preview.fee,
                "propagated outgoing callback defers the fee"
            );
            assertEq(usds.balanceOf(recipient), recipientBefore, "failed payout moves nothing");
        } else {
            assertFalse(liveToken.callbackSucceeded(), "nested guarded call is rejected");
            assertEq(
                liveToken.callbackRevertSelector(),
                ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
                "nested call reaches the shared guard"
            );
            assertEq(
                usds.balanceOf(recipient) - recipientBefore,
                preview.fee,
                "caught callback still pays once"
            );
            assertEq(
                burnerLoans.pendingPayout(address(usds), recipient),
                0,
                "caught callback leaves no debt"
            );
        }
    }

    // given sendFeesToDistributor is false
    //   when the borrower extends
    //     Treasury receives the fee immediately
    // Scenarios: EXT-P01
    function test_givenSendFeesToDistributorIsFalse_paysTreasury() public {
        _borrowForAlice();
        uint256 fee = burnerLoans.previewExtend(address(usds), alice, 1).fee;
        uint256 treasuryBefore = usds.balanceOf(address(trsry));

        vm.prank(alice);
        burnerLoans.extend(address(usds), alice, 1, fee);

        assertGt(fee, 0, "extension fee is positive");
        assertEq(usds.balanceOf(address(trsry)) - treasuryBefore, fee, "Treasury receives fee");
        assertEq(burnerLoans.pendingPayout(address(usds), address(trsry)), 0, "no fee is pending");
    }

    // given sendFeesToDistributor is false
    //   given the token transfer to Treasury reverts
    //     when the borrower extends
    //       [X] the extension succeeds with its fee pending
    // Scenarios: EXT-T02
    function test_givenSendFeesToDistributorIsFalse_whenTokenTransferReverts_recordsPendingFee()
        public
    {
        _borrowForAlice();
        uint256 fee = burnerLoans.previewExtend(address(usds), alice, 1).fee;
        uint256 maturityBefore = burnerLoans.getPosition(address(usds), alice).maturity;
        uint256 treasuryBefore = usds.balanceOf(address(trsry));
        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, address(trsry)),
            abi.encodeWithSignature("Error(string)", "blacklisted")
        );

        vm.prank(alice);
        burnerLoans.extend(address(usds), alice, 1, fee);

        assertEq(
            usds.balanceOf(address(trsry)),
            treasuryBefore,
            "rejected Treasury receives no fee"
        );
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(trsry)),
            fee,
            "fee remains pending"
        );
        assertGt(
            burnerLoans.getPosition(address(usds), alice).maturity,
            maturityBefore,
            "extension succeeds despite rejected fee transfer"
        );
    }

    // given sendFeesToDistributor is true
    //   given the distributor is active
    //     when the borrower extends
    //       [X] the distributor receives the fee immediately
    // Scenarios: EXT-P04
    function test_givenSendFeesToDistributorIsTrue_paysDistributor() public {
        _borrowForAlice();
        RevenueDistributor distributor = _installFeeDistributorForTest(address(usds));
        uint256 fee = burnerLoans.previewExtend(address(usds), alice, 1).fee;
        uint256 treasuryBefore = usds.balanceOf(address(trsry));

        vm.prank(alice);
        burnerLoans.extend(address(usds), alice, 1, fee);

        assertGt(fee, 0, "extension fee is positive");
        assertEq(usds.balanceOf(address(distributor)), fee, "distributor receives fee");
        assertEq(
            usds.balanceOf(address(trsry)),
            treasuryBefore,
            "Treasury receives no extension fee"
        );
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(distributor)),
            0,
            "no fee is pending"
        );
    }

    // given sendFeesToDistributor is true
    //   given the distributor is disabled
    //     when a positive-fee extension executes
    //       [X] the collateral fee reaches that distributor
    //       [X] Treasury's collateral balance is unchanged
    // Scenarios: EXT-L01
    function test_givenSendFeesToDistributorIsTrue_givenDistributorDisabled_paysDistributor()
        public
    {
        _borrowForAlice();
        RevenueDistributor distributor = _installFeeDistributorForTest(address(usds));
        vm.prank(admin);
        distributor.disable("");

        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        uint256 treasuryBefore = usds.balanceOf(address(trsry));
        vm.prank(alice);
        burnerLoans.extend(address(usds), alice, 1, preview.fee);

        assertGt(preview.fee, 0, "extension charges positive fee");
        assertEq(
            usds.balanceOf(address(distributor)),
            preview.fee,
            "disabled distributor receives extension fee"
        );
        assertEq(
            usds.balanceOf(address(trsry)),
            treasuryBefore,
            "Treasury receives no extension fee"
        );
    }

    // given sendFeesToDistributor is true
    //   given the distributor is Kernel-inactive
    //     when a positive-fee extension executes
    //       [X] the collateral fee reaches that distributor
    //       [X] Treasury's collateral balance is unchanged
    // Scenarios: EXT-L02
    function test_givenSendFeesToDistributorIsTrue_givenDistributorKernelInactive_paysDistributor()
        public
    {
        _borrowForAlice();
        RevenueDistributor distributor = _installFeeDistributorForTest(address(usds));
        _deactivatePolicy(address(distributor));

        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        uint256 treasuryBefore = usds.balanceOf(address(trsry));
        vm.prank(alice);
        burnerLoans.extend(address(usds), alice, 1, preview.fee);

        assertGt(preview.fee, 0, "extension charges positive fee");
        assertEq(
            usds.balanceOf(address(distributor)),
            preview.fee,
            "inactive distributor receives extension fee"
        );
        assertEq(
            usds.balanceOf(address(trsry)),
            treasuryBefore,
            "Treasury receives no extension fee"
        );
    }

    // given sendFeesToDistributor is true
    //   given the token transfer to the distributor reverts
    //     when the borrower pays the exact fee and extends
    //       [X] the extension succeeds and the fee remains pending
    // Scenarios: EXT-T04
    function test_givenSendFeesToDistributorIsTrue_whenTokenTransferReverts_recordsPendingFee()
        public
    {
        _borrowForAlice();
        RevenueDistributor distributor = _installFeeDistributorForTest(address(usds));
        uint256 fee = burnerLoans.previewExtend(address(usds), alice, 1).fee;
        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, address(distributor)),
            abi.encodeWithSignature("Error(string)", "blacklisted")
        );

        vm.prank(alice);
        burnerLoans.extend(address(usds), alice, 1, fee);
        assertEq(usds.balanceOf(address(burnerLoans)), fee, "fee is retained");
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(distributor)),
            fee,
            "extension fee remains owed"
        );
        assertEq(usds.balanceOf(address(distributor)), 0, "rejected distributor receives nothing");
        assertGt(
            burnerLoans.getPosition(address(usds), alice).maturity,
            block.timestamp,
            "extension remains effective"
        );
    }

    // Condition tree:
    // - Market schema: incompatible config ID with malformed data
    // - Action: preview and execute extension
    // - Expected branch: both reject the schema before position or fee handling
    function test_givenDifferentConfigId_previewAndExtendRevertBeforeDecoding() public {
        bytes16 incompatibleConfigId = bytes16("Different config");
        uint32 marketId = _replaceMarketConfigForTest(address(usds), incompatibleConfigId, hex"01");
        _setActivePositionForSchemaTest();
        bytes memory expectedError = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_IncompatibleMarketConfig.selector,
            marketId,
            incompatibleConfigId
        );

        vm.expectRevert(expectedError);
        burnerLoans.previewExtend(address(usds), alice, 1);

        vm.prank(alice);
        vm.expectRevert(expectedError);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // Condition tree:
    // - Market schema: compatible config ID with malformed data length
    // - Action: preview and execute extension
    // - Expected branch: both reject the byte length before position or fee handling
    function test_givenInvalidConfigDataLength_previewAndExtendRevertBeforeDecoding() public {
        uint32 marketId = _replaceMarketConfigForTest(
            address(usds),
            bytes16("Burner Loans v1"),
            hex"01"
        );
        _setActivePositionForSchemaTest();
        bytes memory expectedError = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_InvalidMarketConfigData.selector,
            marketId,
            1
        );

        vm.expectRevert(expectedError);
        burnerLoans.previewExtend(address(usds), alice, 1);

        vm.prank(alice);
        vm.expectRevert(expectedError);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    function _setActivePositionForSchemaTest() internal {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: 2_000e18,
                debtOhm: 100e9,
                maturity: uint48(block.timestamp + 30 days),
                lastBorrowBlock: 0
            })
        );
    }

    // extend
    // given an active position whose collateral vault has fallen below borrower liabilities
    //  when previewing or executing an extension
    //   then the asset-level custody shortfall blocks the extension
    function test_givenCustodyShortfall_reverts() public {
        (MockERC20 asset, MockERC4626 vault) = _addVaultAssetForTest();
        uint128 collateral = 2_000e18;
        asset.mint(alice, collateral + 100e18);
        vm.startPrank(alice);
        asset.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(asset), collateral, alice);
        IBurnerLoans.BorrowPreview memory borrowPreview = burnerLoans.previewBorrow(
            address(asset),
            100e9,
            alice
        );
        burnerLoans.borrow(address(asset), 100e9, alice, alice, borrowPreview.fee);
        vm.stopPrank();
        asset.burn(address(vault), 1);

        bytes memory expectedError = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_CustodyShortfall.selector,
            address(asset),
            collateral,
            collateral - 1,
            0
        );
        vm.expectRevert(expectedError);
        burnerLoans.previewExtend(address(asset), alice, 1);

        vm.prank(alice);
        vm.expectRevert(expectedError);
        burnerLoans.extend(address(asset), alice, 1, type(uint256).max);
    }

    // extend
    // given healthy active position
    //  when extend is called
    //   then it adds one term and charges collateral fee
    function test_givenHealthyActivePosition_extendAddsOneTermAndChargesCollateralFee() public {
        _borrowForAlice();
        IBurnerLoans.Position memory beforePosition = burnerLoans.getPosition(address(usds), alice);
        uint256 healthBefore = burnerLoans.positionHealthFactor(
            address(usds),
            beforePosition.depositedCollateral,
            beforePosition.debtOhm
        );
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        // Required collateral = ceil($1,000e18 * 10,000 / 8,500)
        //                     = 1_176.470588235294117648e18 USDS.
        // Pre-extension utilization = 100 OHM / 100,000 OHM = 0.001e18 WAD.
        // Fee rate = 25 bps + floor(0.001e18 * 100 bps / 0.8e18)
        //          = 0.0025125e18 WAD.
        // Fee = ceil(1_176.470588235294117648e18 * 0.0025125e18 / 1e18)
        //     = 2.955882352941176471e18 USDS.
        assertEq(preview.fee, 2_955_882_352_941_176_471, "preview fee");
        assertEq(preview.maturity, beforePosition.maturity + 30 days, "preview maturity");
        assertEq(preview.healthFactor, healthBefore, "preview preserves health");
        assertTrue(preview.executable, "preview executable");
        uint256 treasuryBefore = usds.balanceOf(address(trsry));

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.Extended(alice, address(usds), alice, preview.maturity, preview.fee);
        vm.prank(alice);
        (uint256 fee, uint48 maturity, uint256 health) = burnerLoans.extend(
            address(usds),
            alice,
            1,
            preview.fee
        );

        IBurnerLoans.Position memory afterPosition = burnerLoans.getPosition(address(usds), alice);
        assertEq(fee, preview.fee, "fee");
        assertEq(maturity, beforePosition.maturity + 30 days, "maturity");
        assertEq(afterPosition.maturity, maturity, "position maturity");
        assertEq(health, preview.healthFactor, "health");
        assertEq(usds.balanceOf(address(trsry)), treasuryBefore + fee, "treasury fee");
        assertEq(afterPosition.debtOhm, beforePosition.debtOhm, "debt");
        assertEq(
            afterPosition.depositedCollateral,
            beforePosition.depositedCollateral,
            "collateral"
        );
        assertEq(afterPosition.lastBorrowBlock, beforePosition.lastBorrowBlock, "borrow block");
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 1, "active borrowers");
        _assertFloanPositionMatchesBurnerLoans(address(usds), alice);
    }

    // extend
    // given two terms
    //  when extend is called
    //   then it charges twice single term fee
    function test_givenTwoTerms_extendChargesTwiceSingleTermFee() public {
        _borrowForAlice();
        IBurnerLoans.ExtendPreview memory single = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        IBurnerLoans.ExtendPreview memory doubleTerm = burnerLoans.previewExtend(
            address(usds),
            alice,
            2
        );
        assertEq(doubleTerm.fee, single.fee * 2, "linear extension fee");

        vm.prank(alice);
        burnerLoans.extend(address(usds), alice, 2, doubleTerm.fee);
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            uint48(block.timestamp + 90 days),
            "maturity"
        );
    }

    // extend
    // given authorized operator
    //  when extend is called
    //   then it succeeds and operator pays fee
    function test_givenAuthorizedOperator_extendSucceedsAndOperatorPaysFee() public {
        _borrowForAlice();
        _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        usds.mint(operator, preview.fee);
        vm.prank(operator);
        usds.approve(address(burnerLoans), preview.fee);

        vm.prank(operator);
        (, uint48 maturity, ) = burnerLoans.extend(address(usds), alice, 1, preview.fee);
        assertEq(usds.balanceOf(operator), 0, "operator paid fee");
        assertEq(maturity, preview.maturity, "returned maturity");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            preview.maturity,
            "position maturity"
        );
    }

    // extend
    // given unauthorized caller
    //  when extend is called
    //   then it reverts
    function test_givenUnauthorizedCaller_extendReverts() public {
        _borrowForAlice();

        vm.prank(operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // extend
    // given unauthorized caller
    //  when extend is called
    //   then it reverts
    function test_givenUnauthorizedCaller_extendReverts(address caller_) public {
        vm.assume(caller_ != alice);
        _borrowForAlice();

        vm.prank(caller_);
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // extend
    // given expired authorization
    //  when extend is called
    //   then it reverts
    function test_givenExpiredAuthorization_extendReverts() public {
        _borrowForAlice();
        _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp));
        vm.warp(block.timestamp + 1);

        vm.prank(operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // extend
    // given zero term count
    //  when extend is called
    //   then it reverts
    function test_givenZeroTermCount_extendReverts() public {
        _borrowForAlice();

        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAmount.selector);
        burnerLoans.previewExtend(address(usds), alice, 0);

        vm.prank(alice);
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAmount.selector);
        burnerLoans.extend(address(usds), alice, 0, type(uint256).max);
    }

    // extend
    // given extension beyond horizon
    //  when extend is called
    //   then it reverts
    function test_givenExtensionBeyondHorizon_extendReverts() public {
        _borrowForAlice();
        bytes memory revertData = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_MaturityHorizonExceeded.selector,
            block.timestamp + 120 days,
            block.timestamp + 90 days
        );

        vm.expectRevert(revertData);
        burnerLoans.previewExtend(address(usds), alice, 3);

        vm.prank(alice);
        vm.expectRevert(revertData);
        burnerLoans.extend(address(usds), alice, 3, type(uint256).max);
    }

    // extend
    // given active position
    //  when extend is called
    //   then it succeeds within the maturity horizon
    function test_givenActivePosition_extendWithinHorizonSucceeds(
        uint16 termCount_,
        uint32 elapsed_
    ) public {
        uint16 termCount = uint16(bound(termCount_, 1, 2));
        uint256 elapsed = bound(elapsed_, 0, 30 days - 1);
        _borrowForAlice();
        uint48 originalMaturity = burnerLoans.getPosition(address(usds), alice).maturity;
        vm.warp(block.timestamp + elapsed);
        price.setTimestamp(uint48(block.timestamp));
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            termCount
        );

        vm.prank(alice);
        (, uint48 maturity, uint256 healthFactor) = burnerLoans.extend(
            address(usds),
            alice,
            termCount,
            preview.fee
        );

        assertEq(
            preview.maturity,
            originalMaturity + uint48(30 days * termCount),
            "preview maturity"
        );
        assertEq(maturity, preview.maturity, "returned maturity");
        assertEq(healthFactor, preview.healthFactor, "returned health");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            preview.maturity,
            "fuzzed maturity"
        );
    }

    // extend
    // given extension above horizon
    //  when extend is called
    //   then it reverts
    function test_givenExtensionAboveHorizon_extendReverts(
        uint16 termCount_,
        uint32 elapsed_
    ) public {
        uint16 termCount = uint16(bound(termCount_, 3, type(uint16).max));
        uint256 elapsed = bound(elapsed_, 0, 30 days - 1);
        _borrowForAlice();
        uint48 originalMaturity = burnerLoans.getPosition(address(usds), alice).maturity;
        vm.warp(block.timestamp + elapsed);
        price.setTimestamp(uint48(block.timestamp));
        uint256 requested = originalMaturity + uint256(30 days) * termCount;
        uint256 maximum = block.timestamp + 90 days;

        bytes memory revertData = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_MaturityHorizonExceeded.selector,
            requested,
            maximum
        );

        vm.expectRevert(revertData);
        burnerLoans.previewExtend(address(usds), alice, termCount);

        vm.prank(alice);
        vm.expectRevert(revertData);
        burnerLoans.extend(address(usds), alice, termCount, type(uint256).max);
    }

    // extend
    // given extension at exact horizon
    //  when extend is called
    //   then it succeeds
    function test_givenExtensionAtExactHorizon_extendSucceeds() public {
        _borrowForAlice();
        vm.warp(block.timestamp + 30 days);
        price.setTimestamp(uint48(block.timestamp));
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            3
        );

        vm.prank(alice);
        (, uint48 maturity, ) = burnerLoans.extend(address(usds), alice, 3, preview.fee);
        assertEq(preview.maturity, block.timestamp + 90 days, "exact horizon");
        assertEq(maturity, preview.maturity, "returned maturity");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            preview.maturity,
            "position maturity"
        );
    }

    // extend
    // given updated term length
    //  when extend is called
    //   then it uses new term without changing existing maturity
    function test_givenUpdatedTermLength_extendUsesNewTermWithoutChangingExistingMaturity(
        uint32 termLength_
    ) public {
        uint48 termLength = uint48(bound(termLength_, 1 days, 29 days));
        _borrowForAlice();
        uint48 originalMaturity = burnerLoans.getPosition(address(usds), alice).maturity;
        IBurnerLoans.AssetRiskConfigInput memory riskConfig = _defaultAssetRiskConfigInput();
        riskConfig.termLength = termLength;
        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(usds), riskConfig);
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            originalMaturity,
            "configuration does not mutate maturity"
        );
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );

        vm.prank(alice);
        (, uint48 maturity, ) = burnerLoans.extend(address(usds), alice, 1, preview.fee);
        assertEq(preview.maturity, originalMaturity + termLength, "new term length");
        assertEq(maturity, preview.maturity, "returned maturity");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            preview.maturity,
            "position maturity"
        );
    }

    // Condition tree:
    // - Debt episode: active position receives an additional borrow after shorter terms are set
    // - Time: extension becomes available at the exact updated horizon
    // - Expected branch: borrow preserves maturity; extension rolls the aggregate debt by the new term
    function test_givenUpdatedTermsAndAdditionalBorrow_whenExtend_appliesToAggregateDebt() public {
        _borrowForAlice();
        IBurnerLoans.Position memory originalPosition = burnerLoans.getPosition(
            address(usds),
            alice
        );
        IBurnerLoans.AssetRiskConfigInput memory riskConfig = _defaultAssetRiskConfigInput();
        riskConfig.termLength = 15 days;
        riskConfig.maxMaturityHorizon = 30 days;
        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(usds), riskConfig);

        IBurnerLoans.BorrowPreview memory borrowPreview = burnerLoans.previewBorrow(
            address(usds),
            1e9,
            alice
        );
        vm.prank(alice);
        burnerLoans.borrow(address(usds), 1e9, alice, alice, borrowPreview.fee);

        IBurnerLoans.Position memory afterBorrow = burnerLoans.getPosition(address(usds), alice);
        assertEq(afterBorrow.debtOhm, originalPosition.debtOhm + 1e9, "aggregate debt");
        assertEq(afterBorrow.maturity, originalPosition.maturity, "borrow preserves maturity");

        uint256 requestedMaturity = uint256(originalPosition.maturity) + 15 days;
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_MaturityHorizonExceeded.selector,
                requestedMaturity,
                block.timestamp + 30 days
            )
        );
        burnerLoans.previewExtend(address(usds), alice, 1);

        vm.warp(block.timestamp + 15 days);
        price.setTimestamp(uint48(block.timestamp));
        IBurnerLoans.ExtendPreview memory extendPreview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        vm.prank(alice);
        burnerLoans.extend(address(usds), alice, 1, extendPreview.fee);

        IBurnerLoans.Position memory afterExtension = burnerLoans.getPosition(address(usds), alice);
        assertEq(afterExtension.debtOhm, afterBorrow.debtOhm, "extension preserves aggregate debt");
        assertEq(
            afterExtension.maturity,
            originalPosition.maturity + 15 days,
            "current term extends aggregate debt"
        );
    }

    // extend
    // given unhealthy position
    //  when extension is previewed or executed
    //   then preview returns the health and execution reverts
    function test_givenUnhealthyPosition_whenExtensionIsPreviewedOrExecuted() public {
        backingOracle.setBacking(10e18);
        _borrowForAlice();
        price.setPrice(address(usds), 0.1e18);
        // Launch parameters: maxLtvBps = 8,500 and backingMultiplierBps = 12,500.
        // Debt = 100e9 OHM (9 decimals); backing = $10e18 per OHM (18 decimals).
        // Backing debt value = 100e9 * $10e18 / 1e9 = $1,000e18.
        // Backing requirement = $1,000e18 * 12,500 / 10,000 = $1,250e18.
        // OHM market price is $10e18, below the $10.625e18 crossover, so backing dominates.
        // Collateral value after the depeg = 2,000e18 * $0.1e18 / 1e18 = $200e18.
        // Health = floor($200e18 * 1e18 / $1,250e18) = 0.16e18 WAD.
        uint256 expectedHealthFactor = 0.16e18;
        bytes memory revertData = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_UnhealthyPosition.selector,
            expectedHealthFactor
        );

        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        assertEq(preview.healthFactor, expectedHealthFactor, "preview health");
        assertFalse(preview.executable, "preview executable");

        vm.prank(alice);
        vm.expectRevert(revertData);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // extend
    // given a healthy position that matured less than one term ago
    //  when extend is called
    //   then it adds the term to the previous maturity
    function test_givenMaturedHealthyPosition_extendUsesPreviousMaturityAsBase(
        uint48 elapsed_
    ) public {
        _borrowForAlice();
        uint48 previousMaturity = burnerLoans.getPosition(address(usds), alice).maturity;
        uint48 elapsed = uint48(bound(elapsed_, 30 days, 60 days - 1));
        vm.warp(block.timestamp + elapsed);
        price.setTimestamp(uint48(block.timestamp));
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );

        vm.prank(alice);
        (, uint48 maturity, ) = burnerLoans.extend(address(usds), alice, 1, preview.fee);

        uint48 expectedMaturity = previousMaturity + 30 days;
        assertEq(preview.maturity, expectedMaturity, "preview maturity");
        assertEq(maturity, expectedMaturity, "returned maturity");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            expectedMaturity,
            "position maturity"
        );
    }

    // extend
    // given a healthy position whose one-term extension would remain matured
    //  when previewing or executing one term
    //   then both reject the insufficient catch-up extension
    function test_givenExtensionDoesNotAdvanceMaturityBeyondCurrentTimestamp_reverts(
        uint48 elapsed_
    ) public {
        _borrowForAlice();
        uint48 previousMaturity = burnerLoans.getPosition(address(usds), alice).maturity;
        uint48 elapsed = uint48(bound(elapsed_, 60 days, 365 days));
        vm.warp(block.timestamp + elapsed);
        price.setTimestamp(uint48(block.timestamp));
        uint256 requestedMaturity = uint256(previousMaturity) + 30 days;
        bytes memory revertData = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_ExtensionMaturityNotFuture.selector,
            requestedMaturity,
            block.timestamp
        );

        vm.expectRevert(revertData);
        burnerLoans.previewExtend(address(usds), alice, 1);

        vm.prank(alice);
        vm.expectRevert(revertData);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // extend
    // given originations disabled
    //  when extend is called
    //   then it reverts
    // Scenarios: EXT-L06
    function test_givenAssetOriginationsDisabled_extendReverts() public {
        _borrowForAlice();
        _setAssetOriginationsEnabled(address(usds), false);
        bytes memory revertData = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_AssetOriginationsDisabled.selector,
            address(usds)
        );

        vm.expectRevert(revertData);
        burnerLoans.previewExtend(address(usds), alice, 1);

        vm.prank(alice);
        vm.expectRevert(revertData);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // extend
    // given global policy disabled
    //  when extend is called
    //   then it reverts
    // Scenarios: EXT-L04
    function test_givenGlobalPolicyDisabled_extendReverts() public {
        _borrowForAlice();
        _disableBurnerLoans(emergency);

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewExtend(address(usds), alice, 1);

        vm.prank(alice);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // Scenarios: EXT-L05
    function test_givenPolicyInactive_whenExtendIsPreviewedOrExecuted_reverts(
        bool sendFeesToDistributor_,
        bool useOperator_
    ) public {
        _borrowForAlice();
        address caller = alice;
        if (useOperator_) {
            caller = operator;
            _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));
            usds.mint(operator, 100e18);
            vm.prank(operator);
            usds.approve(address(burnerLoans), type(uint256).max);
        }

        address feeRecipient = _configureFeeRecipientForTest(sendFeesToDistributor_, address(usds));

        uint256 maxFee = burnerLoans.previewExtend(address(usds), alice, 1).fee;
        IBurnerLoans.Position memory positionBefore = burnerLoans.getPosition(address(usds), alice);
        uint256 payerBalanceBefore = usds.balanceOf(caller);
        uint256 payerAllowanceBefore = usds.allowance(caller, address(burnerLoans));
        uint256 recipientBalanceBefore = usds.balanceOf(feeRecipient);

        _deactivatePolicy(address(burnerLoans));
        bytes memory revertData = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_PolicyInactive.selector
        );

        vm.expectRevert(revertData);
        burnerLoans.previewExtend(address(usds), alice, 1);

        vm.prank(caller);
        vm.expectRevert(revertData);
        burnerLoans.extend(address(usds), alice, 1, maxFee);

        IBurnerLoans.Position memory positionAfter = burnerLoans.getPosition(address(usds), alice);
        assertEq(positionAfter.debtOhm, positionBefore.debtOhm, "debt unchanged");
        assertEq(positionAfter.maturity, positionBefore.maturity, "maturity unchanged");
        assertEq(usds.balanceOf(caller), payerBalanceBefore, "fee payer balance unchanged");
        assertEq(
            usds.allowance(caller, address(burnerLoans)),
            payerAllowanceBefore,
            "fee payer allowance unchanged"
        );
        assertEq(usds.balanceOf(feeRecipient), recipientBalanceBefore, "recipient unchanged");
        assertEq(burnerLoans.totalPendingForTest(address(usds)), 0, "no pending fee");
    }

    // Scenarios: EXT-L07
    function test_givenDisabledAndPolicyInactive_extendAndPreviewUseLocalGuard() public {
        _borrowForAlice();
        _disableBurnerLoans(emergency);
        _deactivatePolicy(address(burnerLoans));

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewExtend(address(usds), alice, 1);

        vm.prank(alice);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // extend
    // given stale price
    //  when extend is called
    //   then it reverts
    function test_givenStalePrice_extendReverts() public {
        _borrowForAlice();
        vm.warp(block.timestamp + 1 days);
        price.setTimestamp(uint48(block.timestamp - 9 hours));

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.previewExtend(address(usds), alice, 1);

        vm.prank(alice);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // extend
    // given unavailable price
    //  when extend is called
    //   then it reverts
    function test_givenUnavailablePrice_extendReverts() public {
        _borrowForAlice();
        price.setPrice(address(usds), 0);
        bytes memory revertData = abi.encodeWithSelector(
            IPRICEv2.PRICE_PriceZero.selector,
            address(usds)
        );

        vm.expectRevert(revertData);
        burnerLoans.previewExtend(address(usds), alice, 1);

        vm.prank(alice);
        vm.expectRevert(revertData);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
    }

    // extend
    // given no debt
    //  when extend is called
    //   then it reverts
    function test_givenNoDebt_extendReverts() public {
        usds.mint(alice, 1e18);
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), 1e18, alice);

        vm.expectRevert(IBurnerLoans.BurnerLoans_NoDebt.selector);
        burnerLoans.previewExtend(address(usds), alice, 1);

        vm.expectRevert(IBurnerLoans.BurnerLoans_NoDebt.selector);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);
        vm.stopPrank();
    }

    // extend
    // given fee above max
    //  when extend is called
    //   then it reverts without maturity change
    // Scenarios: EXT-I03
    function test_givenFeeAboveMax_extendRevertsWithoutMaturityChange() public {
        _borrowForAlice();
        IBurnerLoans.Position memory beforePosition = burnerLoans.getPosition(address(usds), alice);
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_FeeExceedsMax.selector,
                preview.fee,
                preview.fee - 1
            )
        );
        burnerLoans.extend(address(usds), alice, 1, preview.fee - 1);
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            beforePosition.maturity,
            "maturity"
        );
    }

    // extend
    // given missing fee allowance
    //  when extend is called
    //   then it reverts without maturity change
    // Scenarios: EXT-I01
    function test_givenMissingFeeAllowance_extendRevertsWithoutMaturityChange() public {
        _borrowForAlice();
        IBurnerLoans.Position memory beforePosition = burnerLoans.getPosition(address(usds), alice);
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        vm.prank(alice);
        usds.approve(address(burnerLoans), 0);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(burnerLoans),
                0,
                preview.fee
            )
        );
        burnerLoans.extend(address(usds), alice, 1, preview.fee);
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            beforePosition.maturity,
            "maturity"
        );
    }

    // extend
    // given missing fee balance
    //  when extend is called
    //   then it reverts without maturity change
    // Scenarios: EXT-I04
    function test_givenMissingFeeBalance_extendRevertsWithoutMaturityChange() public {
        _borrowForAlice();
        IBurnerLoans.Position memory beforePosition = burnerLoans.getPosition(address(usds), alice);
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        uint256 aliceBalance = usds.balanceOf(alice);
        vm.prank(alice);
        SafeERC20.safeTransfer(IERC20(address(usds)), operator, aliceBalance);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                alice,
                0,
                preview.fee
            )
        );
        burnerLoans.extend(address(usds), alice, 1, preview.fee);
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            beforePosition.maturity,
            "maturity"
        );
    }

    function _borrowForAlice() internal {
        usds.mint(alice, 2_100e18);
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), 2_000e18, alice);
        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            100e9,
            alice
        );
        burnerLoans.borrow(address(usds), 100e9, alice, alice, preview.fee);
        vm.stopPrank();
    }

    // extend
    // given multiple markets for the facility and token pair
    //  when extension is previewed and executed
    //   then Burner Loans uses the first market
    function test_givenMultipleMarkets_previewAndExtendUseFirstMarket() public {
        _borrowForAlice();
        uint32 firstMarketId = burnerLoansConfig.marketId(address(usds));
        uint48 previousMaturity = burnerLoans.getPosition(address(usds), alice).maturity;
        uint32 secondMarketId = _createDuplicateUsdsMarketForTest();

        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        vm.prank(alice);
        burnerLoans.extend(address(usds), alice, 1, preview.fee);

        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            previousMaturity + 30 days,
            "first-market maturity"
        );
        assertEq(floan.getMarketPrincipalDue(firstMarketId), 100e9, "first-market debt");
        assertEq(floan.getMarketPrincipalDue(secondMarketId), 0, "second-market debt");
    }

    // extend
    // given missing market
    //  when extension is previewed and executed
    //   then both revert
    function test_givenMissingMarket_previewAndExtendRevert() public {
        address unknownAsset = makeAddr("unknown asset");
        bytes memory revertData = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
            unknownAsset
        );

        vm.expectRevert(revertData);
        burnerLoans.previewExtend(unknownAsset, alice, 1);

        vm.prank(alice);
        vm.expectRevert(revertData);
        burnerLoans.extend(unknownAsset, alice, 1, type(uint256).max);
    }
}

// forge-lint: disable-end(unused-return,unsafe-typecast)

// forge-lint: disable-end(literal-instead-of-constant)
