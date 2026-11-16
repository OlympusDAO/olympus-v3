// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20 as OZERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Contracts
import {ERC4626} from "@openzeppelin-5.7.0/token/ERC20/extensions/ERC4626.sol";
import {BurnerLoansCollateralVaultTest} from "./BurnerLoansCollateralVaultTest.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";

abstract contract BurnerLoansCollateralInsolvencyTest is BurnerLoansCollateralVaultTest {
    function _seedLossVault(uint256 loss_) internal returns (MockERC20 token, MockERC4626 vault) {
        token = new MockERC20("Loss Asset", "LOSS", 0);
        vault = new MockERC4626(OZERC20(address(token)), "Loss Vault", "LV");
        _admitVault(token, address(vault), false);
        _depositAsset(token, 100, _borrower);
        token.burn(address(vault), loss_);
    }

    function _fundLossDeposit(MockERC20 token_, address payer_, uint128 amount_) internal {
        token_.mint(payer_, amount_);
        vm.prank(payer_);
        token_.approve(address(_core), amount_);
    }

    function _lossAccountingDigest(address asset_) internal view returns (bytes32) {
        uint32 market = _core.marketId(asset_);
        bytes32 indexes = keccak256(
            abi.encode(
                _floan.getPositionCount(),
                _floan.getPositionIdsForBorrower(_borrower),
                _floan.getPositionIdsForBorrower(_OTHER_BORROWER),
                _floan.getPositionIdsForMarket(market),
                _floan.getActiveBorrowers(market),
                _floan.getMarket(market),
                _floan.getMarketCollateral(market),
                _floan.getMarketPrincipalDue(market)
            )
        );
        bytes32 grant = keccak256(
            abi.encode(
                _auth.getGrant(_borrower, _recipient),
                _auth.accountEpochs(_borrower),
                _auth.pairEpochs(_borrower, _recipient),
                _auth.authorizationContext(_borrower, _recipient)
            )
        );
        return
            keccak256(
                abi.encode(
                    _accountingDigest(asset_),
                    indexes,
                    grant,
                    _depositManager.getAssetDepositCapStatus(IERC20(asset_)),
                    IERC20(asset_).allowance(_OTHER_BORROWER, address(_core))
                )
            );
    }

    function _lossVaultDigest(MockERC20 token_, ERC4626 vault_) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _lossAccountingDigest(address(token_)),
                    token_.totalSupply(),
                    token_.balanceOf(address(vault_)),
                    token_.allowance(address(_depositManager), address(vault_)),
                    vault_.totalSupply(),
                    vault_.balanceOf(address(_depositManager)),
                    vault_.balanceOf(address(_core)),
                    vault_.allowance(address(_depositManager), address(_core))
                )
            );
    }

    function _expectLossDeposit(
        MockERC20 token_,
        ERC4626 vault_,
        address payer_,
        address borrower_,
        uint128 amount_,
        uint256 liabilities_,
        uint256 assets_
    ) internal {
        bytes32 beforeState = _lossVaultDigest(token_, vault_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_Insolvent.selector,
                address(token_),
                liabilities_,
                assets_,
                uint256(0)
            )
        );
        vm.prank(payer_);
        _collateral.depositCollateral(address(token_), amount_, borrower_);
        assertEq(
            _lossVaultDigest(token_, vault_),
            beforeState,
            "Final solvency rejection restores payer, custody, receipts, grants and FLOAN indexes"
        );
    }
}
