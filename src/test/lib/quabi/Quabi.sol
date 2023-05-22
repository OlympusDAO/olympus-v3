// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";

library Quabi {
    Vm internal constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    function jq_bytes(string memory query, string memory path)
        internal
        returns (bytes[] memory response)
    {
        string[] memory inputs = new string[](3);
        inputs[0] = "sh";
        inputs[1] = "-c";
        inputs[2] = string(bytes.concat("./src/test/lib/quabi/jq_bytes.sh ", bytes(query), " ", bytes(path), ""));
        bytes memory res = vm.ffi(inputs);

        response = abi.decode(res, (bytes[]));
    }

    function jq_strings(string memory query, string memory path)
        internal
        returns (string[] memory response)
    {
        string[] memory inputs = new string[](3);
        inputs[0] = "sh";
        inputs[1] = "-c";
        inputs[2] = string(bytes.concat("./src/test/lib/quabi/jq_strings.sh ", bytes(query), " ", bytes(path), ""));
        bytes memory res = vm.ffi(inputs);

        response = abi.decode(res, (string[]));
    }

    function getPath(string memory contractName) internal returns (string memory path) {
        string[] memory inputs = new string[](3);
        inputs[0] = "sh";
        inputs[1] = "-c";
        inputs[2] = string(bytes.concat("./src/test/lib/quabi/path.sh ", bytes(contractName), ".json", ""));
        bytes memory res = vm.ffi(inputs);

        path = abi.decode(res, (string));
    }

    function getSelectors(string memory contractName, string memory modifierName) internal returns (bytes4[] memory) {
        // Get target contract path
        string memory path = getPath(contractName);
        
        // Get the linearized list of base contract ast ids for the target contract
        string memory query = string(bytes.concat("'((.ast.nodes[] | if .nodeType == \"ContractDefinition\" and .name == \"",bytes(contractName),"\" then .linearizedBaseContracts else empty end) | sort) as $ids | [.ast.exportedSymbols | to_entries | .[] | if (.value[0] as $value | $ids | bsearch($value)) > -1 then .key else empty end]'"));
        string[] memory names = jq_strings(query, path);

        // Iterate through contracts and get selectors
        uint256 numArrays = names.length;
        bytes[] memory selectorArrays = new bytes[](numArrays);
        uint256 count;
        bytes[] memory response;
        bool useModifier = keccak256(abi.encodePacked(modifierName)) != keccak256(abi.encodePacked(""));
        for (uint256 i; i < numArrays;) {
            query = useModifier ? 
                string(bytes.concat("'[.ast.nodes[] | if .name == \"",bytes(names[i]),"\" then .nodes[] else empty end | if .nodeType == \"FunctionDefinition\" and .kind == \"function\" and ([.modifiers[] | .modifierName.name == \"", bytes(modifierName), "\" ] | any ) then .functionSelector else empty end ]'")) :
                string(bytes.concat("'[.ast.nodes[] | if .name == \"",bytes(names[i]),"\" then .nodes[] else empty end | if .nodeType == \"FunctionDefinition\" and .kind == \"function\" then .functionSelector else empty end ]'"));
            response = jq_bytes(query, getPath(names[i]));
            count += response.length;
            selectorArrays[i] = abi.encode(response);
            unchecked {
                ++i;
            }
        }

        // Concatenate selector arrays
        uint256 len;
        bytes4[] memory selectors = new bytes4[](count);
        count = 0;
        for (uint256 i; i < numArrays;) {
            bytes[] memory array = abi.decode(selectorArrays[i], (bytes[]));
            len = array.length;
            for (uint256 j; j < len; ) {
                selectors[count] = bytes4(array[j]);
                unchecked {
                    ++j;
                    ++count;
                }
            }
            unchecked {
                ++i;
            }
        }

        return selectors;
    }

    function getFunctions(string memory contractName) public returns (bytes4[] memory) {
        return getSelectors(contractName, "");
    }

    function getFunctionsWithModifier(string memory contractName, string memory modifierName) public returns (bytes4[] memory) {
        return getSelectors(contractName, modifierName);
    }

    /// TODO get events, errors, state variables, etc.


}