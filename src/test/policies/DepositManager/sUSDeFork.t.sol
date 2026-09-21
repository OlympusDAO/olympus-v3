// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

// Interfaces
import {Actions} from "src/Kernel.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IStakedUSDeV2} from "src/test/policies/DepositManager/interfaces/IStakedUSDeV2.sol";

// Test contracts
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";

contract DepositManagerSUSDeForkTest is DepositManagerTest {
    uint256 internal constant _FORK_BLOCK = 25_973_712;
    address internal constant _USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address internal constant _SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    uint256 internal constant _DEPOSIT_AMOUNT = 100e18;
    uint256 internal constant _ACTION_AMOUNT = 10e18;
    uint256 internal constant _YIELD_CLAIM_AMOUNT = 1e18;

    function setUp() public override {
        // The fork ID is not needed after selecting the only fork used by this test contract.
        // forge-lint: disable-next-line(unused-return)
        vm.createSelectFork("mainnet", _FORK_BLOCK);
        super.setUp();

        iAsset = IERC20(_USDE);
        iVault = IERC4626(_SUSDE);

        assertEq(iVault.asset(), address(iAsset), "sUSDe asset mismatch");
        assertGt(IStakedUSDeV2(_SUSDE).cooldownDuration(), 0, "sUSDe cooldown disabled");

        deal(address(iAsset), DEPOSITOR, _DEPOSIT_AMOUNT);

        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "cd1");
        IDepositManagerV1_1(address(depositManager)).addAsset(
            iAsset,
            iVault,
            type(uint256).max,
            0,
            true
        );
        // The deposit below validates this configuration through its returned receipt token ID.
        // forge-lint: disable-next-line(unused-return)
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.stopPrank();

        vm.prank(DEPOSITOR);
        assertTrue(
            iAsset.approve(address(depositManager), _DEPOSIT_AMOUNT),
            "USDe approval failed"
        );
    }

    // withdraw
    // given sUSDe cooldown is enabled but its non-standard restriction is not configured
    //  when underlying output is previewed and requested
    //   then preview remains an estimate and the vault's synchronous-redemption error bubbles up
    function test_givenSUSDeCooldownEnabled_givenShareWithdrawalNotRequired_whenUnderlyingOutputRequested_previewSucceedsAndWithdrawReverts()
        public
    {
        DepositManager unmarkedManager = new DepositManager(
            address(kernel),
            address(receiptTokenManager)
        );
        vm.startPrank(ADMIN);
        kernel.executeAction(Actions.ActivatePolicy, address(unmarkedManager));
        unmarkedManager.enable("");
        unmarkedManager.setOperatorName(DEPOSIT_OPERATOR, "cd1");
        IDepositManagerV1_1(address(unmarkedManager)).addAsset(
            iAsset,
            iVault,
            type(uint256).max,
            0,
            false
        );
        uint256 configuredReceiptTokenId = unmarkedManager.addAssetPeriod(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
        vm.stopPrank();

        vm.prank(DEPOSITOR);
        assertTrue(
            iAsset.approve(address(unmarkedManager), _DEPOSIT_AMOUNT),
            "unmarked manager approval failed"
        );
        vm.prank(DEPOSIT_OPERATOR);
        (uint256 receiptTokenId, uint256 creditedAssets) = unmarkedManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: _DEPOSIT_AMOUNT,
                shouldWrap: false
            })
        );
        assertEq(receiptTokenId, configuredReceiptTokenId, "unmarked receipt token ID");
        vm.prank(DEPOSITOR);
        assertTrue(
            receiptTokenManager.approve(address(unmarkedManager), receiptTokenId, creditedAssets),
            "unmarked receipt approval failed"
        );

        (IERC20 previewToken, uint256 previewAmount) = IDepositManagerV1_1(address(unmarkedManager))
            .previewWithdraw(iAsset, creditedAssets, false);
        assertEq(address(previewToken), _USDE, "unmarked preview output token");
        assertGt(previewAmount, 0, "unmarked preview output amount");

        vm.expectRevert(IStakedUSDeV2.OperationNotAllowed.selector);
        vm.prank(DEPOSIT_OPERATOR);
        // The call is expected to revert, so there are no return values to assert.
        // forge-lint: disable-start(unused-return)
        IDepositManagerV1_1(address(unmarkedManager)).withdraw(
            IDepositManager.WithdrawParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                recipient: RECIPIENT,
                amount: creditedAssets,
                isWrapped: false
            }),
            false
        );
        // forge-lint: disable-end(unused-return)

        assertEq(
            receiptTokenManager.balanceOf(DEPOSITOR, receiptTokenId),
            creditedAssets,
            "unmarked receipt burn should roll back"
        );
        assertEq(
            unmarkedManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            creditedAssets,
            "unmarked liability debit should roll back"
        );
    }

    // withdraw
    // given sUSDe cooldown is enabled and collateral has been deposited
    //  when underlying output is requested
    //   then the disabled synchronous redemption reverts without changing accounting
    function test_givenSUSDeCooldownEnabled_whenUnderlyingOutputRequested_reverts() public {
        (uint256 receiptTokenId, uint256 creditedAssets) = _depositSUSDe();
        _approveReceiptToken(receiptTokenId, creditedAssets);
        IDepositManager.WithdrawParams memory params = _withdrawParams(creditedAssets);

        uint256 receiptBalanceBefore = receiptTokenManager.balanceOf(DEPOSITOR, receiptTokenId);
        uint256 liabilitiesBefore = depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR);
        uint256 custodySharesBefore = iVault.balanceOf(address(depositManager));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(iAsset),
                address(iVault)
            )
        );
        // The exact revert is asserted above, so the return values are unreachable.
        // forge-lint: disable-next-line(unused-return)
        IDepositManagerV1_1(address(depositManager)).previewWithdraw(iAsset, creditedAssets, false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(iAsset),
                address(iVault)
            )
        );
        vm.prank(DEPOSIT_OPERATOR);
        // The expected revert prevents this call from producing a return value.
        // forge-lint: disable-next-line(unused-return)
        depositManager.withdraw(params);

        assertEq(
            receiptTokenManager.balanceOf(DEPOSITOR, receiptTokenId),
            receiptBalanceBefore,
            "receipt burn did not roll back"
        );
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            liabilitiesBefore,
            "liability debit did not roll back"
        );
        assertEq(
            iVault.balanceOf(address(depositManager)),
            custodySharesBefore,
            "custody shares changed"
        );
    }

    // withdraw
    // given sUSDe cooldown is enabled and collateral has been deposited
    //  when share output is requested
    //   then the equivalent sUSDe shares are transferred without synchronous redemption
    function test_givenSUSDeCooldownEnabled_whenShareOutputRequested_transfersSUSDe() public {
        (uint256 receiptTokenId, uint256 creditedAssets) = _depositSUSDe();
        _approveReceiptToken(receiptTokenId, creditedAssets);
        IDepositManager.WithdrawParams memory params = _withdrawParams(creditedAssets);
        uint256 expectedShares = iVault.convertToShares(creditedAssets);

        (IERC20 previewToken, uint256 previewAmount) = IDepositManagerV1_1(address(depositManager))
            .previewWithdraw(iAsset, creditedAssets, true);
        assertEq(address(previewToken), address(iVault), "preview output token mismatch");
        assertEq(previewAmount, expectedShares, "preview share amount mismatch");

        uint256 custodySharesBefore = iVault.balanceOf(address(depositManager));
        vm.prank(DEPOSIT_OPERATOR);
        (IERC20 tokenOut, uint256 sharesOut) = IDepositManagerV1_1(address(depositManager))
            .withdraw(params, true);

        assertEq(address(tokenOut), _SUSDE, "withdrawal output token mismatch");
        assertEq(sharesOut, expectedShares, "withdrawal share amount mismatch");
        assertEq(iVault.balanceOf(RECIPIENT), expectedShares, "recipient sUSDe balance mismatch");
        assertEq(
            iVault.balanceOf(address(depositManager)),
            custodySharesBefore - expectedShares,
            "DepositManager sUSDe balance mismatch"
        );
        assertEq(iAsset.balanceOf(RECIPIENT), 0, "recipient unexpectedly received USDe");
    }

    function test_givenSUSDeCooldownEnabled_shareWithdrawalIsExplicitlyRequired() public view {
        assertTrue(
            depositManager.isAssetShareWithdrawalRequired(iAsset),
            "sUSDe should require share withdrawals"
        );
    }

    function test_givenSUSDeCooldownEnabled_whenClaimingYield_transfersSUSDe() public {
        _depositSUSDe();
        _fundAndApproveUnderlying(DEPOSITOR, _ACTION_AMOUNT);
        vm.prank(DEPOSIT_OPERATOR);
        uint256 creditedYield = depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: DEPOSITOR,
                amount: _ACTION_AMOUNT,
                maxAmount: 0
            })
        );
        assertGt(creditedYield, _YIELD_CLAIM_AMOUNT, "yield deposit should cover claim");

        uint256 expectedShares = iVault.convertToShares(_YIELD_CLAIM_AMOUNT);
        vm.prank(DEPOSIT_OPERATOR);
        (IERC20 tokenOut, uint256 amountOut) = IDepositManagerV1_1(address(depositManager))
            .claimYield(iAsset, RECIPIENT, _YIELD_CLAIM_AMOUNT, true);

        assertEq(address(tokenOut), _SUSDE, "yield output token");
        assertEq(amountOut, expectedShares, "yield shares out");
        assertEq(iVault.balanceOf(RECIPIENT), expectedShares, "recipient yield shares");
    }

    function test_givenSUSDeCooldownEnabled_whenBorrowing_transfersSUSDe() public {
        _depositSUSDe();
        uint256 borrowAmount = _ACTION_AMOUNT;
        uint256 expectedShares = iVault.convertToShares(borrowAmount);

        vm.prank(DEPOSIT_OPERATOR);
        (IERC20 tokenOut, uint256 amountOut) = IDepositManagerV1_1(address(depositManager))
            .borrowingWithdraw(
                IDepositManager.BorrowingWithdrawParams({
                    asset: iAsset,
                    recipient: RECIPIENT,
                    amount: borrowAmount
                }),
                true
            );

        assertEq(address(tokenOut), _SUSDE, "borrow output token");
        assertEq(amountOut, expectedShares, "borrow shares out");
        assertEq(iVault.balanceOf(RECIPIENT), expectedShares, "recipient borrowed shares");
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            borrowAmount,
            "borrowed accounting"
        );
    }

    function test_givenSUSDeBorrow_whenRepaying_depositsSynchronously() public {
        _depositSUSDe();
        uint256 borrowAmount = _ACTION_AMOUNT;
        _borrowSUSDeShares(borrowAmount);
        _fundAndApproveUnderlying(DEPOSITOR, borrowAmount);

        vm.prank(DEPOSIT_OPERATOR);
        uint256 creditedAssets = depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: DEPOSITOR,
                amount: borrowAmount,
                maxAmount: borrowAmount
            })
        );

        assertGt(creditedAssets, 0, "repayment credit");
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            borrowAmount - (creditedAssets > borrowAmount ? borrowAmount : creditedAssets),
            "remaining borrowed amount"
        );
    }

    function test_givenSUSDeBorrow_whenDefaulting_burnsReceiptsWithoutRedeeming() public {
        (uint256 receiptTokenId, uint256 creditedAssets) = _depositSUSDe();
        uint256 defaultAmount = _ACTION_AMOUNT;
        _borrowSUSDeShares(defaultAmount);
        _approveReceiptToken(receiptTokenId, defaultAmount);
        uint256 custodySharesBefore = iVault.balanceOf(address(depositManager));

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingDefault(
            IDepositManager.BorrowingDefaultParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                payer: DEPOSITOR,
                amount: defaultAmount
            })
        );

        assertEq(depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR), 0, "defaulted borrow");
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            creditedAssets - defaultAmount,
            "defaulted liability"
        );
        assertEq(
            iVault.balanceOf(address(depositManager)),
            custodySharesBefore,
            "default should not redeem shares"
        );
    }

    function test_givenSUSDeCustody_whenRescuingManagedTokens_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IDepositManager.DepositManager_CannotRescueAsset.selector, _USDE)
        );
        vm.prank(ADMIN);
        depositManager.rescue(_USDE);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_CannotRescueAsset.selector,
                _SUSDE
            )
        );
        vm.prank(ADMIN);
        depositManager.rescue(_SUSDE);
    }

    function _depositSUSDe() internal returns (uint256 receiptTokenId_, uint256 creditedAssets_) {
        vm.prank(DEPOSIT_OPERATOR);
        return
            depositManager.deposit(
                IDepositManager.DepositParams({
                    asset: iAsset,
                    depositPeriod: DEPOSIT_PERIOD,
                    depositor: DEPOSITOR,
                    amount: _DEPOSIT_AMOUNT,
                    shouldWrap: false
                })
            );
    }

    function _approveReceiptToken(uint256 receiptTokenId_, uint256 amount_) internal {
        vm.prank(DEPOSITOR);
        assertTrue(
            receiptTokenManager.approve(address(depositManager), receiptTokenId_, amount_),
            "receipt approval failed"
        );
    }

    function _borrowSUSDeShares(uint256 amount_) internal {
        vm.prank(DEPOSIT_OPERATOR);
        // The caller only needs the state transition; dedicated tests assert returned output.
        // forge-lint: disable-start(unused-return)
        IDepositManagerV1_1(address(depositManager)).borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: amount_
            }),
            true
        );
        // forge-lint: disable-end(unused-return)
    }

    function _fundAndApproveUnderlying(address payer_, uint256 amount_) internal {
        deal(address(iAsset), payer_, amount_);
        vm.prank(payer_);
        assertTrue(iAsset.approve(address(depositManager), amount_), "USDe approval failed");
    }

    function _withdrawParams(
        uint256 amount_
    ) internal view returns (IDepositManager.WithdrawParams memory) {
        return
            IDepositManager.WithdrawParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                recipient: RECIPIENT,
                amount: amount_,
                isWrapped: false
            });
    }
}
