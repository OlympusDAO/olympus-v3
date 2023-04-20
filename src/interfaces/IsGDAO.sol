// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.7.5;

import "src/interfaces/IERC20.sol";


interface IsGDAO is IERC20 {
    function rebase( uint256 gdaoProfit_, uint epoch_) external returns (uint256);

    function circulatingSupply() external view returns (uint256);

    function gonsForBalance( uint amount ) external view returns ( uint );

    function balanceForGons( uint gons ) external view returns ( uint );

    function index() external view returns ( uint );

    function toG(uint amount) external view returns (uint);

    function fromG(uint amount) external view returns (uint);

     function changeDebt(
        uint256 amount,
        address debtor,
        bool add
    ) external;

    function debtBalances(address _address) external view returns (uint256);

}