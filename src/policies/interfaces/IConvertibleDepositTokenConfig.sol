// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

interface IConvertibleDepositTokenConfig {
    /// @notice Creates a new CD token
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Creating a new CD token
    ///         - Emitting an event
    ///
    /// @param  vault_          The address of the vault to use for the CD token
    /// @param  periodMonths_   The period of the CD token
    /// @param  reclaimRate_    The reclaim rate to set for the CD token
    /// @return cdToken         The address of the new CD token
    function create(
        IERC4626 vault_,
        uint8 periodMonths_,
        uint16 reclaimRate_
    ) external returns (IConvertibleDepositERC20 cdToken);

    /// @notice Sets the reclaim rate for a CD token
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Setting the reclaim rate for the CD token
    ///
    /// @param  cdToken_      The address of the CD token
    /// @param  reclaimRate_  The reclaim rate to set
    function setReclaimRate(IConvertibleDepositERC20 cdToken_, uint16 reclaimRate_) external;
}
