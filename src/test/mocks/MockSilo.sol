// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ISiloLens} from "interfaces/Silo/ISiloLens.sol";
import {IBaseSilo} from "interfaces/Silo/IBaseSilo.sol";

contract MockSiloLens is ISiloLens {
    uint256 internal _totalBorrowAmountWithInterest;
    uint256 internal _totalDepositsWithInterest;
    uint256 internal _balanceOfUnderlying;

    function totalBorrowAmountWithInterest(
        IBaseSilo silo_,
        address asset_
    ) external view override returns (uint256 totalBorrowAmount_) {
        return _totalBorrowAmountWithInterest;
    }

    function setTotalBorrowAmountWithInterest(uint256 totalBorrowAmountWithInterest_) external {
        _totalBorrowAmountWithInterest = totalBorrowAmountWithInterest_;
    }

    function totalDepositsWithInterest(
        IBaseSilo silo_,
        address asset_
    ) external view override returns (uint256 totalDeposits_) {
        return _totalDepositsWithInterest;
    }

    function setTotalDepositsWithInterest(uint256 totalDepositsWithInterest_) external {
        _totalDepositsWithInterest = totalDepositsWithInterest_;
    }

    function balanceOfUnderlying(
        uint256 assetTotalDeposits_,
        address shareToken_,
        address user_
    ) external view override returns (uint256 balance_) {
        return _balanceOfUnderlying;
    }

    function setBalanceOfUnderlying(uint256 balanceOfUnderlying_) external {
        _balanceOfUnderlying = balanceOfUnderlying_;
    }
}

contract MockBaseSilo is IBaseSilo {
    AssetStorage _storage;

    // Constructor
    constructor() {
        _storage = AssetStorage({
            collateralToken: address(0),
            collateralOnlyToken: address(0),
            debtToken: address(0),
            totalDeposits: 0,
            collateralOnlyDeposits: 0,
            totalBorrowAmount: 0
        });
    }

    function setCollateralToken(address collateralToken_) external {
        _storage.collateralToken = collateralToken_;
    }

    function assetStorage(address _asset) external view override returns (AssetStorage memory) {
        return _storage;
    }
}