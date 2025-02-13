// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IDLGTEv1} from "modules/DLGTE/IDLGTE.v1.sol";
import {IMonoCooler} from "../interfaces/cooler/IMonoCooler.sol";

contract CoolerComposites {
    IMonoCooler public immutable COOLER;
    ERC20 public immutable GOHM;
    ERC20 public immutable USDS;

    constructor(IMonoCooler _cooler, ERC20 _gohm, ERC20 _usds) {
        COOLER = _cooler;

        GOHM = _gohm;
        _gohm.approve(address(_cooler), type(uint256).max);

        USDS = _usds;
        _usds.approve(address(_cooler), type(uint256).max);
    }

    /// @notice allow user to add collateral and borrow from Cooler V2
    /// @dev    user must provide authorization signature before using function
    /// @param authorization        authorization info
    /// @param signature            offchain auth signature
    /// @param collateralAmount     amount of gOHM collateral to deposit
    /// @param borrowAmount         amount of USDS to borrow
    /// @param delegationRequests   resulting collateral delegation
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

        GOHM.transferFrom(msg.sender, address(this), collateralAmount);
        COOLER.addCollateral(collateralAmount, msg.sender, delegationRequests);
        COOLER.borrow(borrowAmount, msg.sender, msg.sender);
    }

    /// @notice allow user to add collateral and borrow from Cooler V2
    /// @dev    user must provide authorization signature before using function
    /// @param authorization        authorization info
    /// @param signature            offchain auth signature
    /// @param repayAmount          amount of USDS to repay
    /// @param collateralAmount     amount of gOHM collateral to withdraw
    /// @param delegationRequests   resulting collateral delegation
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

        USDS.transferFrom(msg.sender, address(this), repayAmount);
        COOLER.repay(repayAmount, msg.sender);
        COOLER.withdrawCollateral(collateralAmount, msg.sender, msg.sender, delegationRequests);
    }
}
