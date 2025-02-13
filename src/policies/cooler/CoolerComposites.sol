// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IDLGTEv1} from "modules/DLGTE/IDLGTE.v1.sol";
import {IMonoCooler} from "../interfaces/cooler/IMonoCooler.sol";
import {ICoolerComposites} from "../interfaces/cooler/ICoolerComposites.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract CoolerComposites is ICoolerComposites {
    using SafeTransferLib for ERC20;

    IMonoCooler public immutable COOLER;
    ERC20 internal immutable _COLLATERAL_TOKEN;
    ERC20 internal immutable _DEBT_TOKEN;

    constructor(IMonoCooler cooler_) {
        COOLER = cooler_;

        _COLLATERAL_TOKEN = ERC20(address(cooler_.collateralToken()));
        _COLLATERAL_TOKEN.approve(address(cooler_), type(uint256).max);

        _DEBT_TOKEN = ERC20(address(cooler_.debtToken()));
        _DEBT_TOKEN.approve(address(cooler_), type(uint256).max);
    }

    // ===== Composite Functions ===== //

    function _addCollateralAndBorrow(
        uint128 collateralAmount,
        uint128 borrowAmount,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests
    ) internal {
        _COLLATERAL_TOKEN.safeTransferFrom(msg.sender, address(this), collateralAmount);
        COOLER.addCollateral(collateralAmount, msg.sender, delegationRequests);
        COOLER.borrow(borrowAmount, msg.sender, msg.sender);
    }

    /// @inheritdoc ICoolerComposites
    function addCollateralAndBorrow(
        uint128 collateralAmount,
        uint128 borrowAmount,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external {
        _addCollateralAndBorrow(collateralAmount, borrowAmount, delegationRequests);
    }

    /// @inheritdoc ICoolerComposites
    function addCollateralAndBorrow(
        IMonoCooler.Authorization memory authorization,
        IMonoCooler.Signature calldata signature,
        uint128 collateralAmount,
        uint128 borrowAmount,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external {
        if (authorization.account != address(0)) {
            COOLER.setAuthorizationWithSig(authorization, signature);
        }

        _addCollateralAndBorrow(collateralAmount, borrowAmount, delegationRequests);
    }

    function _repayAndRemoveCollateral(
        uint128 repayAmount,
        uint128 collateralAmount,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests
    ) internal {
        _DEBT_TOKEN.safeTransferFrom(msg.sender, address(this), repayAmount);
        COOLER.repay(repayAmount, msg.sender);
        COOLER.withdrawCollateral(collateralAmount, msg.sender, msg.sender, delegationRequests);
    }

    /// @inheritdoc ICoolerComposites
    function repayAndRemoveCollateral(
        uint128 repayAmount,
        uint128 collateralAmount,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external {
        _repayAndRemoveCollateral(repayAmount, collateralAmount, delegationRequests);
    }

    /// @inheritdoc ICoolerComposites
    function repayAndRemoveCollateral(
        IMonoCooler.Authorization memory authorization,
        IMonoCooler.Signature calldata signature,
        uint128 repayAmount,
        uint128 collateralAmount,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external {
        if (authorization.account != address(0)) {
            COOLER.setAuthorizationWithSig(authorization, signature);
        }

        _repayAndRemoveCollateral(repayAmount, collateralAmount, delegationRequests);
    }

    // ===== View Functions ===== //

    /// @inheritdoc ICoolerComposites
    function collateralToken() external view returns (IERC20) {
        return IERC20(address(_COLLATERAL_TOKEN));
    }

    /// @inheritdoc ICoolerComposites
    function debtToken() external view returns (IERC20) {
        return IERC20(address(_DEBT_TOKEN));
    }
}
