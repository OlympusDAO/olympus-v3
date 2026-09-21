// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";

// Contracts
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626DifferentDecimals} from "src/test/mocks/MockERC4626DifferentDecimals.sol";
import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";

contract DepositManagerWithdrawV1_1DecimalsTest is DepositManagerTest {
    function test_givenSixDecimalAssetAndEighteenDecimalShares_convertsWithoutRescaling() public {
        _assertDifferentDecimalsConversion(6, 18, 5e6, 5e18);
    }

    function test_givenEighteenDecimalAssetAndSixDecimalShares_convertsWithoutRescaling() public {
        _assertDifferentDecimalsConversion(18, 6, 5e18, 5e6);
    }

    function _assertDifferentDecimalsConversion(
        uint8 assetDecimals_,
        uint8 shareDecimals_,
        uint256 requestedAssets_,
        uint256 expectedShares_
    ) internal {
        MockERC20 localAsset = new MockERC20("Asset", "AST", assetDecimals_);
        MockERC4626DifferentDecimals localVault = new MockERC4626DifferentDecimals(
            ERC20(address(localAsset)),
            shareDecimals_
        );
        IERC20 localAssetInterface = IERC20(address(localAsset));

        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "ddv");
        depositManager.addAsset(
            localAssetInterface,
            IERC4626(address(localVault)),
            type(uint256).max,
            0
        );
        depositManager.addAssetPeriod(localAssetInterface, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.stopPrank();

        localAsset.mint(DEPOSITOR, requestedAssets_);
        vm.prank(DEPOSITOR);
        localAsset.approve(address(depositManager), requestedAssets_);
        vm.prank(DEPOSIT_OPERATOR);
        (uint256 receiptTokenId, uint256 creditedAssets) = depositManager.deposit(
            IDepositManager.DepositParams({
                asset: localAssetInterface,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: requestedAssets_,
                shouldWrap: false
            })
        );
        vm.prank(DEPOSITOR);
        receiptTokenManager.approve(address(depositManager), receiptTokenId, requestedAssets_);

        (IERC20 previewToken, uint256 previewAmount) = depositManager.previewWithdraw(
            localAssetInterface,
            requestedAssets_,
            true
        );
        vm.prank(DEPOSIT_OPERATOR);
        (IERC20 tokenOut, uint256 amountOut) = IDepositManagerV1_1(address(depositManager))
            .withdraw(
                IDepositManager.WithdrawParams({
                    asset: localAssetInterface,
                    depositPeriod: DEPOSIT_PERIOD,
                    depositor: DEPOSITOR,
                    recipient: RECIPIENT,
                    amount: requestedAssets_,
                    isWrapped: false
                }),
                true
            );

        // The asset and share values both represent 5 tokens. The vault owns decimal conversion:
        // 5 * 10^assetDecimals -> 5 * 10^shareDecimals, with no DepositManager rescaling.
        assertEq(creditedAssets, requestedAssets_, "credited underlying amount");
        assertEq(address(previewToken), address(localVault), "preview token");
        assertEq(previewAmount, expectedShares_, "preview share amount");
        assertEq(address(tokenOut), address(localVault), "output token");
        assertEq(amountOut, expectedShares_, "output share amount");
        assertEq(localVault.balanceOf(RECIPIENT), expectedShares_, "recipient share balance");
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
