// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20 as OZERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansAuth} from "src/policies/interfaces/burnerloans/IBurnerLoansAuth.sol";
import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {DEPOSIT_OPERATOR_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansCollateralInsolvencyTest} from "./fixtures/BurnerLoansCollateralInsolvencyTest.sol";
import {BurnerLoansCollateralLossVault} from "./fixtures/BurnerLoansCollateralLossVault.sol";
import {Actions} from "src/Kernel.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {MockERC7540ExternalShareVault} from "src/test/mocks/MockERC7540ExternalShareVault.sol";

// Fixed raw-unit fixtures distinguish final custody solvency from individual loan health.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,reentrancy-no-eth)
contract BurnerLoansCollateralDepositCollateralInsolvencyIntegrationTest is
    BurnerLoansCollateralInsolvencyTest
{
    // Scenarios: BLCOL-DEPOSIT-T10.
    function test_givenVaultLoss_whenExistingBorrowerDeposits_reverts() public {
        (MockERC20 token, MockERC4626 vault) = _seedLossVault(20);
        _fundLossDeposit(token, _borrower, 8);
        _assertLossQuote(token, _borrower, 8, 108);
        _expectLossDeposit(token, vault, _borrower, _borrower, 8, 108, 88);
    }

    // Scenarios: BLCOL-DEPOSIT-T10.
    function test_givenVaultLossAndOriginationsDisabled_whenExistingBorrowerDeposits_reverts()
        public
    {
        (MockERC20 token, MockERC4626 vault) = _seedLossVault(20);
        _config.setAssetOriginationsEnabled(address(token), false);
        _fundLossDeposit(token, _borrower, 8);
        _assertLossQuote(token, _borrower, 8, 108);
        _expectLossDeposit(token, vault, _borrower, _borrower, 8, 108, 88);
    }

    // Scenarios: BLCOL-DEPOSIT-T11.
    function test_givenVaultLoss_whenNewBorrowerDeposits_reverts() public {
        (MockERC20 token, MockERC4626 vault) = _seedLossVault(20);
        _fundLossDeposit(token, _OTHER_BORROWER, 8);
        _assertLossQuote(token, _OTHER_BORROWER, 8, 8);
        _expectLossDeposit(token, vault, _OTHER_BORROWER, _OTHER_BORROWER, 8, 108, 88);
        _assertNoNewBorrower(token);
    }

    // Scenarios: BLCOL-DEPOSIT-T11.
    function test_givenVaultLossAndOriginationsDisabled_whenNewBorrowerDeposits_reverts() public {
        (MockERC20 token, MockERC4626 vault) = _seedLossVault(20);
        _config.setAssetOriginationsEnabled(address(token), false);
        _fundLossDeposit(token, _OTHER_BORROWER, 8);
        _assertLossQuote(token, _OTHER_BORROWER, 8, 8);
        _expectLossDeposit(token, vault, _OTHER_BORROWER, _OTHER_BORROWER, 8, 108, 88);
        _assertNoNewBorrower(token);
    }

    // Scenarios: BLCOL-DEPOSIT-T12.
    function test_givenVaultLoss_whenAuthorizedOperatorDeposits_reverts() public {
        (MockERC20 token, MockERC4626 vault) = _seedLossVault(20);
        IOperatorAuth.Grant memory grant = _operatorGrantForAsset(
            _borrower,
            _recipient,
            type(uint48).max,
            address(token)
        );
        grant.actions = 1;
        IBurnerLoansAuth.Permissions memory permissions = abi.decode(
            grant.permissions,
            (IBurnerLoansAuth.Permissions)
        );
        permissions.maxCollateral = 108;
        grant.permissions = abi.encode(permissions);
        vm.prank(_borrower);
        _auth.approveGrant(grant);
        assertTrue(
            _auth.captureAuthorization(_borrower, _recipient, 1) != bytes32(0),
            "Current delegated grant is usable before the custody failure"
        );
        _fundLossDeposit(token, _recipient, 8);
        bytes memory failure = abi.encodeWithSelector(
            IDepositManager.DepositManager_Insolvent.selector
        );
        vm.mockCallRevert(
            address(_auth),
            abi.encodeWithSelector(IOperatorAuth.captureAuthorization.selector),
            failure
        );
        vm.mockCallRevert(address(_risk), bytes(""), failure);
        vm.mockCallRevert(address(_price), bytes(""), failure);
        _assertLossQuote(token, _borrower, 8, 108);
        vm.clearMockedCalls();
        _expectLossDeposit(token, vault, _recipient, _borrower, 8, 108, 88);
        assertEq(token.balanceOf(_recipient), 8, "Operator funding remains after rejected top-up");
    }

    // Scenarios: BLCOL-DEPOSIT-T13.
    function test_givenDebtAndVaultLoss_whenTopUpRefreshesCache_reverts() public {
        (MockERC20 token, MockERC4626 vault) = _seedLossVault(0);
        vm.prank(_borrower);
        _debt.borrow(address(token), 40e9, _borrower, _borrower, 0, address(0));
        PriceCache cache = new PriceCache(_kernel, 18, "USD");
        _kernel.executeAction(Actions.ActivatePolicy, address(cache));
        cache.enable("");
        _risk.setPriceCache(address(cache));
        _risk.setPriceCacheMaxAge(60);
        cache.cachePrice(address(_ohm), address(token));
        bytes32 beforeCache = keccak256(
            abi.encode(cache.getCachedPrice(address(_ohm), address(token)))
        );
        vm.warp(vm.getBlockTimestamp() + 61);
        _price.setTimestamp(uint48(vm.getBlockTimestamp()));
        _price.setPrice(address(token), 2e18);
        token.burn(address(vault), 20);
        _fundLossDeposit(token, _borrower, 8);
        _assertLossQuote(token, _borrower, 8, 108);
        vm.expectCall(
            address(cache),
            abi.encodeCall(
                cache.cachePriceIfNecessary,
                (address(_ohm), address(token), uint48(60))
            ),
            uint64(1)
        );
        _expectLossDeposit(token, vault, _borrower, _borrower, 8, 108, 88);
        assertEq(
            keccak256(abi.encode(cache.getCachedPrice(address(_ohm), address(token)))),
            beforeCache,
            "Final solvency failure rolls back the real cache refresh"
        );
        assertEq(
            _lens.getPosition(address(token), _borrower).debtOhm,
            40e9,
            "Rejected top-up preserves principal"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-N08.
    function test_givenOneUnitDeficit_whenCollateralDeposited_reverts() public {
        (MockERC20 token, MockERC4626 vault) = _seedLossVault(1);
        _fundLossDeposit(token, _borrower, 99);
        // 99 assets *100 shares /99 backing =100 shares. Post-deposit backing=198;
        // new credit=floor(100*198/200)=99, liabilities=199: exactly one short.
        _assertLossQuote(token, _borrower, 99, 199);
        _expectLossDeposit(token, vault, _borrower, _borrower, 99, 199, 198);
    }

    // Scenarios: BLCOL-DEPOSIT-T14.
    function test_givenSolventCustody_whenVaultRealizesLossDuringDeposit_reverts() public {
        MockERC20 token = new MockERC20("Callback Loss", "CL", 0);
        BurnerLoansCollateralLossVault vault = new BurnerLoansCollateralLossVault(
            OZERC20(address(token))
        );
        _admitVault(token, address(vault), false);
        _depositAsset(token, 100, _borrower);
        _fundLossDeposit(token, _borrower, 100);
        _assertLossQuote(token, _borrower, 100, 200);
        vault.setDepositLoss(20);
        // 100 new shares are worth floor(100*180/200)=90 after the callback loss.
        // Final liabilities=190 exceed custody=180; loss and mint must both roll back.
        _expectLossDeposit(token, vault, _borrower, _borrower, 100, 190, 180);
        assertEq(token.balanceOf(address(vault)), 100, "Realized callback loss rolls back");
    }

    // Scenarios: BLCOL-DEPOSIT-P16.
    function test_givenPartialDonation_whenBorrowerDeposits_reverts() public {
        (MockERC20 token, MockERC4626 vault) = _seedLossVault(20);
        _donateLossRepair(token, 8, 10, 88);
        _fundLossDeposit(token, _borrower, 8);
        _assertLossQuote(token, _borrower, 8, 108);
        _expectLossDeposit(token, vault, _borrower, _borrower, 8, 108, 96);
        assertEq(
            token.balanceOf(address(vault)),
            88,
            "Prior donation persists after rejected top-up"
        );
        assertEq(
            vault.balanceOf(address(_depositManager)),
            110,
            "Prior donation custody shares persist"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-P17.
    function test_givenFullDonation_whenBorrowerDepositsAndWithdraws() public {
        (MockERC20 token, MockERC4626 vault) = _seedLossVault(20);
        _donateLossRepair(token, 20, 25, 100);
        _fundLossDeposit(token, _borrower, 8);
        _assertLossQuote(token, _borrower, 8, 108);
        _assertSuccessfulLossTopUp(token, 8, 8, 108);
        IBurnerLoansCollateral.WithdrawPreview memory quote = _collateral.previewWithdrawCollateral(
            address(token),
            108,
            _borrower,
            _recipient
        );
        _assertWithdrawal(quote, address(token), 108, 0, type(uint256).max);
        vm.prank(_borrower);
        IBurnerLoansCollateral.WithdrawPreview memory actual = _collateral.withdrawCollateral(
            address(token),
            108,
            _borrower,
            _recipient
        );
        _assertWithdrawal(actual, address(token), 108, 0, type(uint256).max);
        assertEq(
            token.balanceOf(_recipient),
            108,
            "Existing and new collateral fully exit after repair"
        );
        assertEq(
            vault.balanceOf(address(_depositManager)),
            0,
            "Full withdrawal clears Core custody"
        );
        _assertLossLiability(token, 0);
    }

    // Scenarios: BLCOL-DEPOSIT-P18.
    function test_givenSolventCustodyBelowUnitExchangeRate_whenBorrowerDeposits() public {
        MockERC20 token = new MockERC20("Below Unit", "BU", 0);
        MockERC4626 vault = new MockERC4626(OZERC20(address(token)), "Below Unit Vault", "BUV");
        token.mint(address(this), 100);
        token.approve(address(vault), 100);
        vault.deposit(100, address(this));
        token.burn(address(vault), 20);
        _admitVault(token, address(vault), false);
        _depositAsset(token, 80, _borrower);
        _fundLossDeposit(token, _borrower, 8);
        _assertLossQuote(token, _borrower, 8, 88);
        _assertSuccessfulLossTopUp(token, 8, 8, 88);
        (uint256 shares, uint256 assets) = _depositManager.getOperatorAssets(
            IERC20(address(token)),
            address(_core)
        );
        assertEq(shares, 110, "Core owns independent shares at the reduced rate");
        assertEq(assets, 88, "Reduced exchange rate still fully backs Core liabilities");
    }

    // Scenarios: BLCOL-DEPOSIT-P20.
    function test_givenOtherOperatorInsolvent_whenCoreDeposits() public {
        address otherOperator = makeAddr("otherOperator");
        MockERC20 token = new MockERC20("Shared Vault", "SV", 0);
        MockERC4626 vault = new MockERC4626(OZERC20(address(token)), "Shared Vault", "SVV");
        _admitVault(token, address(vault), false);
        _rolesAdmin.grantRole(DEPOSIT_OPERATOR_ROLE, otherOperator);
        _depositManager.setOperatorName(otherOperator, "oth");
        _depositManager.addAssetPeriod(IERC20(address(token)), 1, otherOperator);
        token.mint(otherOperator, 100);
        vm.startPrank(otherOperator);
        token.approve(address(_depositManager), 100);
        _depositManager.deposit(
            IDepositManager.DepositParams(IERC20(address(token)), 1, otherOperator, 100, false)
        );
        vm.stopPrank();
        token.burn(address(vault), 20);
        _depositAsset(token, 80, _borrower);
        bytes32 beforeOther = _otherOperatorDigest(token, otherOperator);
        _fundLossDeposit(token, _borrower, 8);
        _assertLossQuote(token, _borrower, 8, 88);
        _assertSuccessfulLossTopUp(token, 8, 8, 88);
        assertEq(
            _otherOperatorDigest(token, otherOperator),
            beforeOther,
            "Core deposit preserves unrelated insolvent namespace"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-T15.
    function test_givenSeparateShareVaultLoss_whenBorrowerDeposits_reverts() public {
        _assertSeparateShareLoss(false);
    }

    // Scenarios: BLCOL-DEPOSIT-T15.
    function test_givenAsyncRedemptionVaultLoss_whenBorrowerDeposits_reverts() public {
        _assertSeparateShareLoss(true);
    }

    // Scenarios: BLCOL-DEPOSIT-P21.
    function test_givenOneUnitLoss_whenDepositRoundingRepairsCustody() public {
        (MockERC20 token, MockERC4626 vault) = _seedLossVault(1);
        _fundLossDeposit(token, _borrower, 2);
        // Input2 mints floor(2*100/99)=2 shares. Both pre-call quote
        // floor(2*99/100) and post-call credit floor(2*101/102) equal1.
        _assertLossQuote(token, _borrower, 1, 101, 2);
        _assertSuccessfulLossTopUp(token, 2, 1, 101);
        (uint256 shares, uint256 assets) = _depositManager.getOperatorAssets(
            IERC20(address(token)),
            address(_core)
        );
        assertEq(shares, 102, "Rounding cure adds both real shares");
        assertEq(assets, 101, "Final custody exactly covers repaired liability");
        assertEq(token.balanceOf(_borrower), 0, "Payer spends both raw units to cure deficit");
        assertEq(vault.totalAssets(), 101, "Vault receives full nominal top-up");
    }

    function _assertLossQuote(
        MockERC20 token_,
        address borrower_,
        uint256 credit_,
        uint256 collateral_
    ) internal {
        _assertLossQuote(token_, borrower_, credit_, collateral_, uint128(credit_));
    }

    function _assertLossQuote(
        MockERC20 token_,
        address borrower_,
        uint256 credit_,
        uint256 collateral_,
        uint128 amount_
    ) internal {
        bytes32 beforeQuote = _lossAccountingDigest(address(token_));
        vm.prank(makeAddr("unfundedViewer"));
        (uint256 credit, uint256 collateral) = _collateral.previewDepositCollateral(
            address(token_),
            amount_,
            borrower_
        );
        assertEq(
            credit,
            credit_,
            "Snapshot conversion quote remains readable despite custody deficit"
        );
        assertEq(collateral, collateral_, "Quote adds estimated credit to the specified borrower");
        assertEq(
            _lossAccountingDigest(address(token_)),
            beforeQuote,
            "Quote creates no settlement effects"
        );
    }

    function _assertNoNewBorrower(MockERC20 token_) internal view {
        assertEq(
            _floan.getPositionIdsForBorrower(_OTHER_BORROWER).length,
            0,
            "Failed first deposit leaves borrower index absent"
        );
        assertEq(
            _lens.getPosition(address(token_), _OTHER_BORROWER).depositedCollateral,
            0,
            "Failed first deposit creates no collateral"
        );
    }

    function _donateLossRepair(
        MockERC20 token_,
        uint256 amount_,
        uint256 shares_,
        uint256 assets_
    ) internal {
        uint64 positions = _floan.getPositionCount();
        address donor = makeAddr("unrelatedDonor");
        token_.mint(donor, amount_);
        vm.startPrank(donor);
        token_.approve(address(_depositManager), amount_);
        (uint256 credit, uint256 shares) = _depositManager.donate(
            IERC20(address(token_)),
            address(_core),
            amount_
        );
        vm.stopPrank();
        assertEq(token_.balanceOf(donor), 0, "Unrelated donor supplies the repair underlying");
        assertEq(credit, amount_, "Donation books real received backing");
        assertEq(shares, shares_, "Donation receives independent expected vault shares");
        (, uint256 assets) = _depositManager.getOperatorAssets(
            IERC20(address(token_)),
            address(_core)
        );
        assertEq(assets, assets_, "Donation increases custody backing");
        _assertLossLiability(token_, 100);
        assertEq(
            _lens.getPosition(address(token_), _borrower).depositedCollateral,
            100,
            "Donation creates no borrower collateral"
        );
        assertEq(_floan.getPositionCount(), positions, "Donation creates no FLOAN position");
        assertEq(
            _depositManager.getAssetDepositCapStatus(IERC20(address(token_))).utilization,
            100,
            "Donation consumes no aggregate principal cap"
        );
    }

    function _assertLossLiability(MockERC20 token_, uint256 collateral_) internal view {
        IERC20 asset = IERC20(address(token_));
        assertEq(
            _depositManager.getOperatorLiabilities(asset, address(_core)),
            collateral_,
            "Core liability matches only recorded collateral"
        );
        uint256 receiptId = _depositManager.getReceiptTokenId(asset, 1, address(_core));
        assertEq(
            _depositManager.getReceiptTokenManager().balanceOf(address(_core), receiptId),
            collateral_,
            "Receipts exclude donation backing"
        );
        assertEq(
            _floan.getMarketCollateral(_core.marketId(address(token_))),
            collateral_,
            "FLOAN aggregate matches borrower collateral"
        );
    }

    function _assertSuccessfulLossTopUp(
        MockERC20 token_,
        uint128 amount_,
        uint128 credit_,
        uint128 collateral_
    ) internal {
        vm.prank(_borrower);
        (uint128 credit, uint128 collateral, uint256 health) = _collateral.depositCollateral(
            address(token_),
            amount_,
            _borrower
        );
        assertEq(credit, credit_, "Real top-up credits independent expected amount");
        assertEq(collateral, collateral_, "Real top-up records expected total collateral");
        assertEq(health, type(uint256).max, "Debt-free top-up retains execution health");
        _assertLossLiability(token_, collateral_);
        assertEq(
            _lens.getPosition(address(token_), _borrower).depositedCollateral,
            collateral_,
            "Canonical borrower receives actual credit"
        );
        assertEq(token_.balanceOf(address(_core)), 0, "Core retains no transient underlying");
        assertEq(
            token_.balanceOf(address(_depositManager)),
            0,
            "All received underlying enters vault custody"
        );
    }

    function _otherOperatorDigest(
        MockERC20 token_,
        address operator_
    ) internal view returns (bytes32) {
        IERC20 asset = IERC20(address(token_));
        (uint256 shares, uint256 assets) = _depositManager.getOperatorAssets(asset, operator_);
        uint256 receiptId = _depositManager.getReceiptTokenId(asset, 1, operator_);
        return
            keccak256(
                abi.encode(
                    shares,
                    assets,
                    _depositManager.getOperatorLiabilities(asset, operator_),
                    _depositManager.getBorrowedAmount(asset, operator_),
                    _depositManager.getReceiptTokenManager().balanceOf(operator_, receiptId)
                )
            );
    }

    function _assertSeparateShareLoss(bool async_) internal {
        MockERC20 token = new MockERC20("External Loss", "EL", 18);
        MockERC7540ExternalShareVault vault = new MockERC7540ExternalShareVault(
            OZERC20(address(token)),
            false,
            async_,
            true
        );
        _admitVault(token, address(vault), true);
        _depositAsset(token, 100e18, _borrower);
        token.burn(address(vault), 20e18);
        _fundLossDeposit(token, _borrower, 8e18);
        _assertLossQuote(token, _borrower, 8e18, 108e18);
        bytes32 beforeState = keccak256(
            abi.encode(
                _lossAccountingDigest(address(token)),
                token.balanceOf(address(vault)),
                IERC20(vault.share()).totalSupply(),
                IERC20(vault.share()).balanceOf(address(_depositManager)),
                token.allowance(address(_depositManager), address(vault))
            )
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_Insolvent.selector,
                address(token),
                uint256(108e18),
                uint256(88e18),
                uint256(0)
            )
        );
        vm.prank(_borrower);
        _collateral.depositCollateral(address(token), 8e18, _borrower);
        assertEq(
            keccak256(
                abi.encode(
                    _lossAccountingDigest(address(token)),
                    token.balanceOf(address(vault)),
                    IERC20(vault.share()).totalSupply(),
                    IERC20(vault.share()).balanceOf(address(_depositManager)),
                    token.allowance(address(_depositManager), address(vault))
                )
            ),
            beforeState,
            "Separate-share loss failure restores vault and canonical accounting"
        );
        assertEq(
            IERC20(vault.share()).balanceOf(address(_depositManager)),
            100e6,
            "All external custody shares restored"
        );
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,reentrancy-no-eth)
