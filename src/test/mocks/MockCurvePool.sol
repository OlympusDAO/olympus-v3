// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ICurvePool, ICurvePoolTwoCrypto, ICurvePoolTriCrypto} from "src/modules/PRICE/submodules/feeds/CurvePoolTokenPrice.sol";

contract MockCurvePool is ICurvePool {
    uint256 private _virtualPrice;
    uint256 private _dy;
    address[] private _coins;
    uint256[] private _balances;
    mapping(uint128 => mapping(uint128 => mapping(uint256 => uint256))) private _swaps;

    function setVirtualPrice(uint256 virtualPrice_) public {
        _virtualPrice = virtualPrice_;
    }

    function get_virtual_price() external view override returns (uint256) {
        return _virtualPrice;
    }

    function setCoins(address[] memory coins_) public {
        _coins = coins_;
    }

    function getCoins() external view returns (address[] memory) {
        return _coins;
    }

    function coins(uint256 arg0) external view override returns (address) {
        return _coins[arg0];
    }

    function setBalances(uint256[] memory balances_) public {
        _balances = balances_;
    }

    function balances(uint256 arg0) external view override returns (uint256) {
        return _balances[arg0];
    }

    function setCoinsTwo(address coin1_, address coin2_) public {
        address[] memory tempCoins = new address[](2);
        tempCoins[0] = coin1_;
        tempCoins[1] = coin2_;
        setCoins(tempCoins);
    }

    function setCoinsThree(address coin1_, address coin2_, address coin3_) public {
        address[] memory tempCoins = new address[](3);
        tempCoins[0] = coin1_;
        tempCoins[1] = coin2_;
        tempCoins[2] = coin3_;
        setCoins(tempCoins);
    }

    function setBalancesThree(uint256 balance1_, uint256 balance2_, uint256 balance3_) public {
        uint256[] memory tempBalances = new uint256[](3);
        tempBalances[0] = balance1_;
        tempBalances[1] = balance2_;
        tempBalances[2] = balance3_;
        setBalances(tempBalances);
    }

    function setBalancesTwo(uint256 balance1_, uint256 balance2_) public {
        uint256[] memory tempBalances = new uint256[](2);
        tempBalances[0] = balance1_;
        tempBalances[1] = balance2_;
        setBalances(tempBalances);
    }

    function remove_liquidity(uint256 amount_, uint256[] calldata minAmounts_) external override {
        require(
            minAmounts_.length == _coins.length,
            "MockCurvePool: minAmounts_ length does not match coins length"
        );
    }

    function setSwap(
        uint128 fromIndex_,
        uint128 destIndex_,
        uint256 fromQuantity_,
        uint256 destQuantity_
    ) public {
        _swaps[fromIndex_][destIndex_][fromQuantity_] = destQuantity_;
    }

    function get_dy(
        uint128 fromIndex_,
        uint128 destIndex_,
        uint256 fromQuantity_
    ) external view override returns (uint256) {
        return _swaps[fromIndex_][destIndex_][fromQuantity_];
    }
}

contract MockCurvePoolTwoCrypto is MockCurvePool, ICurvePoolTwoCrypto {
    uint256 private _price_oracle;
    address private _lp_token;

    function set_price_oracle(uint256 price_oracle_) public {
        _price_oracle = price_oracle_;
    }

    function price_oracle() external view override returns (uint256) {
        return _price_oracle;
    }

    function setToken(address _address) public {
        _lp_token = _address;
    }

    function token() external view override returns (address) {
        return _lp_token;
    }
}

contract MockCurvePoolTriCrypto is MockCurvePool, ICurvePoolTriCrypto {
    uint256[] private _price_oracle;
    address private _lp_token;

    function set_price_oracle(uint256[] memory price_oracle_) public {
        _price_oracle = price_oracle_;
    }

    function price_oracle(uint256 k) external view override returns (uint256) {
        return _price_oracle[k];
    }

    function setToken(address _address) public {
        _lp_token = _address;
    }

    function token() external view override returns (address) {
        return _lp_token;
    }
}
