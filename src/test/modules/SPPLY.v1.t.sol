// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {OlympusERC20Token} from "src/external/OlympusERC20.sol";
//import {MockPolicy} from "test/mocks/KernelTestMocks.sol";

import "src/modules/SPPLY/OlympusSupply.sol";

// Tests for OlympusSupply v1.0
// TODO
// Module Setup
// [ ] KEYCODE - returns the module's identifier: SPPLY
// [ ] VERSION - returns the module's version: 1.0
//
// Cross-chain Supply
// [ ] addChain - adds a new chain for cross-chain supply tracking
//      [ ] reverts if caller is not permissioned
//      [ ] reverts if chain already approved
//      [ ] stores chainId in chainIds array
//      [ ] stores ohm address on chain
// [ ] removeChain - removes a chain from cross-chain supply tracking
//      [ ] reverts if caller is not permissioned
//      [ ] reverts if chain not approved
//      [ ] removes chain supply from totalCrossChainSupply
//      [ ] deletes chain supply from mapping
//      [ ] removes chainId from chainIds array
//      [ ] deletes chain ohm address from mapping
// [ ] updateCrossChainSupplies - updates cross-chain supplies for the provided chains and the category supplies (across all other chains) from the provided categories
//      [ ] reverts if caller is not permissioned
//      [ ] reverts if number of chainIds doesn't match number of chain supplies provided
//      [ ] reverts if any of the chainIds are not approved
//      [ ] reverts if any of the categories are not approved
//      [ ] reverts if number of categories doesn't match number of category supplies provided
//      [ ] updates cross-chain supply for each chain provided
//      [ ] updates category supply for each category provided
//      [ ] updates totalCrossChainSupply with the sum of the chain supplies provided and reduces by the existing chain supply values
//      [ ] emits event for each chain supply update
//      [ ] emits event for each category supply update
// [ ] getCrossChainIds - returns array of all approved chainIds
//      [ ] zero chains
//      [ ] one chain
//      [ ] many chains
//
// Supply Categorization
// [ ] addCategory - adds a new category for supply tracking
// [ ] removeCategory - removes a category from supply tracking
// [ ] categorize - categorizes an OHM location in a category for supply tracking
// [ ] getLocations - returns array of all locations where supply is tracked
// [ ] getCategories - returns array of all categories used to track supply
// [ ] getLocationsByCategory - returns array of all locations categorized in a given category
// [ ] getSupplyByCategory - returns the supply of a given category (totaled from across all locations)
//    [ ] zero supply
//    [ ] OHM supply
//    [ ] gOHM supply
//    [ ] cross-chain supply
//    [ ] handles submodules
//    [ ] reverts upon submodule failure
//
// Supply Metrics
// [ ] totalSupply - returns the total supply of OHM, including cross-chain OHM
// [ ] circulatingSupply
// [ ] floatingSupply
// [ ] collateralizedSupply
// [ ] backedSupply
