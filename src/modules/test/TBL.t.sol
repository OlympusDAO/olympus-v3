// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

/// DEPS
import "forge-std/Test.sol";
import "solmate/tokens/ERC20.sol";

//// LOCAL
// libs
import "test-utils/coins.sol";

// types
import "src/modules/TBL.sol";

contract TransferBalanceLockTest is Test {
    TransferBalanceLock public tbl;
    ERC20 public dummy; // dummy == ohm, but offers abi by using dummy.selector.<fn>

    bool public pswitch;

    function approvedPolicies(address) public view returns (bool) {
        return pswitch;
    }

    function setUp() public {
        tbl = new TransferBalanceLock(address(this));
        dummy = ERC20(coins.ohm);
    }

    function testKEYCODE() public {
        assertEq32("TBL", tbl.KEYCODE());
    }

    function testPullTokens(uint256 amount) public {}
}
