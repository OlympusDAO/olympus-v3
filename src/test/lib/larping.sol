pragma solidity >=0.8.0;

/// DEPS
import {Vm} from "forge-std/Vm.sol";

// larping library
library larping {
    address private constant HEVM_ADDRESS =
        address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));

    Vm private constant vm = Vm(HEVM_ADDRESS);

    // ,address 
    function larp(function () external returns(address) f, address returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1)
        );
    }

    function larpp(function () external payable returns(address) f, address returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1)
        );
    }

    function larpv(function () external view returns(address) f, address returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1)
        );
    }

    // ,bool 
    function larp(function () external returns(bool) f, bool returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1)
        );
    }

    function larpp(function () external payable returns(bool) f, bool returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1)
        );
    }

    function larpv(function () external view returns(bool) f, bool returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1)
        );
    }

    // ,bytes32
    function larp(function () external returns(bytes32) f, bytes32 returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1)
        );
    }

    function larpp(function () external payable returns(bytes32) f, bytes32 returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1)
        );
    }

    function larpv(function () external view returns(bytes32) f, bytes32 returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1)
        );
    }

    // ,string
    function larp(function () external returns(string memory) f, string memory returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1)
        );
    }

    function larpp(function () external payable returns(string memory) f, string memory returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1)
        );
    }

    function larpv(function () external view returns(string memory) f, string memory returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1)
        );
    }

    // ,uint256
    function larp(function () external returns(uint256) f, uint256 returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1)
        );
    }

    function larpp(function () external payable returns(uint256) f, uint256 returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1)
        );
    }

    function larpv(function () external view returns(uint256) f, uint256 returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1)
        );
    }

     // ,uint8
    function larp(function () external returns(uint8) f, uint8 returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1)
        );
    }

    function larpp(function () external payable returns(uint8) f, uint8 returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1)
        );
    }

    function larpv(function () external view returns(uint8) f, uint8 returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector),
            abi.encode(returned1)
        );
    } 

    // address,bool
    function larp(function (address) external returns(bool) f, address addr1, bool returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, addr1),
            abi.encode(returned1)
        );
    }

    function larpp(function (address) external payable returns(bool) f, address addr1, bool returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, addr1),
            abi.encode(returned1)
        );
    }

    function larpv(function (address) external view returns(bool) f, address addr1, bool returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, addr1),
            abi.encode(returned1)
        );
    }

    // address,uint256
    function larp(function (address) external returns(uint256) f, address addr1, uint256 returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, addr1),
            abi.encode(returned1)
        );
    }

    function larpp(function (address) external payable returns(uint256) f, address addr1, uint256 returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, addr1),
            abi.encode(returned1)
        );
    }

    function larpv(function (address) external view returns(uint256) f, address addr1, uint256 returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, addr1),
            abi.encode(returned1)
        );
    }

    // address,address,uint256
    function larp(function (address,address) external returns(uint256) f, address addr1, address addr2, uint256 returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, addr1, addr2),
            abi.encode(returned1)
        );
    }

    function larpp(function (address,address) external payable returns(uint256) f, address addr1, address addr2, uint256 returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, addr1, addr2),
            abi.encode(returned1)
        );
    }

    function larpv(function (address,address) external view returns(uint256) f, address addr1, address addr2, uint256 returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, addr1, addr2),
            abi.encode(returned1)
        );
    }

    // address,uint256,bool
    function larp(function (address,uint256) external returns(bool) f, address addr1, uint256 num1, bool returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, addr1, num1),
            abi.encode(returned1)
        );
    }

    function larpp(function (address,uint256) external payable returns(bool) f, address addr1, uint256 num1, bool returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, addr1, num1),
            abi.encode(returned1)
        );
    }

    function larpv(function (address,uint256) external view returns(bool) f, address addr1, uint256 num1, bool returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, addr1, num1),
            abi.encode(returned1)
        );
    }

    // bytes3,address,bool
    function larp(function (bytes3,address) external returns(bool) f, bytes3 byt31, address num1, bool returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, byt31, num1),
            abi.encode(returned1)
        );
    }

    function larpp(function (bytes3,address) external payable returns(bool) f, bytes3 byt31, address num1, bool returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, byt31, num1),
            abi.encode(returned1)
        );
    }

    function larpv(function (bytes3,address) external view returns(bool) f, bytes3 byt31, address num1, bool returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, byt31, num1),
            abi.encode(returned1)
        );
    }

    // address,address,uint256,bool
    function larp(function (address,address,uint256) external returns(bool) f, address addr1, address addr2, uint256 num1, bool returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, addr1, addr2, num1),
            abi.encode(returned1)
        );
    }

    function larpp(function (address,address,uint256) external payable returns(bool) f, address addr1, address addr2, uint256 num1, bool returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, addr1, addr2, num1),
            abi.encode(returned1)
        );
    }

    function larpv(function (address,address,uint256) external view returns(bool) f, address addr1, address addr2, uint256 num1, bool returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, addr1, addr2, num1),
            abi.encode(returned1)
        );
    }
    
    // address,uint256,uint256,bool
    function larp(function (address,uint256,uint256) external returns(bool) f, address addr1, uint256 num1, uint256 num2, bool returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, addr1, num1, num2),
            abi.encode(returned1)
        );
    }

    function larpp(function (address,uint256,uint256) external payable returns(bool) f, address addr1, uint256 num1, uint256 num2, bool returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, addr1, num1, num2),
            abi.encode(returned1)
        );
    }

    function larpv(function (address,uint256,uint256) external view returns(bool) f, address addr1, uint256 num1, uint256 num2, bool returned1) internal {
        vm.mockCall(
            f.address,
            abi.encodeWithSelector(f.selector, addr1, num1, num2),
            abi.encode(returned1)
        );
    }
}