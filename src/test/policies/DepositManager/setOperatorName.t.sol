// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "./DepositManagerTest.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

import {console2} from "@forge-std-1.9.6/console2.sol";

contract DepositManagerSetOperatorNameTest is DepositManagerTest {
    // ========== EVENTS ========== //

    event OperatorNameSet(address indexed operator, string name);

    // ========== TESTS ========== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(ADMIN);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "tst");
    }

    // when the caller is not the admin or manager
    //  [X] it reverts

    function test_givenCallerIsNotManagerOrAdmin_reverts(address caller_) public givenIsEnabled {
        vm.assume(caller_ != ADMIN && caller_ != MANAGER);

        // Expect revert
        _expectRevertNotManagerOrAdmin();

        // Call function
        vm.prank(caller_);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "tst");
    }

    // when the operator name has been set already
    //  [X] it reverts

    function test_givenOperatorNameAlreadySet_reverts() public givenIsEnabled {
        // Set the operator name
        vm.prank(ADMIN);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "tst");

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_OperatorNameSet.selector,
                DEPOSIT_OPERATOR
            )
        );

        // Call function again
        vm.prank(ADMIN);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "tst");
    }

    // when the operator name is empty
    //  [X] it reverts

    function test_givenOperatorNameIsEmpty_reverts() public givenIsEnabled {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IDepositManager.DepositManager_OperatorNameInvalid.selector)
        );

        // Call function
        vm.prank(ADMIN);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "");
    }

    // when the name is already in use
    //  [X] it reverts

    function test_givenOperatorNameAlreadyInUse_reverts() public givenIsEnabled {
        address otherOperator = makeAddr("otherOperator");
        // Set the operator name
        vm.prank(ADMIN);
        depositManager.setOperatorName(otherOperator, "tst");

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IDepositManager.DepositManager_OperatorNameInUse.selector, "tst")
        );

        // Call function with the same name
        vm.prank(ADMIN);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "tst");
    }

    // when the name length is greater than 3
    //  [X] it reverts

    function test_givenOperatorNameLengthGreaterThanThree_reverts() public givenIsEnabled {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IDepositManager.DepositManager_OperatorNameInvalid.selector)
        );

        // Call function with a name longer than 3 characters
        vm.prank(ADMIN);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "test");
    }

    // when the name contains characters other than lowercase letters or numbers
    //  [X] it reverts

    function test_givenOperatorNameContainsInvalidCharacters_reverts(
        uint8 index_,
        bytes1 character_
    ) public givenIsEnabled {
        index_ = uint8(bound(index_, 0, 2));

        // Ensure character is not a lowercase letter
        if (
            (character_ >= 0x61 && character_ <= 0x7A) || (character_ >= 0x30 && character_ <= 0x39)
        ) {
            character_ = bytes1(0x01);
        }

        // Adjust the name to contain invalid characters
        bytes memory name = new bytes(3);
        for (uint8 i; i < 3; i++) {
            if (i == index_) {
                name[i] = character_;
            } else {
                name[i] = 0x61; // 'a'
            }
        }

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IDepositManager.DepositManager_OperatorNameInvalid.selector)
        );

        // Call function with a name containing invalid characters
        vm.prank(ADMIN);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, string(name));
    }

    // [X] it sets the operator name
    // [X] it emits the OperatorNameSet event

    function test_success(
        bytes1 character1_,
        bytes1 character2_,
        bytes1 character3_
    ) public givenIsEnabled {
        // Ensure characters are lowercase letters or numbers
        if (
            (character1_ < 0x61 || character1_ > 0x7A) && (character1_ < 0x30 || character1_ > 0x39)
        ) {
            character1_ = bytes1(0x61); // 'a'
        }
        if (
            (character2_ < 0x61 || character2_ > 0x7A) && (character2_ < 0x30 || character2_ > 0x39)
        ) {
            character2_ = bytes1(0x61); // 'a'
        }
        if (
            (character3_ < 0x61 || character3_ > 0x7A) && (character3_ < 0x30 || character3_ > 0x39)
        ) {
            character3_ = bytes1(0x61); // 'a'
        }

        // Create the name from the characters
        bytes memory name = new bytes(3);
        name[0] = character1_;
        name[1] = character2_;
        name[2] = character3_;
        string memory nameStr = string(name);
        console2.log("Setting operator name to: %s", nameStr);

        // Expect event
        vm.expectEmit(true, true, false, true);
        emit OperatorNameSet(DEPOSIT_OPERATOR, nameStr);

        // Call function
        vm.prank(ADMIN);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, nameStr);

        // Validate
        assertEq(
            depositManager.getOperatorName(DEPOSIT_OPERATOR),
            nameStr,
            "Operator name not set correctly"
        );
    }
}
