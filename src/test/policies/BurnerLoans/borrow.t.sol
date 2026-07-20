// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ReentrancyGuardTransient} from "@openzeppelin-5.3.0/utils/ReentrancyGuardTransient.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";

import {Actions} from "src/Kernel.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

import {BurnerLoansBorrowTestBase} from "./fixtures/BurnerLoansBorrowTestBase.sol";
import {CallbackMinter} from "./fixtures/CallbackMinter.sol";
import {ReentrantFeeToken} from "./fixtures/ReentrantFeeToken.sol";

contract BurnerLoansBorrowTest is BurnerLoansBorrowTestBase {
    event Borrowed(
        address indexed caller,
        address indexed asset,
        address indexed onBehalfOf,
        address recipient,
        uint256 ohmAmount,
        uint256 fee
    );

    address internal operator;
    uint128 internal constant DEFAULT_BORROW_AMOUNT = 100e9;
    uint128 internal constant DEFAULT_COLLATERAL_AMOUNT = 2_000e18;

    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function setUp() public override {
        super.setUp();
        operator = makeAddr("operator");
    }

    function _depositDefaultCollateral(address account_) internal {
        usds.mint(account_, DEFAULT_COLLATERAL_AMOUNT + 100e18);

        vm.startPrank(account_);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), DEFAULT_COLLATERAL_AMOUNT, account_);
        vm.stopPrank();
    }

    function _depositCollateral(address account_, uint128 collateralAmount_) internal {
        usds.mint(account_, collateralAmount_ + 100e18);

        vm.startPrank(account_);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), collateralAmount_, account_);
        vm.stopPrank();
    }

    function _addAssetAndDepositCollateral(
        MockERC20 asset_,
        address account_,
        uint128 collateralAmount_
    ) internal {
        _configurePrice(address(asset_), 1e18);
        _configureDepositManagerAsset(address(asset_));
        vm.prank(admin);
        burnerLoans.addAsset(
            address(asset_),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );

        asset_.mint(account_, collateralAmount_ + 100e18);
        vm.startPrank(account_);
        asset_.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(asset_), collateralAmount_, account_);
        vm.stopPrank();
    }

    function _setBackingMultiplier(uint256 backingMultiplierBps_) internal {
        IBurnerLoans.AssetRiskConfigInput memory config = _defaultAssetRiskConfigInput();
        config.backingMultiplierBps = uint16(backingMultiplierBps_);

        vm.prank(admin);
        burnerLoans.setAssetRiskConfig(address(usds), config);
    }

    // given a configured collateral vault has lost one unit below borrower liabilities
    //  when previewing or executing a new borrow
    //   then the asset-level custody shortfall blocks new exposure
    function test_givenCustodyShortfall_reverts() public {
        (MockERC20 asset, MockERC4626 vault) = _addVaultAssetForTest();
        uint128 collateral = 2_000e18;
        asset.mint(alice, collateral);
        vm.startPrank(alice);
        asset.approve(address(burnerLoans), collateral);
        burnerLoans.depositCollateral(address(asset), collateral, alice);
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
        burnerLoans.previewBorrow(address(asset), 1e9, alice);

        vm.prank(alice);
        vm.expectRevert(expectedError);
        burnerLoans.borrow(address(asset), 1e9, alice, alice, type(uint256).max);
    }

    function _borrowWithPreview(
        address caller_,
        address onBehalfOf_,
        address recipient_,
        uint128 ohmAmount_
    ) internal returns (IBurnerLoans.BorrowPreview memory preview) {
        preview = burnerLoans.previewBorrow(address(usds), ohmAmount_, onBehalfOf_);

        vm.prank(caller_);
        (
            uint256 borrowedOhm,
            uint256 feeCollateral,
            uint256 totalDebtOhm,
            uint48 maturity,
            uint256 healthFactor
        ) = burnerLoans.borrow(address(usds), ohmAmount_, onBehalfOf_, recipient_, preview.fee);

        assertEq(borrowedOhm, ohmAmount_, "preview borrowed OHM");
        assertEq(feeCollateral, preview.fee, "preview fee");
        assertEq(totalDebtOhm, preview.resultingDebtOhm, "preview debt");
        assertEq(maturity, preview.maturity, "preview maturity");
        assertEq(healthFactor, preview.resultingHealthFactor, "preview health");
        assertTrue(preview.executable, "preview executable");
    }

    function _borrowAssetWithPreview(
        address asset_,
        address borrower_,
        uint128 ohmAmount_
    ) internal returns (IBurnerLoans.BorrowPreview memory preview) {
        preview = burnerLoans.previewBorrow(asset_, ohmAmount_, borrower_);

        vm.prank(borrower_);
        (
            uint256 borrowedOhm,
            uint256 feeCollateral,
            uint256 totalDebtOhm,
            uint48 maturity,
            uint256 healthFactor
        ) = burnerLoans.borrow(asset_, ohmAmount_, borrower_, borrower_, preview.fee);

        assertEq(borrowedOhm, ohmAmount_, "preview borrowed OHM");
        assertEq(feeCollateral, preview.fee, "preview fee");
        assertEq(totalDebtOhm, preview.resultingDebtOhm, "preview debt");
        assertEq(maturity, preview.maturity, "preview maturity");
        assertEq(healthFactor, preview.resultingHealthFactor, "preview health");
        assertTrue(preview.executable, "preview executable");
    }

    function _expectBorrowAndPreviewRevert(bytes memory error_, uint128 ohmAmount_) internal {
        vm.expectRevert(error_);
        burnerLoans.previewBorrow(address(usds), ohmAmount_, alice);

        vm.prank(alice);
        vm.expectRevert(error_);
        burnerLoans.borrow(address(usds), ohmAmount_, alice, alice, type(uint256).max);
    }

    function _expectBorrowAndPreviewPartialRevert(bytes4 selector_, uint128 ohmAmount_) internal {
        vm.expectPartialRevert(selector_);
        burnerLoans.previewBorrow(address(usds), ohmAmount_, alice);

        vm.prank(alice);
        vm.expectPartialRevert(selector_);
        burnerLoans.borrow(address(usds), ohmAmount_, alice, alice, type(uint256).max);
    }

    // Condition tree:
    // - Debt episode: first borrow
    // - Caller: owner
    // - Collateral: sufficient existing credited collateral
    // - Fee: exact previewed fee approved and available
    // - Expected branch: preview and write agree; debt, maturity, index, fee, and mint update
    function test_givenFirstBorrow_borrowCreatesDebtEpisodeAndMatchesPreview() public {
        _depositDefaultCollateral(alice);

        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            DEFAULT_BORROW_AMOUNT,
            alice
        );
        uint256 treasuryBalanceBefore = usds.balanceOf(address(trsry));
        uint256 recipientBalanceBefore = ohm.balanceOf(alice);

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit Borrowed(alice, address(usds), alice, alice, DEFAULT_BORROW_AMOUNT, preview.fee);
        vm.prank(alice);
        (
            uint256 borrowedOhm,
            uint256 feeCollateral,
            uint256 totalDebtOhm,
            uint48 maturity,
            uint256 healthFactor
        ) = burnerLoans.borrow(address(usds), DEFAULT_BORROW_AMOUNT, alice, alice, preview.fee);

        assertEq(borrowedOhm, DEFAULT_BORROW_AMOUNT, "borrowed OHM");
        assertEq(feeCollateral, preview.fee, "preview fee");
        assertEq(totalDebtOhm, preview.resultingDebtOhm, "preview debt");
        assertEq(maturity, preview.maturity, "preview maturity");
        assertEq(healthFactor, preview.resultingHealthFactor, "preview health");
        assertTrue(preview.executable, "preview executable");
        assertEq(ohm.balanceOf(alice), recipientBalanceBefore + DEFAULT_BORROW_AMOUNT, "OHM mint");
        assertEq(
            usds.balanceOf(address(trsry)),
            treasuryBalanceBefore + preview.fee,
            "treasury fee"
        );

        IBurnerLoans.Position memory position = burnerLoans.getPosition(address(usds), alice);
        assertEq(
            uint256(position.status),
            uint256(IBurnerLoans.PositionStatus.Active),
            "position status"
        );
        assertEq(position.lastBorrowBlock, uint48(block.number), "last borrow block");
        _assertPositionAndActiveDebt(
            address(usds),
            alice,
            DEFAULT_COLLATERAL_AMOUNT,
            DEFAULT_BORROW_AMOUNT,
            preview.maturity
        );

        address[] memory borrowers = burnerLoans.getActiveBorrowers(address(usds));
        assertEq(borrowers.length, 1, "active borrower count");
        assertEq(borrowers[0], alice, "active borrower");
    }

    // Condition tree:
    // - Caller: owner (`alice`)
    // - Authorization state: owner acts on own account
    // - Parameters: asset is configured, recipient is owner, authorization deadline is unused
    // - Expected branch: owner borrow succeeds and matches the same-state preview
    function test_givenOwnerCaller_borrowSucceeds() public {
        _depositDefaultCollateral(alice);

        _borrowWithPreview(alice, alice, alice, DEFAULT_BORROW_AMOUNT);
    }

    // Condition tree:
    // - Borrow amount: fuzzed from one OHM unit through 100 OHM
    // - Collateral: sufficient across the full range
    // - Expected branch: exact OHM mint, positive fee, and preview/write consistency
    function test_givenFuzzedBorrowAmount_borrowMintsExactAndChargesFee(uint96 ohmAmount_) public {
        uint128 amount = uint128(bound(uint256(ohmAmount_), 1, DEFAULT_BORROW_AMOUNT));
        _depositDefaultCollateral(alice);

        IBurnerLoans.BorrowPreview memory preview = _borrowWithPreview(alice, alice, alice, amount);

        assertGt(preview.fee, 0, "no fee-avoidance dust");
        assertEq(ohm.balanceOf(alice), amount, "exact fuzzed mint");
        assertEq(burnerLoans.totalActiveDebtOhm(), amount, "exact fuzzed debt");
    }

    // Condition tree:
    // - Caller: operator
    // - Authorization state: no authorization from owner to operator
    // - Parameters: onBehalfOf is owner, recipient is operator
    // - Expected branch: authorization check reverts before borrow validation or state changes
    function test_givenUnauthorizedOperator_reverts() public {
        vm.prank(operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        burnerLoans.borrow(address(usds), 1e9, alice, operator, 0);
    }

    // Condition tree:
    // - Caller: operator
    // - Authorization state: owner has authorized operator through a future deadline
    // - Parameters: onBehalfOf is owner, recipient is operator
    // - Fee payer: operator balance and allowance, not owner collateral or allowance
    // - Expected branch: operator borrow succeeds, routes OHM, and pays the exact previewed fee
    function test_givenAuthorizedOperator_borrowChargesOperatorAndPreservesOwnerFunds() public {
        _depositDefaultCollateral(alice);
        _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));
        usds.mint(operator, 100e18);
        vm.prank(operator);
        usds.approve(address(burnerLoans), type(uint256).max);

        uint256 ownerBalanceBefore = usds.balanceOf(alice);
        uint256 ownerAllowanceBefore = usds.allowance(alice, address(burnerLoans));
        uint256 operatorBalanceBefore = usds.balanceOf(operator);

        IBurnerLoans.BorrowPreview memory preview = _borrowWithPreview(
            operator,
            alice,
            operator,
            DEFAULT_BORROW_AMOUNT
        );

        assertEq(usds.balanceOf(alice), ownerBalanceBefore, "owner fee balance untouched");
        assertEq(
            usds.allowance(alice, address(burnerLoans)),
            ownerAllowanceBefore,
            "owner fee allowance untouched"
        );
        assertEq(
            usds.balanceOf(operator),
            operatorBalanceBefore - preview.fee,
            "operator paid fee"
        );
        assertEq(ohm.balanceOf(operator), DEFAULT_BORROW_AMOUNT, "operator recipient OHM");
    }

    // Condition tree:
    // - Caller: authorized operator
    // - Position owner: alice
    // - Recipient: a third party distinct from owner and operator
    // - Expected branch: preview/write agree and exact OHM is routed to the chosen recipient
    function test_givenAuthorizedOperator_borrowRoutesOhmToThirdPartyRecipient() public {
        address recipient = makeAddr("recipient");
        _depositDefaultCollateral(alice);
        _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));
        usds.mint(operator, 100e18);
        vm.prank(operator);
        usds.approve(address(burnerLoans), type(uint256).max);

        _borrowWithPreview(operator, alice, recipient, DEFAULT_BORROW_AMOUNT);

        assertEq(ohm.balanceOf(recipient), DEFAULT_BORROW_AMOUNT, "third-party recipient OHM");
        assertEq(ohm.balanceOf(alice), 0, "owner receives no routed OHM");
        assertEq(ohm.balanceOf(operator), 0, "operator receives no routed OHM");
    }

    // Condition tree:
    // - Caller: operator
    // - Authorization state: owner authorization exists but block timestamp is after deadline
    // - Parameters: onBehalfOf is owner, recipient is operator
    // - Expected branch: authorization check reverts before borrow validation or state changes
    function test_givenExpiredAuthorization_reverts() public {
        _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1));
        vm.warp(block.timestamp + 2);

        vm.prank(operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        burnerLoans.borrow(address(usds), 1e9, alice, operator, 0);
    }

    // Condition tree:
    // - Caller: owner (`alice`)
    // - Authorization state: owner acts on own account
    // - Parameters: recipient is zero address
    // - Expected branch: recipient validation reverts before pricing or state changes
    function test_givenZeroRecipient_reverts() public {
        vm.prank(alice);
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        burnerLoans.borrow(address(usds), 1e9, alice, address(0), 0);
    }

    // Condition tree:
    // - Amount: zero OHM
    // - Caller: owner
    // - Expected branch: amount validation reverts before pricing or state changes
    function test_givenZeroAmount_borrowAndPreviewRevert() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAmount.selector);
        burnerLoans.previewBorrow(address(usds), 0, alice);

        vm.prank(alice);
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAmount.selector);
        burnerLoans.borrow(address(usds), 0, alice, alice, 0);
    }

    // Condition tree:
    // - Debt episode: active position receives an additional borrow
    // - Time: later block and timestamp, before maturity
    // - Expected branch: only incremental debt and lastBorrowBlock change; maturity/index persist
    function test_givenActivePosition_additionalBorrowPreservesMaturityAndIndex() public {
        address comparisonBorrower = makeAddr("comparisonBorrower");
        _depositDefaultCollateral(alice);
        IBurnerLoans.BorrowPreview memory firstPreview = _borrowWithPreview(
            alice,
            alice,
            alice,
            50e9
        );
        vm.roll(block.number + 7);
        vm.warp(block.timestamp + 1 days);
        price.setTimestamp(uint48(block.timestamp));
        _depositDefaultCollateral(comparisonBorrower);
        IBurnerLoans.BorrowPreview memory incrementalQuote = burnerLoans.previewBorrow(
            address(usds),
            25e9,
            comparisonBorrower
        );

        IBurnerLoans.BorrowPreview memory secondPreview = _borrowWithPreview(
            alice,
            alice,
            alice,
            25e9
        );

        IBurnerLoans.Position memory position = burnerLoans.getPosition(address(usds), alice);
        assertEq(position.debtOhm, 75e9, "incremental debt");
        assertEq(position.maturity, firstPreview.maturity, "maturity preserved");
        assertEq(secondPreview.maturity, firstPreview.maturity, "preview maturity preserved");
        assertEq(secondPreview.fee, incrementalQuote.fee, "incremental debt fee only");
        assertEq(position.lastBorrowBlock, uint48(block.number), "last borrow block updated");
        assertEq(burnerLoans.totalActiveDebtOhm(), 75e9, "global active debt");
        assertEq(burnerLoans.assetActiveDebtOhm(address(usds)), 75e9, "asset active debt");

        address[] memory borrowers = burnerLoans.getActiveBorrowers(address(usds));
        assertEq(borrowers.length, 1, "no duplicate borrower");
        assertEq(borrowers[0], alice, "indexed owner");
    }

    // Condition tree:
    // - Borrow sequence: two fuzzed positive amounts totaling at most 100 OHM
    // - Time: both borrows execute in the same block and timestamp
    // - Expected branch: repeat borrowing is permitted with exact cumulative debt and one index entry
    function test_givenActivePosition_sameBlockBorrowRemainsPermitted(
        uint64 firstAmount_,
        uint64 secondAmount_
    ) public {
        uint128 firstAmount = uint128(bound(uint256(firstAmount_), 1, 50e9));
        uint128 secondAmount = uint128(bound(uint256(secondAmount_), 1, 50e9));
        _depositDefaultCollateral(alice);
        uint256 borrowBlock = block.number;

        IBurnerLoans.BorrowPreview memory firstPreview = _borrowWithPreview(
            alice,
            alice,
            alice,
            firstAmount
        );
        IBurnerLoans.BorrowPreview memory secondPreview = _borrowWithPreview(
            alice,
            alice,
            alice,
            secondAmount
        );

        uint256 total = firstAmount + secondAmount;
        IBurnerLoans.Position memory position = burnerLoans.getPosition(address(usds), alice);
        assertEq(secondPreview.resultingDebtOhm, total, "same-block cumulative debt");
        assertEq(secondPreview.maturity, firstPreview.maturity, "same-block preserved maturity");
        assertEq(position.lastBorrowBlock, borrowBlock, "same-block last borrow block");
        assertEq(ohm.balanceOf(alice), total, "same-block cumulative mint");
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 1, "single index entry");
    }

    // Condition tree:
    // - Asset: one configured collateral asset
    // - Borrowers: two distinct owners with independent collateral and debt
    // - Expected branch: both positions are active; borrower index and aggregate debt include both
    function test_givenTwoBorrowersForSameAsset_borrowTracksIndependentPositions(
        uint96 aliceAmount_,
        uint96 bobAmount_
    ) public {
        address bob = makeAddr("bob");
        uint128 aliceAmount = uint128(bound(uint256(aliceAmount_), 1, DEFAULT_BORROW_AMOUNT));
        uint128 bobAmount = uint128(bound(uint256(bobAmount_), 1, DEFAULT_BORROW_AMOUNT));
        _depositDefaultCollateral(alice);
        _depositDefaultCollateral(bob);

        _borrowAssetWithPreview(address(usds), alice, aliceAmount);
        _borrowAssetWithPreview(address(usds), bob, bobAmount);

        IBurnerLoans.Position memory alicePosition = burnerLoans.getPosition(address(usds), alice);
        IBurnerLoans.Position memory bobPosition = burnerLoans.getPosition(address(usds), bob);
        assertEq(alicePosition.debtOhm, aliceAmount, "alice debt isolated");
        assertEq(bobPosition.debtOhm, bobAmount, "bob debt isolated");
        assertEq(
            uint256(alicePosition.status),
            uint256(IBurnerLoans.PositionStatus.Active),
            "alice position active"
        );
        assertEq(
            uint256(bobPosition.status),
            uint256(IBurnerLoans.PositionStatus.Active),
            "bob position active"
        );
        assertEq(alicePosition.depositedCollateral, DEFAULT_COLLATERAL_AMOUNT, "alice collateral");
        assertEq(bobPosition.depositedCollateral, DEFAULT_COLLATERAL_AMOUNT, "bob collateral");
        assertEq(
            burnerLoans.totalActiveDebtOhm(),
            aliceAmount + bobAmount,
            "global debt includes both"
        );
        assertEq(
            burnerLoans.assetActiveDebtOhm(address(usds)),
            aliceAmount + bobAmount,
            "asset debt includes both"
        );

        address[] memory borrowers = burnerLoans.getActiveBorrowers(address(usds));
        assertEq(borrowers.length, 2, "two active borrowers");
        assertTrue(_contains(borrowers, alice), "active borrowers contains alice");
        assertTrue(_contains(borrowers, bob), "active borrowers contains bob");
    }

    // Condition tree:
    // - Borrower: one owner borrowing against two configured collateral assets
    // - Expected branch: positions, active-borrower sets, and per-asset debt remain asset-scoped
    function test_givenSameBorrowerForTwoAssets_borrowTracksIndependentPositions(
        uint96 usdsAmount_,
        uint96 secondAssetAmount_
    ) public {
        MockERC20 secondAsset = new MockERC20("Second Asset", "ASSET2", 18);
        uint128 usdsAmount = uint128(bound(uint256(usdsAmount_), 1, DEFAULT_BORROW_AMOUNT));
        uint128 secondAssetAmount = uint128(
            bound(uint256(secondAssetAmount_), 1, DEFAULT_BORROW_AMOUNT)
        );
        _depositDefaultCollateral(alice);
        _addAssetAndDepositCollateral(secondAsset, alice, DEFAULT_COLLATERAL_AMOUNT);

        _borrowAssetWithPreview(address(usds), alice, usdsAmount);
        _borrowAssetWithPreview(address(secondAsset), alice, secondAssetAmount);

        IBurnerLoans.Position memory usdsPosition = burnerLoans.getPosition(address(usds), alice);
        IBurnerLoans.Position memory secondPosition = burnerLoans.getPosition(
            address(secondAsset),
            alice
        );
        assertEq(usdsPosition.debtOhm, usdsAmount, "USDS position debt");
        assertEq(secondPosition.debtOhm, secondAssetAmount, "second-asset position debt");
        assertEq(
            uint256(usdsPosition.status),
            uint256(IBurnerLoans.PositionStatus.Active),
            "USDS position active"
        );
        assertEq(
            uint256(secondPosition.status),
            uint256(IBurnerLoans.PositionStatus.Active),
            "second-asset position active"
        );
        assertEq(usdsPosition.depositedCollateral, DEFAULT_COLLATERAL_AMOUNT, "USDS collateral");
        assertEq(
            secondPosition.depositedCollateral,
            DEFAULT_COLLATERAL_AMOUNT,
            "second-asset collateral"
        );
        assertEq(
            burnerLoans.totalActiveDebtOhm(),
            usdsAmount + secondAssetAmount,
            "global debt includes both assets"
        );
        assertEq(burnerLoans.assetActiveDebtOhm(address(usds)), usdsAmount, "USDS debt isolated");
        assertEq(
            burnerLoans.assetActiveDebtOhm(address(secondAsset)),
            secondAssetAmount,
            "second-asset debt isolated"
        );

        address[] memory usdsBorrowers = burnerLoans.getActiveBorrowers(address(usds));
        address[] memory secondAssetBorrowers = burnerLoans.getActiveBorrowers(
            address(secondAsset)
        );
        assertEq(usdsBorrowers.length, 1, "one USDS borrower");
        assertEq(secondAssetBorrowers.length, 1, "one second-asset borrower");
        assertEq(usdsBorrowers[0], alice, "USDS borrower is alice");
        assertEq(secondAssetBorrowers[0], alice, "second-asset borrower is alice");
    }

    // Condition tree:
    // - Assets: two configured collateral assets
    // - Borrowers: one distinct owner per asset
    // - Expected branch: each asset has one isolated position, borrower entry, and debt total
    function test_givenDifferentBorrowersForTwoAssets_borrowTracksIndependentState(
        uint96 aliceAmount_,
        uint96 bobAmount_
    ) public {
        address bob = makeAddr("bob");
        MockERC20 secondAsset = new MockERC20("Second Asset", "ASSET2", 18);
        uint128 aliceAmount = uint128(bound(uint256(aliceAmount_), 1, DEFAULT_BORROW_AMOUNT));
        uint128 bobAmount = uint128(bound(uint256(bobAmount_), 1, DEFAULT_BORROW_AMOUNT));
        _depositDefaultCollateral(alice);
        _addAssetAndDepositCollateral(secondAsset, bob, DEFAULT_COLLATERAL_AMOUNT);

        _borrowAssetWithPreview(address(usds), alice, aliceAmount);
        _borrowAssetWithPreview(address(secondAsset), bob, bobAmount);

        IBurnerLoans.Position memory alicePosition = burnerLoans.getPosition(address(usds), alice);
        IBurnerLoans.Position memory bobPosition = burnerLoans.getPosition(
            address(secondAsset),
            bob
        );
        assertEq(alicePosition.debtOhm, aliceAmount, "alice USDS debt");
        assertEq(bobPosition.debtOhm, bobAmount, "bob second-asset debt");
        assertEq(
            uint256(alicePosition.status),
            uint256(IBurnerLoans.PositionStatus.Active),
            "alice position active"
        );
        assertEq(
            uint256(bobPosition.status),
            uint256(IBurnerLoans.PositionStatus.Active),
            "bob position active"
        );
        assertEq(
            burnerLoans.getPosition(address(usds), bob).debtOhm,
            0,
            "bob has no USDS position"
        );
        assertEq(
            burnerLoans.getPosition(address(secondAsset), alice).debtOhm,
            0,
            "alice has no second-asset position"
        );
        assertEq(
            burnerLoans.totalActiveDebtOhm(),
            aliceAmount + bobAmount,
            "global debt includes both"
        );
        assertEq(burnerLoans.assetActiveDebtOhm(address(usds)), aliceAmount, "USDS debt isolated");
        assertEq(
            burnerLoans.assetActiveDebtOhm(address(secondAsset)),
            bobAmount,
            "second-asset debt isolated"
        );

        address[] memory usdsBorrowers = burnerLoans.getActiveBorrowers(address(usds));
        address[] memory secondAssetBorrowers = burnerLoans.getActiveBorrowers(
            address(secondAsset)
        );
        assertEq(usdsBorrowers.length, 1, "one USDS borrower");
        assertEq(secondAssetBorrowers.length, 1, "one second-asset borrower");
        assertEq(usdsBorrowers[0], alice, "USDS borrower is alice");
        assertEq(secondAssetBorrowers[0], bob, "second-asset borrower is bob");
    }

    function _contains(
        address[] memory addresses_,
        address expected_
    ) internal pure returns (bool) {
        for (uint256 i; i < addresses_.length; ++i) {
            if (addresses_[i] == expected_) return true;
        }

        return false;
    }

    // Condition tree:
    // - Position collateral: zero credited collateral
    // - Expected branch: preview and write reject debt creation without implicit deposit
    function test_givenNoCreditedCollateral_borrowAndPreviewRevert() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_NoCollateral.selector);
        burnerLoans.previewBorrow(address(usds), 1e9, alice);

        vm.prank(alice);
        vm.expectRevert(IBurnerLoans.BurnerLoans_NoCollateral.selector);
        burnerLoans.borrow(address(usds), 1e9, alice, alice, type(uint256).max);
    }

    // Condition tree:
    // - FLOAN: two markets share the Burner Loans facility, collateral, and debt-token tuple
    // - Expected branch: Burner Loans rejects the ambiguous market instead of selecting one
    function test_givenMultipleMarketsForAsset_borrowAndPreviewRevert() public {
        _createDuplicateUsdsMarketForTest();
        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_AmbiguousMarket.selector,
            address(usds),
            2
        );

        vm.expectRevert(error);
        burnerLoans.previewBorrow(address(usds), 1e9, alice);

        vm.prank(alice);
        vm.expectRevert(error);
        burnerLoans.borrow(address(usds), 1e9, alice, alice, type(uint256).max);
    }

    // Condition tree:
    // - Capacity: resulting facility debt exceeds the global cap
    // - Asset capacity: sufficient
    // - Expected branch: global cap error includes resulting debt and cap
    function test_givenGlobalCapExceeded_borrowAndPreviewRevert(
        uint96 ohmAmount_,
        uint96 availableRoom_
    ) public {
        uint128 amount = uint128(bound(uint256(ohmAmount_), 1, DEFAULT_BORROW_AMOUNT));
        uint256 availableRoom = bound(uint256(availableRoom_), 0, amount - 1);
        _depositDefaultCollateral(alice);
        uint256 existingGlobalDebt = burnerLoans.globalDebtCapOhm() - availableRoom;
        _setOtherMarketDebtForTest(uint128(existingGlobalDebt));

        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_GlobalDebtCapExceeded.selector,
            amount,
            availableRoom
        );
        _expectBorrowAndPreviewRevert(error, amount);
    }

    // Condition tree:
    // - Capacity: resulting asset debt exceeds a fuzzed per-asset cap
    // - Global capacity: sufficient
    // - Expected branch: asset cap error includes asset, resulting debt, and cap
    function test_givenAssetCapExceeded_borrowAndPreviewRevert(
        uint96 ohmAmount_,
        uint96 availableRoom_
    ) public {
        uint128 amount = uint128(bound(uint256(ohmAmount_), 1, DEFAULT_BORROW_AMOUNT));
        uint256 availableRoom = bound(uint256(availableRoom_), 0, amount - 1);
        _depositDefaultCollateral(alice);
        uint256 assetCap = burnerLoans.getAssetConfig(address(usds)).debtCap;
        uint256 existingAssetDebt = assetCap - availableRoom;
        burnerLoans.setActiveDebtForTest(address(usds), existingAssetDebt, existingAssetDebt);

        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_AssetDebtCapExceeded.selector,
            address(usds),
            amount,
            availableRoom
        );
        _expectBorrowAndPreviewRevert(error, amount);
    }

    // Condition tree:
    // - Policy state: globally disabled
    // - Expected branch: preview and write are blocked by the emergency pause
    function test_givenGlobalDisabled_borrowAndPreviewRevert() public {
        _depositDefaultCollateral(alice);
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.expectRevert(abi.encodeWithSignature("NotEnabled()"));
        burnerLoans.previewBorrow(address(usds), 1e9, alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NotEnabled()"));
        burnerLoans.borrow(address(usds), 1e9, alice, alice, type(uint256).max);
    }

    // Condition tree:
    // - Asset state: configured but disabled for new exposure
    // - Expected branch: preview and write reject the new borrow
    function test_givenAssetDisabled_borrowAndPreviewRevert() public {
        _depositDefaultCollateral(alice);
        vm.prank(admin);
        burnerLoans.disableAsset(address(usds));

        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_AssetNotEnabled.selector,
            address(usds)
        );
        vm.expectRevert(error);
        burnerLoans.previewBorrow(address(usds), 1e9, alice);

        vm.prank(alice);
        vm.expectRevert(error);
        burnerLoans.borrow(address(usds), 1e9, alice, alice, type(uint256).max);
    }

    // Condition tree:
    // - Position: active debt with maturity equal to the current timestamp
    // - Health: otherwise healthy
    // - Expected branch: maturity-seizable position cannot increase debt
    function test_givenMaturedActivePosition_borrowAndPreviewRevert() public {
        _depositDefaultCollateral(alice);
        uint48 maturity = uint48(block.timestamp + 1);
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: DEFAULT_COLLATERAL_AMOUNT,
                debtOhm: 10e9,
                maturity: maturity,
                lastBorrowBlock: uint48(block.number - 1),
                status: IBurnerLoans.PositionStatus.Active
            })
        );
        burnerLoans.setActiveDebtForTest(address(usds), 10e9, 10e9);
        vm.warp(maturity);

        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_PositionMatured.selector,
            maturity
        );
        vm.expectRevert(error);
        burnerLoans.previewBorrow(address(usds), 1e9, alice);

        vm.prank(alice);
        vm.expectRevert(error);
        burnerLoans.borrow(address(usds), 1e9, alice, alice, type(uint256).max);
    }

    // Condition tree:
    // - Position: active and not matured
    // - Current health: below 1e18 before the requested increase
    // - Expected branch: health-seizable position cannot increase debt
    function test_givenCurrentlyUnhealthyActivePosition_borrowAndPreviewRevert(
        uint96 ohmAmount_
    ) public {
        uint128 amount = uint128(bound(uint256(ohmAmount_), 1, DEFAULT_BORROW_AMOUNT));
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: 1e18,
                debtOhm: 100e9,
                maturity: uint48(block.timestamp + 1 days),
                lastBorrowBlock: uint48(block.number - 1),
                status: IBurnerLoans.PositionStatus.Active
            })
        );
        burnerLoans.setActiveDebtForTest(address(usds), 100e9, 100e9);

        _expectBorrowAndPreviewPartialRevert(
            IBurnerLoans.BurnerLoans_UnhealthyPosition.selector,
            amount
        );
    }

    // Condition tree:
    // - Position: active, not matured, and currently unhealthy
    // - Requested amount: zero
    // - Expected branch: zero-amount validation takes precedence over current-health validation
    function test_givenCurrentlyUnhealthyActivePosition_zeroBorrowRevertsWithZeroAmount() public {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: 1e18,
                debtOhm: 100e9,
                maturity: uint48(block.timestamp + 1 days),
                lastBorrowBlock: uint48(block.number - 1),
                status: IBurnerLoans.PositionStatus.Active
            })
        );
        burnerLoans.setActiveDebtForTest(address(usds), 100e9, 100e9);

        _expectBorrowAndPreviewRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_ZeroAmount.selector),
            0
        );
    }

    // Condition tree:
    // - Resulting health: exactly 1e18
    // - Math: 100 OHM * $10 * 115% = 1,150 USDS required
    // - Expected branch: exact seizure boundary remains borrowable
    function test_givenResultingHealthExactlyOneWad_borrowSucceeds() public {
        _depositCollateral(alice, 1_150e18);

        IBurnerLoans.BorrowPreview memory preview = _borrowWithPreview(
            alice,
            alice,
            alice,
            DEFAULT_BORROW_AMOUNT
        );

        assertEq(preview.resultingHealthFactor, 1e18, "exact health boundary");
    }

    // Condition tree:
    // - Resulting health: 1.1e18
    // - Math: 1,265 USDS / 1,150 USDS required = 1.1
    // - Expected branch: borrow succeeds and returns the manually calculated health factor
    function test_givenResultingHealthAboveOneWad_borrowReturnsExpectedHealth() public {
        _depositCollateral(alice, 1_265e18);

        IBurnerLoans.BorrowPreview memory preview = _borrowWithPreview(
            alice,
            alice,
            alice,
            DEFAULT_BORROW_AMOUNT
        );

        assertEq(preview.resultingHealthFactor, 1.1e18, "manual health above boundary");
    }

    // Condition tree:
    // - Borrow amount: fixed at 100 OHM, whose manual collateral boundary is 1,150 USDS
    // - Collateral: fuzzed positive surplus above that fixed boundary
    // - Expected branch: every sampled surplus produces health above 1e18
    function test_givenFuzzedCollateralAboveBoundary_borrowSucceeds(
        uint128 collateralSurplus_
    ) public {
        // At a 1,150 USDS denominator, 1,150 wei is the smallest surplus that
        // increases the 18-decimal health factor above 1e18 after rounding down.
        uint256 collateralSurplus = bound(uint256(collateralSurplus_), 1_150, 100e18);
        _depositCollateral(alice, uint128(1_150e18 + collateralSurplus));

        IBurnerLoans.BorrowPreview memory preview = _borrowWithPreview(
            alice,
            alice,
            alice,
            DEFAULT_BORROW_AMOUNT
        );

        assertGt(preview.resultingHealthFactor, 1e18, "health above boundary");
    }

    // Condition tree:
    // - Collateral: one 18-decimal USDS unit below the manual 1,150 USDS boundary
    // - Math: floor((1,150e18 - 1) / 1,150e18 * 1e18) = 999999999999999999
    // - Expected branch: preview and write return the manually calculated unhealthy factor
    function test_givenResultingHealthOneUnitBelowOneWad_borrowAndPreviewRevert() public {
        _depositCollateral(alice, 1_150e18 - 1);

        _expectBorrowAndPreviewRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_UnhealthyBorrow.selector,
                999999999999999999
            ),
            DEFAULT_BORROW_AMOUNT
        );
    }

    // Condition tree:
    // - Borrow amount: fixed at 100 OHM, whose manual collateral boundary is 1,150 USDS
    // - Collateral: fuzzed positive shortfall below that fixed boundary
    // - Expected branch: every sampled shortfall is rejected as unhealthy
    function test_givenFuzzedCollateralBelowBoundary_borrowAndPreviewRevert(
        uint128 collateralShortfall_
    ) public {
        uint256 collateralShortfall = bound(uint256(collateralShortfall_), 1, 1_150e18 - 1);
        _depositCollateral(alice, uint128(1_150e18 - collateralShortfall));

        _expectBorrowAndPreviewPartialRevert(
            IBurnerLoans.BurnerLoans_UnhealthyBorrow.selector,
            DEFAULT_BORROW_AMOUNT
        );
    }

    // Condition tree:
    // - PRICE timestamps: older than one observation-frequency window
    // - Price values: otherwise nonzero and supported for both legs
    // - Expected branch: stale risk input blocks preview and write
    function test_givenStalePrices_borrowAndPreviewRevert(
        uint96 ohmAmount_,
        uint32 staleBy_
    ) public {
        uint128 amount = uint128(bound(uint256(ohmAmount_), 1, DEFAULT_BORROW_AMOUNT));
        uint256 staleBy = bound(uint256(staleBy_), 1, 30 days);
        _depositDefaultCollateral(alice);
        vm.warp(31 days);
        price.setTimestamp(uint48(block.timestamp - 8 hours - staleBy));

        _expectBorrowAndPreviewRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidPrice.selector),
            amount
        );
    }

    // Condition tree:
    // - PRICE timestamp: exactly one observation-frequency window old
    // - Expected branch: boundary timestamp remains fresh and borrowing succeeds
    function test_givenPriceAtFreshnessBoundary_borrowSucceeds(uint96 ohmAmount_) public {
        uint128 amount = uint128(bound(uint256(ohmAmount_), 1, DEFAULT_BORROW_AMOUNT));
        _depositDefaultCollateral(alice);
        vm.warp(8 hours + 1);
        price.setTimestamp(uint48(block.timestamp - 8 hours));

        _borrowWithPreview(alice, alice, alice, amount);
    }

    // Condition tree:
    // - OHM PRICE: supported but zero
    // - Collateral PRICE: fresh and nonzero
    // - Expected branch: PRICE zero error blocks preview and write
    function test_givenZeroOhmPrice_borrowAndPreviewRevert() public {
        _depositDefaultCollateral(alice);
        price.setPrice(address(ohm), 0);

        _expectBorrowAndPreviewRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(ohm)),
            DEFAULT_BORROW_AMOUNT
        );
    }

    // Condition tree:
    // - Collateral PRICE: supported but zero
    // - OHM PRICE: fresh and nonzero
    // - Expected branch: PRICE zero error blocks preview and write
    function test_givenZeroCollateralPrice_borrowAndPreviewRevert() public {
        _depositDefaultCollateral(alice);
        price.setPrice(address(usds), 0);

        _expectBorrowAndPreviewRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(usds)),
            DEFAULT_BORROW_AMOUNT
        );
    }

    // Condition tree:
    // - OHM PRICE: removed after asset configuration
    // - Collateral PRICE: supported
    // - Expected branch: unsupported OHM leg blocks preview and write
    function test_givenUnsupportedOhmPrice_borrowAndPreviewRevert() public {
        _depositDefaultCollateral(alice);
        price.removeAsset(address(ohm));

        _expectBorrowAndPreviewRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, address(ohm)),
            DEFAULT_BORROW_AMOUNT
        );
    }

    // Condition tree:
    // - Collateral PRICE: removed after asset configuration
    // - OHM PRICE: supported
    // - Expected branch: unsupported collateral leg blocks preview and write
    function test_givenUnsupportedCollateralPrice_borrowAndPreviewRevert() public {
        _depositDefaultCollateral(alice);
        price.removeAsset(address(usds));

        _expectBorrowAndPreviewRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, address(usds)),
            DEFAULT_BORROW_AMOUNT
        );
    }

    // Condition tree:
    // - OHM market price: $5, below the oracle's $10 backing value
    // - Backing multiplier: 100%, so backing requires $10 per borrowed OHM
    // - Collateral: exactly 1,000 USDS for 100 OHM
    // - Expected branch: backing leg dominates the $575 market requirement and borrow succeeds
    function test_givenBelowBackingOhmPrice_borrowSucceedsOnlyAtBackingRequirement() public {
        _configurePrice(address(ohm), 5e18);
        backingOracle.setBacking(10e18);
        _depositCollateral(alice, 1_000e18);

        IBurnerLoans.BorrowPreview memory preview = _borrowWithPreview(
            alice,
            alice,
            alice,
            DEFAULT_BORROW_AMOUNT
        );

        assertEq(preview.resultingHealthFactor, 1e18, "backing-dominant boundary");
    }

    // Condition tree:
    // - OHM market price: $5 while the backing oracle reports $10
    // - Collateral: one USDS unit below the $1,000 backing requirement
    // - Expected branch: market requirement is covered but backing requirement rejects the borrow
    function test_givenBelowBackingOhmPriceAndInsufficientBacking_borrowAndPreviewRevert() public {
        _configurePrice(address(ohm), 5e18);
        backingOracle.setBacking(10e18);
        _depositCollateral(alice, 1_000e18 - 1);

        _expectBorrowAndPreviewPartialRevert(
            IBurnerLoans.BurnerLoans_UnhealthyBorrow.selector,
            DEFAULT_BORROW_AMOUNT
        );
    }

    // Condition tree:
    // - OHM market price: fuzzed below the point where its 115% requirement reaches $10 backing
    // - Backing multiplier: 100%
    // - Expected branch: exact backing requirement is sufficient for every sampled lower market price
    function test_givenFuzzedMarketPriceBelowBacking_borrowUsesBackingRequirement(
        uint64 ohmMarketPrice_
    ) public {
        uint256 marketPrice = bound(uint256(ohmMarketPrice_), 1, 8e18);
        _configurePrice(address(ohm), marketPrice);
        backingOracle.setBacking(10e18);
        _depositCollateral(alice, 1_000e18);

        IBurnerLoans.BorrowPreview memory preview = _borrowWithPreview(
            alice,
            alice,
            alice,
            DEFAULT_BORROW_AMOUNT
        );

        assertEq(preview.resultingHealthFactor, 1e18, "manual backing requirement");
    }

    // Condition tree:
    // - Backing multiplier: 150%
    // - OHM market price: $1, so the backing leg always dominates
    // - Math: 100 OHM * $10 backing * 150% = 1,500 USDS required
    // - Expected branch: exact manually calculated collateral produces health of 1e18
    function test_givenBackingMultiplier_borrowUsesMultipliedBacking() public {
        _configurePrice(address(ohm), 1e18);
        backingOracle.setBacking(10e18);
        _setBackingMultiplier(15_000);
        _depositCollateral(alice, 1_500e18);

        IBurnerLoans.BorrowPreview memory preview = _borrowWithPreview(
            alice,
            alice,
            alice,
            DEFAULT_BORROW_AMOUNT
        );

        assertEq(preview.resultingHealthFactor, 1e18, "manual multiplied backing requirement");
    }

    // Condition tree:
    // - OHM market price: $12, whose 115% requirement exceeds $10 backing
    // - Backing multiplier: 100%
    // - Math: 100 OHM * $12 * 115% = 1,380 USDS required
    // - Expected branch: exact manually calculated collateral produces health of 1e18
    function test_givenMarketRequirementAboveBacking_borrowUsesMarketRequirement() public {
        _configurePrice(address(ohm), 12e18);
        backingOracle.setBacking(10e18);
        _depositCollateral(alice, 1_380e18);

        IBurnerLoans.BorrowPreview memory preview = _borrowWithPreview(
            alice,
            alice,
            alice,
            DEFAULT_BORROW_AMOUNT
        );

        assertEq(preview.resultingHealthFactor, 1e18, "manual market requirement");
    }

    // Condition tree:
    // - Borrow amount: fixed at 100 OHM, whose manual backing boundary is 1,000 USDS
    // - Collateral: fuzzed positive shortfall below that fixed backing requirement
    // - Expected branch: every undercollateralized sample is rejected
    function test_givenFuzzedInsufficientBacking_borrowAndPreviewRevert(
        uint128 collateralShortfall_
    ) public {
        _configurePrice(address(ohm), 1e18);
        backingOracle.setBacking(10e18);
        uint256 shortfall = bound(uint256(collateralShortfall_), 1, 1_000e18 - 1);
        _depositCollateral(alice, uint128(1_000e18 - shortfall));

        _expectBorrowAndPreviewPartialRevert(
            IBurnerLoans.BurnerLoans_UnhealthyBorrow.selector,
            DEFAULT_BORROW_AMOUNT
        );
    }

    // Condition tree:
    // - Backing oracle value: zero after configuration
    // - Market PRICE inputs: fresh, supported, and nonzero
    // - Expected branch: invalid backing blocks preview and write
    function test_givenZeroBacking_borrowAndPreviewRevert() public {
        _depositDefaultCollateral(alice);
        backingOracle.setBacking(0);

        _expectBorrowAndPreviewRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidPrice.selector),
            DEFAULT_BORROW_AMOUNT
        );
    }

    // Condition tree:
    // - Fee quote: greater than a fuzzed caller maxFee
    // - Other eligibility: valid
    // - Expected branch: write rejects the fee cap and leaves preview available
    function test_givenFeeAboveMax_borrowReverts(uint96 ohmAmount_, uint96 maxFee_) public {
        uint128 amount = uint128(bound(uint256(ohmAmount_), 1, DEFAULT_BORROW_AMOUNT));
        _depositDefaultCollateral(alice);
        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            amount,
            alice
        );
        uint256 maxFee = bound(uint256(maxFee_), 0, preview.fee - 1);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_FeeExceedsMax.selector,
                preview.fee,
                maxFee
            )
        );
        burnerLoans.borrow(address(usds), amount, alice, alice, maxFee);
    }

    // Condition tree:
    // - Borrow amount: one smallest OHM unit
    // - Incremental required collateral: two raw 18-decimal USDS units
    // - Fee: 25 bps of two units rounds up from a nonzero fraction to one unit
    // - Expected branch: preview and execution charge one raw collateral unit, preventing free debt
    function test_givenOneUnitDebt_borrowChargesOneUnitFee() public {
        _configurePrice(address(ohm), 1);
        backingOracle.setBacking(1);
        _depositCollateral(alice, 2);

        // debtValueUsd = ceil(1 OHM unit * 1 price unit / 1e9 OHM scale) = 1 USD unit.
        // requiredUsd = ceil(1 * 11,500 / 10,000) = 2 USD units.
        // requiredCollateral = 2 USD units * 1e18 USDS scale / $1e18 = 2 USDS units.
        // fee = ceil(2 * 25 / 10,000) = 1 USDS unit.
        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            1,
            alice
        );
        uint256 treasuryBalanceBefore = usds.balanceOf(address(trsry));

        vm.prank(alice);
        (
            uint256 borrowedOhm,
            uint256 fee,
            uint256 totalDebtOhm,
            uint48 maturity,
            uint256 healthFactor
        ) = burnerLoans.borrow(address(usds), 1, alice, alice, preview.fee);

        assertTrue(preview.executable, "one-unit preview executable");
        assertEq(preview.fee, 1, "preview rounds fee up to one collateral unit");
        assertEq(borrowedOhm, 1, "one OHM unit returned");
        assertEq(fee, 1, "borrow charges one collateral unit fee");
        assertEq(totalDebtOhm, preview.resultingDebtOhm, "one-unit preview debt");
        assertEq(maturity, preview.maturity, "one-unit preview maturity");
        assertEq(healthFactor, preview.resultingHealthFactor, "one-unit preview health");
        assertEq(ohm.balanceOf(alice), 1, "one OHM unit minted");
        assertEq(
            usds.balanceOf(address(trsry)),
            treasuryBalanceBefore + 1,
            "treasury receives one collateral unit fee"
        );
    }

    // Condition tree:
    // - Global utilization: raised to 90% while USDS asset utilization remains zero
    // - Fee input: asset-only pre-borrow utilization
    // - Expected branch: quote remains equal to the zero-asset-utilization quote
    function test_givenHighGlobalUtilization_previewFeeUsesAssetUtilizationOnly() public {
        _depositDefaultCollateral(alice);
        IBurnerLoans.BorrowPreview memory baseline = burnerLoans.previewBorrow(
            address(usds),
            DEFAULT_BORROW_AMOUNT,
            alice
        );
        burnerLoans.setActiveDebtForTest(address(usds), 900_000e9, 0);

        IBurnerLoans.BorrowPreview memory highGlobal = burnerLoans.previewBorrow(
            address(usds),
            DEFAULT_BORROW_AMOUNT,
            alice
        );

        assertEq(highGlobal.fee, baseline.fee, "global utilization excluded");
    }

    // Condition tree:
    // - Asset utilization: exactly 80% before the borrow
    // - Fee curve: default kink at 80%, producing 125 bps
    // - Incremental requirement: 1,150 USDS for 100 OHM
    // - Expected branch: fee is ceil(1,150 * 1.25%) = 14.375 USDS
    function test_givenAssetAtKink_previewFeeUsesPreBorrowUtilization() public {
        _depositDefaultCollateral(alice);
        burnerLoans.setActiveDebtForTest(address(usds), 80_000e9, 80_000e9);

        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            DEFAULT_BORROW_AMOUNT,
            alice
        );

        assertEq(preview.fee, 14_375e15, "pre-borrow kink fee");
    }

    // Condition tree:
    // - Fee transfer: direct from caller to TRSRY
    // - DepositManager accounting: liability/assets and claimable yield sampled before and after
    // - Expected branch: borrow fee does not alter credited collateral or custody yield accounting
    function test_givenSuccessfulBorrow_feeDoesNotAlterCustodyAccounting() public {
        _depositDefaultCollateral(alice);
        (uint256 sharesBefore, uint256 assetsBefore) = depositManager.getOperatorAssets(
            IERC20(address(usds)),
            address(burnerLoans)
        );
        uint256 yieldBefore = depositManager.maxClaimYield(
            IERC20(address(usds)),
            address(burnerLoans)
        );

        _borrowWithPreview(alice, alice, alice, DEFAULT_BORROW_AMOUNT);

        (uint256 sharesAfter, uint256 assetsAfter) = depositManager.getOperatorAssets(
            IERC20(address(usds)),
            address(burnerLoans)
        );
        assertEq(sharesAfter, sharesBefore, "custody shares unchanged");
        assertEq(assetsAfter, assetsBefore, "custody assets unchanged");
        assertEq(
            depositManager.maxClaimYield(IERC20(address(usds)), address(burnerLoans)),
            yieldBefore,
            "claimable yield unchanged"
        );
        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            DEFAULT_COLLATERAL_AMOUNT,
            "credited collateral unchanged"
        );
    }

    // Condition tree:
    // - Fee approval: removed after collateral deposit
    // - Fee balance: sufficient
    // - Expected branch: transfer helper reverts and all borrow effects roll back
    function test_givenMissingFeeApproval_borrowRevertsAndRollsBack() public {
        _depositDefaultCollateral(alice);
        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            DEFAULT_BORROW_AMOUNT,
            alice
        );
        vm.prank(alice);
        usds.approve(address(burnerLoans), 0);
        uint256 aliceBalanceBefore = usds.balanceOf(alice);
        uint256 treasuryBalanceBefore = usds.balanceOf(address(trsry));

        vm.prank(alice);
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        burnerLoans.borrow(address(usds), DEFAULT_BORROW_AMOUNT, alice, alice, preview.fee);

        _assertBorrowRolledBack(aliceBalanceBefore, treasuryBalanceBefore);
    }

    // Condition tree:
    // - Fee approval: sufficient
    // - Fee balance: one unit below the previewed fee
    // - Expected branch: transfer helper reverts and all borrow effects roll back
    function test_givenInsufficientFeeBalance_borrowRevertsAndRollsBack() public {
        _depositDefaultCollateral(alice);
        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            DEFAULT_BORROW_AMOUNT,
            alice
        );
        uint256 balance = usds.balanceOf(alice);
        usds.burn(alice, balance - (preview.fee - 1));
        uint256 aliceBalanceBefore = usds.balanceOf(alice);
        uint256 treasuryBalanceBefore = usds.balanceOf(address(trsry));

        vm.prank(alice);
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        burnerLoans.borrow(address(usds), DEFAULT_BORROW_AMOUNT, alice, alice, preview.fee);

        _assertBorrowRolledBack(aliceBalanceBefore, treasuryBalanceBefore);
    }

    // Condition tree:
    // - MINTR: deactivated after preview
    // - Fee transfer: would succeed before mint
    // - Expected branch: mint failure rolls fee, position, totals, index, and balances back
    function test_givenMintrFailure_borrowRevertsAndRollsBack() public {
        _depositDefaultCollateral(alice);
        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            DEFAULT_BORROW_AMOUNT,
            alice
        );
        minterAdminPolicy.deactivateMinter();
        uint256 aliceBalanceBefore = usds.balanceOf(alice);
        uint256 treasuryBalanceBefore = usds.balanceOf(address(trsry));

        vm.prank(alice);
        vm.expectRevert(MINTRv1.MINTR_NotActive.selector);
        burnerLoans.borrow(address(usds), DEFAULT_BORROW_AMOUNT, alice, alice, preview.fee);

        _assertBorrowRolledBack(aliceBalanceBefore, treasuryBalanceBefore);
    }

    function _assertBorrowRolledBack(
        uint256 aliceBalanceBefore_,
        uint256 treasuryBalanceBefore_
    ) internal view {
        IBurnerLoans.Position memory position = burnerLoans.getPosition(address(usds), alice);
        assertEq(position.depositedCollateral, DEFAULT_COLLATERAL_AMOUNT, "rollback collateral");
        assertEq(position.debtOhm, 0, "rollback debt");
        assertEq(position.maturity, 0, "rollback maturity");
        assertEq(position.lastBorrowBlock, 0, "rollback last borrow block");
        assertEq(
            uint256(position.status),
            uint256(IBurnerLoans.PositionStatus.NoDebt),
            "rollback status"
        );
        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "rollback global debt");
        assertEq(burnerLoans.assetActiveDebtOhm(address(usds)), 0, "rollback asset debt");
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 0, "rollback index");
        assertEq(usds.balanceOf(alice), aliceBalanceBefore_, "rollback fee payer balance");
        assertEq(
            usds.balanceOf(address(trsry)),
            treasuryBalanceBefore_,
            "rollback treasury balance"
        );
        assertEq(ohm.balanceOf(alice), 0, "rollback recipient OHM");
    }

    // Condition tree:
    // - External interaction: collateral fee token attempts a nested borrow during transferFrom
    // - Authorization: callback token is an authorized operator for the same owner
    // - Expected branch: nested borrow hits the transient guard; outer borrow mints and indexes once
    function test_givenReentrantFeeToken_borrowCannotMintOrIndexTwice() public {
        ReentrantFeeToken feeToken = new ReentrantFeeToken();
        _configurePrice(address(feeToken), 1e18);
        _configureDepositManagerAsset(address(feeToken));
        vm.prank(admin);
        burnerLoans.addAsset(
            address(feeToken),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );

        feeToken.mint(alice, DEFAULT_COLLATERAL_AMOUNT + 100e18);
        vm.startPrank(alice);
        feeToken.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(feeToken), DEFAULT_COLLATERAL_AMOUNT, alice);
        burnerLoans.setAuthorization(address(feeToken), uint48(block.timestamp + 1 days));
        vm.stopPrank();

        feeToken.setCallback(
            address(burnerLoans),
            abi.encodeCall(
                burnerLoans.borrow,
                (address(feeToken), 1e9, alice, alice, type(uint256).max)
            )
        );
        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(feeToken),
            DEFAULT_BORROW_AMOUNT,
            alice
        );

        vm.prank(alice);
        (
            uint256 borrowedOhm,
            uint256 feeCollateral,
            uint256 totalDebtOhm,
            uint48 maturity,
            uint256 healthFactor
        ) = burnerLoans.borrow(address(feeToken), DEFAULT_BORROW_AMOUNT, alice, alice, preview.fee);

        assertFalse(feeToken.callbackSucceeded(), "fee callback blocked");
        assertEq(
            feeToken.callbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "fee callback guard"
        );
        assertEq(borrowedOhm, DEFAULT_BORROW_AMOUNT, "preview borrowed OHM");
        assertEq(feeCollateral, preview.fee, "preview fee");
        assertEq(totalDebtOhm, preview.resultingDebtOhm, "preview debt");
        assertEq(maturity, preview.maturity, "preview maturity");
        assertEq(healthFactor, preview.resultingHealthFactor, "preview health");
        assertEq(ohm.balanceOf(alice), DEFAULT_BORROW_AMOUNT, "single mint");
        assertEq(
            burnerLoans.assetActiveDebtOhm(address(feeToken)),
            DEFAULT_BORROW_AMOUNT,
            "single debt increase"
        );
        assertEq(
            burnerLoans.getActiveBorrowers(address(feeToken)).length,
            1,
            "single index insertion"
        );
    }

    // Condition tree:
    // - External interaction: injected MINTR attempts a nested borrow before minting
    // - Authorization: callback MINTR is authorized for the same owner
    // - Expected branch: nested borrow hits the transient guard; trusted outer mint occurs once
    function test_givenReentrantMintr_borrowCannotMintOrIndexTwice() public {
        _depositDefaultCollateral(alice);
        CallbackMinter callbackMinter = new CallbackMinter(kernel, address(ohm));
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(callbackMinter));
        _setAuthorizationAndExpectEvent(
            alice,
            address(callbackMinter),
            uint48(block.timestamp + 1 days)
        );
        callbackMinter.setCallback(
            address(burnerLoans),
            abi.encodeCall(
                burnerLoans.borrow,
                (address(usds), 1e9, alice, alice, type(uint256).max)
            )
        );
        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            DEFAULT_BORROW_AMOUNT,
            alice
        );

        vm.prank(alice);
        (
            uint256 borrowedOhm,
            uint256 feeCollateral,
            uint256 totalDebtOhm,
            uint48 maturity,
            uint256 healthFactor
        ) = burnerLoans.borrow(address(usds), DEFAULT_BORROW_AMOUNT, alice, alice, preview.fee);

        assertFalse(callbackMinter.callbackSucceeded(), "MINTR callback blocked");
        assertEq(
            callbackMinter.callbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "MINTR callback guard"
        );
        assertEq(borrowedOhm, DEFAULT_BORROW_AMOUNT, "preview borrowed OHM");
        assertEq(feeCollateral, preview.fee, "preview fee");
        assertEq(totalDebtOhm, preview.resultingDebtOhm, "preview debt");
        assertEq(maturity, preview.maturity, "preview maturity");
        assertEq(healthFactor, preview.resultingHealthFactor, "preview health");
        assertEq(ohm.balanceOf(alice), DEFAULT_BORROW_AMOUNT, "single MINTR mint");
        assertEq(burnerLoans.totalActiveDebtOhm(), DEFAULT_BORROW_AMOUNT, "single debt increase");
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 1, "single index insertion");
    }

    // Condition tree:
    // - Asset cap: fuzzed borrow amount exactly equals the cap
    // - Global cap: sufficient
    // - Expected branch: exact cap boundary succeeds without one-unit headroom
    function test_givenBorrowAtAssetCap_borrowSucceeds(uint96 ohmAmount_) public {
        uint128 amount = uint128(bound(uint256(ohmAmount_), 1, DEFAULT_BORROW_AMOUNT));
        _depositDefaultCollateral(alice);
        vm.prank(admin);
        burnerLoans.setAssetDebtCap(address(usds), amount);

        _borrowWithPreview(alice, alice, alice, amount);

        assertEq(burnerLoans.assetActiveDebtOhm(address(usds)), amount, "exact asset cap");
    }

    // Condition tree:
    // - Global cap: fuzzed borrow amount exactly equals the cap
    // - Asset cap: reduced first so it remains compatible with the global cap
    // - Expected branch: exact global-cap boundary succeeds without one-unit headroom
    function test_givenBorrowAtGlobalCap_borrowSucceeds(uint96 ohmAmount_) public {
        uint128 amount = uint128(bound(uint256(ohmAmount_), 1, DEFAULT_BORROW_AMOUNT));
        _depositDefaultCollateral(alice);
        vm.startPrank(admin);
        burnerLoans.setAssetDebtCap(address(usds), amount);
        burnerLoans.setGlobalDebtCap(amount);
        vm.stopPrank();

        _borrowWithPreview(alice, alice, alice, amount);

        assertEq(burnerLoans.totalActiveDebtOhm(), amount, "exact global cap");
    }

    // Condition tree:
    // - Asset debt: cap minus fuzzed remaining capacity
    // - Borrow amount: remaining capacity plus a fuzzed excess of at least one unit
    // - Global capacity: sufficient
    // - Expected branch: preview and write reject every resulting debt above the asset cap
    function test_givenExistingAssetDebt_borrowAboveRemainingAssetCapReverts_fuzz(
        uint96 remainingCapacity_,
        uint96 excess_
    ) public {
        uint256 remainingCapacity = bound(uint256(remainingCapacity_), 1, DEFAULT_BORROW_AMOUNT);
        uint256 excess = bound(uint256(excess_), 1, DEFAULT_BORROW_AMOUNT);
        uint128 borrowAmount = uint128(remainingCapacity + excess);
        uint256 assetCap = burnerLoans.getAssetConfig(address(usds)).debtCap;
        uint256 existingAssetDebt = assetCap - remainingCapacity;
        _depositDefaultCollateral(alice);
        burnerLoans.setActiveDebtForTest(address(usds), existingAssetDebt, existingAssetDebt);

        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_AssetDebtCapExceeded.selector,
            address(usds),
            borrowAmount,
            remainingCapacity
        );
        _expectBorrowAndPreviewRevert(error, borrowAmount);
    }

    // Condition tree:
    // - Asset debt: cap minus the fuzzed borrow amount
    // - Borrow amount: exactly all remaining asset capacity
    // - Global capacity: sufficient
    // - Expected branch: resulting asset debt equals, but never exceeds, the asset cap
    function test_givenExistingAssetDebt_borrowRemainingAssetCapSucceeds(uint96 ohmAmount_) public {
        uint128 amount = uint128(bound(uint256(ohmAmount_), 1, DEFAULT_BORROW_AMOUNT));
        uint256 assetCap = burnerLoans.getAssetConfig(address(usds)).debtCap;
        uint256 existingDebt = assetCap - amount;
        _depositDefaultCollateral(alice);
        usds.mint(alice, 100e18);
        burnerLoans.setActiveDebtForTest(address(usds), existingDebt, existingDebt);

        _borrowWithPreview(alice, alice, alice, amount);

        uint256 resultingAssetDebt = burnerLoans.assetActiveDebtOhm(address(usds));
        assertEq(resultingAssetDebt, assetCap, "remaining asset capacity reaches cap");
        assertLe(resultingAssetDebt, assetCap, "resulting asset debt does not exceed cap");
    }

    // Condition tree:
    // - Global debt: cap minus fuzzed remaining capacity
    // - Borrow amount: remaining capacity plus a fuzzed excess of at least one unit
    // - Asset capacity: sufficient
    // - Expected branch: preview and write reject every resulting debt above the global cap
    function test_givenExistingGlobalDebt_borrowAboveRemainingGlobalCapReverts_fuzz(
        uint96 remainingCapacity_,
        uint96 excess_
    ) public {
        uint256 remainingCapacity = bound(uint256(remainingCapacity_), 1, DEFAULT_BORROW_AMOUNT);
        uint256 excess = bound(uint256(excess_), 1, DEFAULT_BORROW_AMOUNT);
        uint128 borrowAmount = uint128(remainingCapacity + excess);
        uint256 globalCap = burnerLoans.globalDebtCapOhm();
        uint256 existingGlobalDebt = globalCap - remainingCapacity;
        _depositDefaultCollateral(alice);
        _setOtherMarketDebtForTest(uint128(existingGlobalDebt));

        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_GlobalDebtCapExceeded.selector,
            borrowAmount,
            remainingCapacity
        );
        _expectBorrowAndPreviewRevert(error, borrowAmount);
    }

    // Condition tree:
    // - Global debt: cap minus the fuzzed borrow amount
    // - Borrow amount: exactly all remaining global capacity
    // - Asset capacity: sufficient
    // - Expected branch: resulting global debt equals, but never exceeds, the global cap
    function test_givenExistingGlobalDebt_borrowRemainingGlobalCapSucceeds(
        uint96 ohmAmount_
    ) public {
        uint128 amount = uint128(bound(uint256(ohmAmount_), 1, DEFAULT_BORROW_AMOUNT));
        uint256 globalCap = burnerLoans.globalDebtCapOhm();
        uint256 existingGlobalDebt = globalCap - amount;
        _depositDefaultCollateral(alice);
        _setOtherMarketDebtForTest(uint128(existingGlobalDebt));

        _borrowWithPreview(alice, alice, alice, amount);

        uint256 resultingGlobalDebt = burnerLoans.totalActiveDebtOhm();
        assertEq(resultingGlobalDebt, globalCap, "remaining global capacity reaches cap");
        assertLe(resultingGlobalDebt, globalCap, "resulting global debt does not exceed cap");
    }

    // Condition tree:
    // - Timestamp: fuzzed across the uint48-safe deployment horizon
    // - Debt episode: first borrow
    // - Expected branch: preview/write maturity is exactly timestamp plus termLength
    function test_givenFuzzedTimestamp_firstBorrowSetsExactTermMaturity(uint40 timestamp_) public {
        uint48 timestamp = timestamp_ == 0 ? 1 : timestamp_;
        vm.warp(timestamp);
        price.setTimestamp(timestamp);
        _depositDefaultCollateral(alice);

        IBurnerLoans.BorrowPreview memory preview = _borrowWithPreview(
            alice,
            alice,
            alice,
            DEFAULT_BORROW_AMOUNT
        );

        assertEq(preview.maturity, timestamp + 30 days, "fuzzed maturity");
    }

    // Condition tree:
    // - Borrow sequence: two fuzzed positive amounts totaling at most 100 OHM
    // - Time: second borrow occurs in a later block before maturity
    // - Expected branch: exact cumulative debt/mint, one index entry, and preserved maturity
    function test_givenFuzzedMultipleBorrows_debtAndIndexRemainExact(
        uint64 firstAmount_,
        uint64 secondAmount_
    ) public {
        uint128 firstAmount = uint128(bound(uint256(firstAmount_), 1, 50e9));
        uint128 secondAmount = uint128(bound(uint256(secondAmount_), 1, 50e9));
        _depositDefaultCollateral(alice);

        IBurnerLoans.BorrowPreview memory firstPreview = _borrowWithPreview(
            alice,
            alice,
            alice,
            firstAmount
        );
        vm.roll(block.number + 1);
        IBurnerLoans.BorrowPreview memory secondPreview = _borrowWithPreview(
            alice,
            alice,
            alice,
            secondAmount
        );

        uint256 total = firstAmount + secondAmount;
        assertEq(secondPreview.resultingDebtOhm, total, "fuzzed cumulative debt");
        assertEq(secondPreview.maturity, firstPreview.maturity, "fuzzed preserved maturity");
        assertEq(ohm.balanceOf(alice), total, "fuzzed cumulative mint");
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 1, "single index entry");
    }

    // Condition tree:
    // - Caller: fuzzed caller that is neither owner nor authorized operator
    // - Authorization state: owner has authorized only `operator`
    // - Parameters: onBehalfOf is owner, recipient is fuzzed caller
    // - Expected branch: authorization check reverts for every non-owner, non-operator caller
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != alice);
        vm.assume(caller_ != operator);

        _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));

        vm.prank(caller_);
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        burnerLoans.borrow(address(usds), 1e9, alice, caller_, 0);
    }
}
