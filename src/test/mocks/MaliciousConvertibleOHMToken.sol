// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ERC20} from "@openzeppelin-5.3.0/token/ERC20/ERC20.sol";

/// @notice A mock token that mimics ConvertibleOHMToken interface
///         for testing with invalid/malicious tokens.
contract MaliciousConvertibleOHMToken is ERC20 {
    address internal _quote;
    uint48 internal _eligible;
    uint48 internal _expiry;
    address internal _teller;
    uint256 internal _strikePrice;

    constructor(
        address quote_,
        uint48 eligible_,
        uint48 expiry_,
        address teller_,
        uint256 strikePrice_
    ) ERC20("Malicious Convertible Token", "MCT") {
        _quote = quote_;
        _eligible = eligible_;
        _expiry = expiry_;
        _teller = teller_;
        _strikePrice = strikePrice_;
    }

    function decimals() public pure override returns (uint8) {
        return 9;
    }

    function parameters() external view returns (address, uint48, uint48, uint256) {
        return (_quote, _eligible, _expiry, _strikePrice);
    }

    function quote() external view returns (address) {
        return _quote;
    }

    function eligible() external view returns (uint48) {
        return _eligible;
    }

    function expiry() external view returns (uint48) {
        return _expiry;
    }

    function teller() external view returns (address) {
        return _teller;
    }

    function strike() external view returns (uint256) {
        return _strikePrice;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
