// SPDX-FileCopyrightText: 2021 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface IWsteth {
    function stEthPerToken() external view returns (uint256);
}
