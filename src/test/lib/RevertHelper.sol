// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// DEPS
import {Vm} from "forge-std/Vm.sol";

// errors library
// <err>.selector.willRevert
// larping.sol method does not work due to
// https://github.com/ethereum/solidity/issues/12991
library RevertHelper {
    address private constant HEVM_ADDRESS =
        address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));

    Vm private constant vm = Vm(HEVM_ADDRESS);

    // no arg
    function willRevert(bytes4 errorSel) internal {
        vm.expectRevert(abi.encodeWithSelector(errorSel));
    }

    function willRevert(bytes4 errorSel, address arg1) internal {
        vm.expectRevert(abi.encodeWithSelector(errorSel, arg1));
    }

    function willRevert(bytes4 errorSel, bool arg1) internal {
        vm.expectRevert(abi.encodeWithSelector(errorSel, arg1));
    }

    function willRevert(bytes4 errorSel, bytes32 arg1) internal {
        vm.expectRevert(abi.encodeWithSelector(errorSel, arg1));
    }

    function willRevert(bytes4 errorSel, string memory arg1) internal {
        vm.expectRevert(abi.encodeWithSelector(errorSel, arg1));
    }

    function willRevert(bytes4 errorSel, uint256 arg1) internal {
        vm.expectRevert(abi.encodeWithSelector(errorSel, arg1));
    }

    function willRevert(
        bytes4 errorSel,
        address arg1,
        address arg2
    ) internal {
        vm.expectRevert(abi.encodeWithSelector(errorSel, arg1, arg2));
    }

    function willRevert(
        bytes4 errorSel,
        bool arg1,
        bool arg2
    ) internal {
        vm.expectRevert(abi.encodeWithSelector(errorSel, arg1, arg2));
    }

    function willRevert(
        bytes4 errorSel,
        bytes32 arg1,
        bytes32 arg2
    ) internal {
        vm.expectRevert(abi.encodeWithSelector(errorSel, arg1, arg2));
    }

    function willRevert(
        bytes4 errorSel,
        string memory arg1,
        string memory arg2
    ) internal {
        vm.expectRevert(abi.encodeWithSelector(errorSel, arg1, arg2));
    }

    function willRevert(
        bytes4 errorSel,
        uint256 arg1,
        uint256 arg2
    ) internal {
        vm.expectRevert(abi.encodeWithSelector(errorSel, arg1, arg2));
    }

    function willRevert(
        bytes4 errorSel,
        address arg1,
        address arg2,
        address arg3
    ) internal {
        vm.expectRevert(abi.encodeWithSelector(errorSel, arg1, arg2, arg3));
    }

    function willRevert(
        bytes4 errorSel,
        bool arg1,
        bool arg2,
        bool arg3
    ) internal {
        vm.expectRevert(abi.encodeWithSelector(errorSel, arg1, arg2, arg3));
    }

    function willRevert(
        bytes4 errorSel,
        bytes32 arg1,
        bytes32 arg2,
        bytes32 arg3
    ) internal {
        vm.expectRevert(abi.encodeWithSelector(errorSel, arg1, arg2, arg3));
    }

    function willRevert(
        bytes4 errorSel,
        string memory arg1,
        string memory arg2,
        string memory arg3
    ) internal {
        vm.expectRevert(abi.encodeWithSelector(errorSel, arg1, arg2, arg3));
    }

    function willRevert(
        bytes4 errorSel,
        uint256 arg1,
        uint256 arg2,
        uint256 arg3
    ) internal {
        vm.expectRevert(abi.encodeWithSelector(errorSel, arg1, arg2, arg3));
    }
}
