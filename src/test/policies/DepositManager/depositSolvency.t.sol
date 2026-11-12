// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.27;

// Scenario-specific raw-unit literals make rounding boundaries explicit.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IERC20Errors} from "@openzeppelin-5.7.0/interfaces/draft-IERC6093.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";

// Libraries
import {Math} from "@openzeppelin-5.7.0/utils/math/Math.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {DepositManagerTest} from "./DepositManagerTest.sol";
import {DepositSettlementVault} from "./fixtures/DepositSettlementVault.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";

contract DepositManagerDepositSolvencyTest is DepositManagerTest {
    DepositSettlementVault internal _settlementVault;

    function setUp() public override {
        super.setUp();
        // A fresh underlying leaves the entire uint256 supply domain available.
        asset = new MockERC20("Solvency asset", "SOLV", 18);
        iAsset = IERC20(address(asset));
        vault = new MockERC4626(ERC20(address(asset)), "Solvency vault", "SV");
        iVault = IERC4626(address(vault));
    }

    function _configure(IERC4626 vault_) internal {
        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.addAsset(iAsset, vault_, type(uint256).max, 0);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "sol");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD + 1, DEPOSIT_OPERATOR);
        vm.stopPrank();
    }

    function _fund(uint256 amount_) internal {
        asset.mint(DEPOSITOR, amount_);
        _approveSpendingAsset(DEPOSITOR, amount_);
    }

    function _execute(
        uint256 amount_,
        uint8 period_,
        bool wrapped_
    ) internal returns (uint256 credit) {
        vm.prank(DEPOSIT_OPERATOR);
        (, credit) = depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: period_,
                depositor: DEPOSITOR,
                amount: amount_,
                shouldWrap: wrapped_
            })
        );
    }

    function _expectInsolvent(uint256 liabilities_, uint256 assets_, uint256 borrowed_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_Insolvent.selector,
                address(asset),
                liabilities_,
                assets_,
                borrowed_
            )
        );
    }

    function _ledgerHash() internal view returns (bytes32) {
        (uint256 firstId, address firstWrapper) = depositManager.getReceiptToken(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
        (uint256 secondId, address secondWrapper) = depositManager.getReceiptToken(
            iAsset,
            DEPOSIT_PERIOD + 1,
            DEPOSIT_OPERATOR
        );
        bytes32 receipts = keccak256(
            abi.encode(
                receiptTokenManager.balanceOf(DEPOSITOR, firstId),
                receiptTokenManager.balanceOf(DEPOSITOR, secondId),
                IERC20(firstWrapper).balanceOf(DEPOSITOR),
                ERC20(firstWrapper).totalSupply(),
                IERC20(secondWrapper).balanceOf(DEPOSITOR),
                ERC20(secondWrapper).totalSupply(),
                receiptTokenManager.balanceOf(firstWrapper, firstId),
                receiptTokenManager.balanceOf(secondWrapper, secondId)
            )
        );
        (uint256 shares, uint256 assets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );
        return
            keccak256(
                abi.encode(
                    receipts,
                    shares,
                    assets,
                    depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
                    depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
                    depositManager.getAssetDepositCapStatus(iAsset).utilization
                )
            );
    }

    function _custodyHash(IERC4626 vault_) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    asset.balanceOf(DEPOSITOR),
                    asset.allowance(DEPOSITOR, address(depositManager)),
                    asset.balanceOf(address(depositManager)),
                    asset.balanceOf(address(vault_)),
                    asset.totalSupply(),
                    vault_.balanceOf(address(depositManager)),
                    vault_.totalSupply(),
                    asset.allowance(address(depositManager), address(vault_)),
                    _ledgerHash()
                )
            );
    }

    function _assertNamespace(
        uint256 shares_,
        uint256 assets_,
        uint256 liabilities_,
        uint256 borrowed_
    ) internal view {
        (uint256 shares, uint256 assets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );
        assertEq(shares, shares_, "Recorded custody shares");
        assertEq(assets, assets_, "Live custody value");
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            liabilities_,
            "Receipt liabilities"
        );
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            borrowed_,
            "Borrowed principal"
        );
    }

    function _idleDeposit(uint256 amount_) internal {
        _configure(IERC4626(address(0)));
        _fund(amount_);
        (uint256 quoted, uint256 shares) = depositManager.previewDeposit(iAsset, amount_);
        assertEq(quoted, amount_, "Idle quote credit");
        assertEq(shares, amount_, "Idle quote shares");
        assertEq(_execute(amount_, DEPOSIT_PERIOD, false), amount_, "Idle execution credit");
        _assertNamespace(amount_, amount_, amount_, 0);
        uint256 receipt = depositManager.getReceiptTokenId(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
        assertEq(
            receiptTokenManager.balanceOf(DEPOSITOR, receipt),
            amount_,
            "Exact unwrapped receipt credit"
        );
        assertEq(asset.balanceOf(DEPOSITOR), 0, "Entire input settled into idle custody");
        assertEq(
            asset.allowance(DEPOSITOR, address(depositManager)),
            amount_ == type(uint256).max ? amount_ : 0,
            "Token preserves only its infinite allowance"
        );
        assertEq(
            depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR),
            0,
            "Equality has no claimable yield"
        );
        assertEq(asset.balanceOf(address(depositManager)), amount_, "Exact idle custody");
        assertEq(
            depositManager.getAssetDepositCapStatus(iAsset).utilization,
            amount_,
            "Principal utilization"
        );
    }

    // Scenarios: DM-DEPOSIT-P01, DM-DEPOSIT-N02.
    function test_whenIdleAmountAcrossUint256Domain(uint256 amount_) public {
        _idleDeposit(bound(amount_, 1, type(uint256).max));
    }

    // Scenarios: DM-DEPOSIT-P01, DM-DEPOSIT-N02.
    function test_whenIdleAmountIsOne() public {
        _idleDeposit(1);
    }

    // Scenarios: DM-DEPOSIT-P01, DM-DEPOSIT-N02.
    function test_whenIdleAmountIsUint256Maximum() public {
        _idleDeposit(type(uint256).max);
    }

    // Scenarios: DM-DEPOSIT-P02.
    function test_givenSolventBelowOneSharePrice_whenDepositing() public {
        asset.mint(address(this), 100);
        asset.approve(address(vault), 100);
        vault.deposit(100, address(this));
        asset.burn(address(vault), 20);
        _configure(iVault);
        _fund(88);
        _execute(80, DEPOSIT_PERIOD, false);
        _assertNamespace(100, 80, 80, 0);
        (uint256 quote, uint256 shares) = depositManager.previewDeposit(iAsset, 8);
        assertEq(quote, 8, "Below-one quote credit");
        assertEq(shares, 10, "Below-one quote shares");
        assertEq(_execute(8, DEPOSIT_PERIOD, false), 8, "Below-one execution credit");
        _assertNamespace(110, 88, 88, 0);
    }

    // Scenarios: DM-DEPOSIT-I01.
    function test_givenInsolventAboveOneSharePrice_whenDepositing_reverts(
        bool existingWrapped_,
        bool newWrapped_
    ) public {
        asset.mint(address(this), 100);
        asset.approve(address(vault), 100);
        vault.deposit(100, address(this));
        asset.mint(address(vault), 30);
        _configure(iVault);
        _fund(142);
        _execute(130, DEPOSIT_PERIOD, existingWrapped_);
        asset.burn(address(vault), 20);
        _assertNamespace(100, 120, 130, 0);
        (uint256 quote, uint256 shares) = depositManager.previewDeposit(iAsset, 12);
        assertEq(quote, 12, "Above-one quote credit");
        assertEq(shares, 10, "Above-one quote shares");
        bytes32 beforeState = _custodyHash(iVault);
        _expectInsolvent(142, 132, 0);
        _execute(12, DEPOSIT_PERIOD, newWrapped_);
        assertEq(_custodyHash(iVault), beforeState, "Above-one rejection rolls back every ledger");
    }

    // Scenarios: DM-DEPOSIT-I02, DM-DEPOSIT-I03, DM-DEPOSIT-P08.
    function test_givenLossAcrossPeriods_whenDepositing_revertsAndRollsBack(
        bool existingWrapped_,
        bool secondWrapped_,
        bool newWrapped_
    ) public {
        _configure(iVault);
        _fund(108);
        _execute(60, DEPOSIT_PERIOD, existingWrapped_);
        _execute(40, DEPOSIT_PERIOD + 1, secondWrapped_);
        asset.burn(address(vault), 20);
        (uint256 quote, uint256 shares) = depositManager.previewDeposit(iAsset, 8);
        assertEq(quote, 8, "Loss quote remains available");
        assertEq(shares, 10, "Loss quote shares");
        bytes32 beforeState = _custodyHash(iVault);
        _expectInsolvent(108, 88, 0);
        _execute(8, DEPOSIT_PERIOD + 1, newWrapped_);
        assertEq(_custodyHash(iVault), beforeState, "Both periods and wrapped supply roll back");
    }

    function _proportionalDeficit(
        uint256 liabilities_,
        uint256 deficit_,
        uint256 amount_,
        bool existingWrapped_,
        bool newWrapped_
    ) internal {
        uint256 backing = liabilities_ - deficit_;
        uint256 shares = Math.mulDiv(amount_, liabilities_, backing);
        uint256 finalAssets = backing + amount_;
        uint256 credit = Math.mulDiv(shares, finalAssets, liabilities_ + shares);
        vm.assume(credit != 0);
        _configure(iVault);
        _fund(liabilities_);
        _execute(liabilities_, DEPOSIT_PERIOD, existingWrapped_);
        asset.burn(address(vault), deficit_);
        _fund(amount_);
        bytes32 beforeState = _custodyHash(iVault);
        // O owns all shares: its final custody value is exactly backing+A, independently of preview.
        _expectInsolvent(liabilities_ + credit, finalAssets, 0);
        _execute(amount_, DEPOSIT_PERIOD, newWrapped_);
        assertEq(_custodyHash(iVault), beforeState, "Proportional-deficit rejection is atomic");
    }

    // Scenarios: DM-DEPOSIT-N01.
    function test_givenProportionalDeficit_whenDepositingAcrossRepresentableDomain(
        uint256 liabilities_,
        uint256 deficit_,
        uint256 amount_,
        bool existingWrapped_,
        bool newWrapped_
    ) public {
        liabilities_ = bound(liabilities_, 3, type(uint256).max / 2);
        deficit_ = bound(deficit_, 2, liabilities_ - 1);
        // Ensures liabilities+shares, liabilities+credit, backing+input and total token supply fit.
        // floor(A*L/backing) <= MAX-L iff A < (MAX-L+1)*backing/L.
        uint256 maximumAmount = Math.mulDiv(
            type(uint256).max - liabilities_ + 1,
            liabilities_ - deficit_,
            liabilities_,
            Math.Rounding.Ceil
        ) - 1;
        _proportionalDeficit(
            liabilities_,
            deficit_,
            bound(amount_, 1, maximumAmount),
            existingWrapped_,
            newWrapped_
        );
    }

    // Scenarios: DM-DEPOSIT-N01.
    function test_givenTwoUnitDeficit_whenDepositing_reverts(
        bool existingWrapped_,
        bool newWrapped_
    ) public {
        _proportionalDeficit(100, 2, 98, existingWrapped_, newWrapped_);
    }

    // Scenarios: DM-DEPOSIT-N01.
    function test_givenMaximumProportionalDeficit_whenDepositing_reverts(
        bool existingWrapped_,
        bool newWrapped_
    ) public {
        _proportionalDeficit(100, 99, 1, existingWrapped_, newWrapped_);
    }

    // Scenarios: DM-DEPOSIT-N03.
    function test_givenOneUnitRemainingDeficit_whenDepositing_reverts(
        bool existingWrapped_,
        bool newWrapped_
    ) public {
        _configure(iVault);
        _fund(199);
        _execute(100, DEPOSIT_PERIOD, existingWrapped_);
        asset.burn(address(vault), 1);
        bytes32 beforeState = _custodyHash(iVault);
        _expectInsolvent(199, 198, 0);
        _execute(99, DEPOSIT_PERIOD, newWrapped_);
        assertEq(_custodyHash(iVault), beforeState, "One-unit deficit rolls back");
    }

    // Scenarios: DM-DEPOSIT-P09.
    function test_givenOneUnitLoss_whenRoundingFullyRepairsDeficit() public {
        _configure(iVault);
        _fund(102);
        _execute(100, DEPOSIT_PERIOD, false);
        asset.burn(address(vault), 1);
        (uint256 quote, uint256 shares) = depositManager.previewDeposit(iAsset, 2);
        assertEq(shares, 2, "floor(2*100/99)=2 raw shares");
        assertEq(quote, 1, "floor(2*99/100)=1 raw asset quote");
        // Post-call credit=floor(2*101/102)=1; total backing=101 and liabilities=100+1.
        assertEq(_execute(2, DEPOSIT_PERIOD, false), 1, "Rounding-funded cure credits one");
        _assertNamespace(102, 101, 101, 0);
        uint256 receipt = depositManager.getReceiptTokenId(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
        assertEq(
            receiptTokenManager.balanceOf(DEPOSITOR, receipt),
            101,
            "Exactly one receipt added to the existing hundred"
        );
        assertEq(asset.balanceOf(DEPOSITOR), 0, "Payer spends two raw units");
    }

    // Scenarios: DM-DEPOSIT-P03, DM-DEPOSIT-N02.
    function test_givenBorrowedPrincipal_whenFinalSolvencyIsEquality() public {
        _configure(IERC4626(address(0)));
        _fund(110);
        _execute(100, DEPOSIT_PERIOD, false);
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: 40
            })
        );
        _assertNamespace(60, 60, 100, 40);
        (uint256 quote, uint256 shares) = depositManager.previewDeposit(iAsset, 10);
        assertEq(quote, 10, "Borrowed principal does not change conversion credit");
        assertEq(shares, 10, "Borrowed principal does not change idle custody quote");
        assertEq(_execute(10, DEPOSIT_PERIOD, false), 10, "Deposit with debt succeeds");
        _assertNamespace(70, 70, 110, 40);
    }

    // Scenarios: DM-DEPOSIT-P04.
    function test_givenOtherOperatorIsInsolvent_whenIndependentOperatorDeposits() public {
        _configure(iVault);
        _fund(108);
        _execute(100, DEPOSIT_PERIOD, false);
        asset.burn(address(vault), 20);
        vm.startPrank(ADMIN);
        rolesAdmin.grantRole("deposit_operator", RECIPIENT);
        depositManager.setOperatorName(RECIPIENT, "oth");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, RECIPIENT);
        vm.stopPrank();
        (uint256 quote, uint256 quotedShares) = depositManager.previewDeposit(iAsset, 8);
        assertEq(quote, 8, "Independent namespace quote credit");
        assertEq(quotedShares, 10, "Independent namespace quote custody");
        vm.prank(RECIPIENT);
        (, uint256 credit) = depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: 8,
                shouldWrap: false
            })
        );
        assertEq(credit, 8, "Independent namespace credit");
        _assertNamespace(100, 80, 100, 0);
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, RECIPIENT),
            8,
            "Only independent liabilities change"
        );
        (uint256 shares, uint256 assets) = depositManager.getOperatorAssets(iAsset, RECIPIENT);
        assertEq(shares, 10, "Independent namespace recorded custody");
        assertEq(assets, 8, "Independent namespace live custody value");
        uint256 receipt = depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD, RECIPIENT);
        assertEq(
            receiptTokenManager.balanceOf(DEPOSITOR, receipt),
            8,
            "Independent namespace receipt credit"
        );
    }

    function _configureSettlementVault() internal {
        _settlementVault = new DepositSettlementVault(asset);
        _configure(IERC4626(address(_settlementVault)));
    }

    // Scenarios: DM-DEPOSIT-T01.
    function test_givenSolventOperator_whenVaultRealizesLossDuringDeposit_reverts(
        bool existingWrapped_,
        bool newWrapped_
    ) public {
        _configureSettlementVault();
        _fund(110);
        _execute(100, DEPOSIT_PERIOD, existingWrapped_);
        _settlementVault.setSettlementLoss(22);
        bytes32 beforeState = _custodyHash(IERC4626(address(_settlementVault)));
        // Mint ten shares, then burn 22 assets: new ten-share credit=8; final assets=88 < L=108.
        _expectInsolvent(108, 88, 0);
        _execute(10, DEPOSIT_PERIOD, newWrapped_);
        assertEq(
            _custodyHash(IERC4626(address(_settlementVault))),
            beforeState,
            "Realized loss and deposit both roll back"
        );
    }

    // Scenarios: DM-DEPOSIT-P05.
    function test_givenInsolventOperator_whenVaultRealizesYieldDuringDeposit() public {
        _configureSettlementVault();
        _fund(108);
        _execute(100, DEPOSIT_PERIOD, false);
        asset.burn(address(_settlementVault), 20);
        _settlementVault.setSettlementYield(22);
        assertEq(
            _execute(8, DEPOSIT_PERIOD, false),
            10,
            "Actual settled ten-share value includes genuine yield"
        );
        _assertNamespace(110, 110, 110, 0);
    }

    // Scenarios: DM-DEPOSIT-P06.
    function test_givenPartialDonation_whenDepositing_revertsAndRetainsDonation(
        bool existingWrapped_,
        bool newWrapped_
    ) public {
        _configure(iVault);
        _fund(116);
        _execute(100, DEPOSIT_PERIOD, existingWrapped_);
        asset.burn(address(vault), 20);
        vm.prank(DEPOSITOR);
        depositManager.donate(iAsset, DEPOSIT_OPERATOR, 8);
        _assertNamespace(110, 88, 100, 0);
        bytes32 beforeState = _custodyHash(iVault);
        _expectInsolvent(108, 96, 0);
        _execute(8, DEPOSIT_PERIOD, newWrapped_);
        assertEq(
            _custodyHash(iVault),
            beforeState,
            "Earlier donation persists after rejected deposit"
        );
    }

    // Scenarios: DM-DEPOSIT-P07.
    function test_givenFullDonation_whenDepositingAndWithdrawing() public {
        _configure(iVault);
        _fund(128);
        _execute(100, DEPOSIT_PERIOD, false);
        asset.burn(address(vault), 20);
        vm.prank(DEPOSITOR);
        depositManager.donate(iAsset, DEPOSIT_OPERATOR, 20);
        _assertNamespace(125, 100, 100, 0);
        assertEq(
            depositManager.getAssetDepositCapStatus(iAsset).utilization,
            100,
            "Donation adds no cap utilization"
        );
        uint256 receipt = depositManager.getReceiptTokenId(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
        assertEq(
            receiptTokenManager.balanceOf(DEPOSITOR, receipt),
            100,
            "Donation adds no receipt claim"
        );
        (uint256 quote, uint256 shares) = depositManager.previewDeposit(iAsset, 8);
        assertEq(quote, 8, "Restored conversion quote credit");
        assertEq(shares, 10, "Restored conversion quote shares");
        assertEq(_execute(8, DEPOSIT_PERIOD, false), 8, "Deposit resumes after full repair");
        assertEq(
            receiptTokenManager.balanceOf(DEPOSITOR, receipt),
            108,
            "Deposit alone adds eight receipt claims"
        );
        vm.prank(DEPOSITOR);
        receiptTokenManager.approve(address(depositManager), receipt, 8);
        assertEq(_withdraw(8, false), 8, "Existing-holder withdrawal resumes");
        _assertNamespace(125, 100, 100, 0);
        assertEq(
            receiptTokenManager.balanceOf(DEPOSITOR, receipt),
            100,
            "Withdrawal burns exactly eight receipt claims"
        );
    }

    // Scenarios: DM-DEPOSIT-I04.
    function test_givenInsolventOperator_whenCallerIsUnauthorized_revertsRoleFirst(
        address caller_,
        bool existingWrapped_,
        bool newWrapped_
    ) public {
        vm.assume(caller_ != DEPOSIT_OPERATOR);
        _configure(iVault);
        _fund(108);
        _execute(100, DEPOSIT_PERIOD, existingWrapped_);
        asset.burn(address(vault), 20);
        bytes32 beforeState = _custodyHash(iVault);
        _expectRevertNotDepositOperator();
        vm.prank(caller_);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: 8,
                shouldWrap: newWrapped_
            })
        );
        assertEq(_custodyHash(iVault), beforeState, "Role failure changes no custody");
    }

    // Scenarios: DM-DEPOSIT-I05.
    function test_givenInsolventOperator_givenDisabledPeriod_whenDepositing_revertsPeriodFirst(
        bool existingWrapped_,
        bool newWrapped_
    ) public {
        _configure(iVault);
        _fund(108);
        _execute(100, DEPOSIT_PERIOD, existingWrapped_);
        asset.burn(address(vault), 20);
        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        bytes32 beforeState = _custodyHash(iVault);
        _expectRevertAssetPeriodDisabled(iAsset, DEPOSIT_PERIOD);
        _execute(8, DEPOSIT_PERIOD, newWrapped_);
        assertEq(_custodyHash(iVault), beforeState, "Period failure changes no custody");
    }

    // Scenarios: DM-DEPOSIT-I06.
    function test_givenInsolventOperator_whenAllowanceIsInsufficient_revertsAllowanceFirst(
        bool existingWrapped_,
        bool newWrapped_
    ) public {
        _configure(iVault);
        _fund(108);
        _execute(100, DEPOSIT_PERIOD, existingWrapped_);
        asset.burn(address(vault), 20);
        _approveSpendingAsset(DEPOSITOR, 7);
        bytes32 beforeState = _custodyHash(iVault);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(depositManager),
                7,
                8
            )
        );
        _execute(8, DEPOSIT_PERIOD, newWrapped_);
        assertEq(_custodyHash(iVault), beforeState, "Allowance failure precedes final solvency");
    }

    // Scenarios: DM-DEPOSIT-C01.
    function test_givenVaultCallback_whenEligibleDonationReenters_rejectsNestedAndCreditsOnce()
        public
    {
        _configureSettlementVault();
        _fund(100);
        asset.mint(address(_settlementVault), 2);
        _settlementVault.approveAsset(address(depositManager), 2);
        _settlementVault.setCallback(
            address(depositManager),
            abi.encodeCall(IDepositManagerV1_1.donate, (iAsset, DEPOSIT_OPERATOR, 2))
        );
        assertEq(
            _execute(100, DEPOSIT_PERIOD, false),
            102,
            "Outer deposit credits its settled custody once"
        );
        assertFalse(_settlementVault.callbackSucceeded(), "Nested donation rejects");
        assertEq(
            _settlementVault.callbackResult(),
            abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector),
            "Shared transient guard rejects nested donation"
        );
        _assertNamespace(100, 102, 102, 0);
    }

    // Scenarios: DM-DEPOSIT-N02.
    function test_givenReEnabled_whenSolventDeposit() public {
        _configure(iVault);
        _fund(1);
        vm.startPrank(ADMIN);
        depositManager.disable("");
        depositManager.enable("");
        vm.stopPrank();
        assertEq(_execute(1, DEPOSIT_PERIOD, false), 1, "Re-enabled deposit");
    }

    // Scenarios: DM-DEPOSIT-N02.
    function test_givenPolicyReactivated_whenSolventDeposit() public {
        _configure(iVault);
        _fund(1);
        vm.startPrank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        kernel.executeAction(Actions.ActivatePolicy, address(depositManager));
        vm.stopPrank();
        assertEq(_execute(1, DEPOSIT_PERIOD, false), 1, "Reactivated deposit");
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
