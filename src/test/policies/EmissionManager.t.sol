// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {BondFixedTermSDA} from "test/lib/bonds/BondFixedTermSDA.sol";
import {BondAggregator} from "test/lib/bonds/BondAggregator.sol";
import {BondFixedTermTeller} from "test/lib/bonds/BondFixedTermTeller.sol";
import {RolesAuthority, Authority as SolmateAuthority} from "solmate/auth/authorities/RolesAuthority.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626, ERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {MockPrice} from "test/mocks/MockPrice.sol";
import {MockOhm} from "test/mocks/MockOhm.sol";
import {MockClearinghouse} from "test/mocks/MockClearinghouse.sol";

import {IBondSDA} from "interfaces/IBondSDA.sol";
import {IBondAggregator} from "interfaces/IBondAggregator.sol";

import {FullMath} from "libraries/FullMath.sol";

import "src/Kernel.sol";
import {OlympusRange} from "modules/RANGE/OlympusRange.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {EmissionManager} from "policies/EmissionManager.sol";
import {Operator} from "policies/Operator.sol";
import {BondCallback} from "policies/BondCallback.sol";

// solhint-disable-next-line max-states-count
contract EmissionManagerTest is Test {
    // core functionality
    // [ ] execute
    //   [ ] when not locally active
    //     [ ] it reverts
    //   [ ] when locally active
    //     [ ] when beatCounter != 2
    //        [ ] it returns without doing anything
    //     [ ] when beatCounter == 2
    //        [ ] when current OHM balance is not zero
    //           [ ] it reduces supply added from the last sale
    //        [ ] when current DAI balance is not zero
    //           [ ] it increments the reserves added from the last sale
    //           [ ] it deposits the DAI into sDAI and sends it to the treasury
    //           [ ] it updates the backing price value based on the reserves added and supply added values from the last sale
    //        TODO mint or burn OHM based on amount needed for sale
    //
    // view functions
    // [ ] getSupply
    // [ ] getReseves
    //
    // emergency functions
    // [ ] shutdown
    // [ ] restart
    //
    // admin functions
    // [ ] initialize
    // [ ] setBaseRate
    // [ ] setMinimumPremium
    // [ ] adjustBacking
    // [ ] adjustRestartTimeframe
    // [ ] updateBondContracts
}
