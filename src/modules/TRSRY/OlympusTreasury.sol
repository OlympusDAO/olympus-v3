// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";

import "src/modules/TRSRY/TRSRY.v1.sol";
import "src/Kernel.sol";

/// @notice Treasury holds all other assets under the control of the protocol.
contract OlympusTreasury is TRSRYv1_1, ReentrancyGuard {
    using TransferHelper for ERC20;

    //============================================================================================//
    //                                      MODULE SETUP                                          //
    //============================================================================================//

    constructor(Kernel kernel_) Module(kernel_) {
        active = true;
    }

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("TRSRY");
    }

    /// @inheritdoc Module
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 1;
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @inheritdoc TRSRYv1
    function increaseWithdrawApproval(
        address withdrawer_,
        ERC20 token_,
        uint256 amount_
    ) external override permissioned {
        uint256 approval = withdrawApproval[withdrawer_][token_];

        uint256 newAmount = type(uint256).max - approval <= amount_
            ? type(uint256).max
            : approval + amount_;
        withdrawApproval[withdrawer_][token_] = newAmount;

        emit IncreaseWithdrawApproval(withdrawer_, token_, newAmount);
    }

    /// @inheritdoc TRSRYv1
    function decreaseWithdrawApproval(
        address withdrawer_,
        ERC20 token_,
        uint256 amount_
    ) external override permissioned {
        uint256 approval = withdrawApproval[withdrawer_][token_];

        uint256 newAmount = approval <= amount_ ? 0 : approval - amount_;
        withdrawApproval[withdrawer_][token_] = newAmount;

        emit DecreaseWithdrawApproval(withdrawer_, token_, newAmount);
    }

    /// @inheritdoc TRSRYv1
    function withdrawReserves(
        address to_,
        ERC20 token_,
        uint256 amount_
    ) public override permissioned onlyWhileActive {
        withdrawApproval[msg.sender][token_] -= amount_;

        token_.safeTransfer(to_, amount_);

        emit Withdrawal(msg.sender, to_, token_, amount_);
    }

    // =========  DEBT FUNCTIONS ========= //

    /// @inheritdoc TRSRYv1
    function increaseDebtorApproval(
        address debtor_,
        ERC20 token_,
        uint256 amount_
    ) external override permissioned {
        uint256 newAmount = debtApproval[debtor_][token_] + amount_;
        debtApproval[debtor_][token_] = newAmount;
        emit IncreaseDebtorApproval(debtor_, token_, newAmount);
    }

    /// @inheritdoc TRSRYv1
    function decreaseDebtorApproval(
        address debtor_,
        ERC20 token_,
        uint256 amount_
    ) external override permissioned {
        uint256 newAmount = debtApproval[debtor_][token_] - amount_;
        debtApproval[debtor_][token_] = newAmount;
        emit DecreaseDebtorApproval(debtor_, token_, newAmount);
    }

    /// @inheritdoc TRSRYv1
    function incurDebt(
        ERC20 token_,
        uint256 amount_
    ) external override permissioned onlyWhileActive {
        debtApproval[msg.sender][token_] -= amount_;

        // Add debt to caller
        reserveDebt[token_][msg.sender] += amount_;
        totalDebt[token_] += amount_;

        token_.safeTransfer(msg.sender, amount_);

        emit DebtIncurred(token_, msg.sender, amount_);
    }

    /// @inheritdoc TRSRYv1
    function repayDebt(
        address debtor_,
        ERC20 token_,
        uint256 amount_
    ) external override permissioned nonReentrant {
        if (reserveDebt[token_][debtor_] == 0) revert TRSRY_NoDebtOutstanding();

        // Deposit from caller first (to handle nonstandard token transfers)
        uint256 prevBalance = token_.balanceOf(address(this));
        token_.safeTransferFrom(msg.sender, address(this), amount_);

        uint256 received = token_.balanceOf(address(this)) - prevBalance;

        // Choose minimum between passed-in amount and received amount
        if (received > amount_) received = amount_;

        // Subtract debt from debtor
        reserveDebt[token_][debtor_] -= received;
        totalDebt[token_] -= received;

        emit DebtRepaid(token_, debtor_, received);
    }

    /// @inheritdoc TRSRYv1
    function setDebt(
        address debtor_,
        ERC20 token_,
        uint256 amount_
    ) external override permissioned {
        uint256 oldDebt = reserveDebt[token_][debtor_];

        reserveDebt[token_][debtor_] = amount_;

        if (oldDebt < amount_) totalDebt[token_] += amount_ - oldDebt;
        else totalDebt[token_] -= oldDebt - amount_;

        emit DebtSet(token_, debtor_, amount_);
    }

    /// @inheritdoc TRSRYv1
    function deactivate() external override permissioned {
        active = false;
    }

    /// @inheritdoc TRSRYv1
    function activate() external override permissioned {
        active = true;
    }

    //============================================================================================//
    //                                       VIEW FUNCTIONS                                       //
    //============================================================================================//

    /// @inheritdoc TRSRYv1
    function getReserveBalance(ERC20 token_) public view override returns (uint256) {
        return token_.balanceOf(address(this)) + totalDebt[token_];
    }

    //============================================================================================//
    //                                       DATA FUNCTIONS                                       //
    //============================================================================================//

    // ========== ASSET INFORMATION ========== //

    function getAssets() external view override returns (address[] memory) {
        return assets;
    }

    function getAssetData(address asset_) external view override returns (Asset memory) {
        return assetData[asset_];
    }

    function getAssetsByCategory(
        Category category_
    ) public view override returns (address[] memory) {
        // Get category group
        CategoryGroup group = categoryToGroup[category_];
        if (fromCategoryGroup(group) == bytes32(0))
            revert TRSRY_InvalidParams(0, abi.encode(category_));

        // Iterate through assets and count the ones in the category
        uint256 len = assets.length;
        uint256 count;
        for (uint256 i; i < len; i++) {
            if (fromCategory(categorization[assets[i]][group]) == fromCategory(category_)) {
                unchecked {
                    ++count;
                }
            }
        }

        // Create array and iterate through assets again to populate it
        address[] memory categoryAssets = new address[](count);
        count = 0;
        for (uint256 i; i < len; i++) {
            if (fromCategory(categorization[assets[i]][group]) == fromCategory(category_)) {
                categoryAssets[count] = assets[i];
                unchecked {
                    ++count;
                }
            }
        }

        return categoryAssets;
    }

    function getAssetBalance(
        address asset_,
        Variant variant_
    ) public view override returns (uint256, uint48) {
        // Check if asset is approved
        if (!assetData[asset_].approved) revert TRSRY_AssetNotApproved(asset_);

        // Route to correct balance function based on requested variant
        if (variant_ == Variant.CURRENT) {
            return _getCurrentBalance(asset_);
        } else if (variant_ == Variant.LAST) {
            return _getLastBalance(asset_);
        } else {
            revert TRSRY_InvalidParams(1, abi.encode(variant_));
        }
    }

    function _getCurrentBalance(address asset_) internal view returns (uint256, uint48) {
        Asset memory asset = assetData[asset_];
        ERC20 token = ERC20(asset_);

        // Get reserve balance from this contract to begin with
        uint256 balance = getReserveBalance(token);

        // Get balances from other locations
        uint256 len = asset.locations.length;
        for (uint256 i; i < len; ) {
            balance += token.balanceOf(asset.locations[i]);
            unchecked {
                ++i;
            }
        }

        return (balance, uint48(block.timestamp));
    }

    function _getLastBalance(address asset_) internal view returns (uint256, uint48) {
        // Return last balance and time
        return (assetData[asset_].lastBalance, assetData[asset_].updatedAt);
    }

    function storeBalance(address asset_) external override permissioned returns (uint256) {
        Asset storage asset = assetData[asset_];

        // Check that asset is approved
        if (!asset.approved) revert TRSRY_AssetNotApproved(asset_);

        // Get the current balance for the asset
        (uint256 balance, uint48 time) = _getCurrentBalance(asset_);

        // Store the data
        asset.lastBalance = balance;
        asset.updatedAt = time;

        // Emit event
        emit BalanceStored(asset_, balance, time);

        return balance;
    }

    function getCategoryBalance(
        Category category_,
        Variant variant_
    ) external view override returns (uint256, uint48) {
        // Get category group and check that it is valid
        CategoryGroup group = categoryToGroup[category_];
        if (fromCategoryGroup(group) == bytes32(0))
            revert TRSRY_InvalidParams(0, abi.encode(category_));

        // Get category assets
        address[] memory categoryAssets = getAssetsByCategory(category_);

        // Get balance for each asset and add to total
        uint256 len = categoryAssets.length;
        uint256 balance;
        uint48 time;
        for (uint256 i; i < len; ) {
            (uint256 assetBalance, uint48 assetTime) = getAssetBalance(categoryAssets[i], variant_);
            balance += assetBalance;
            if (i == 0) {
                time = assetTime;
            } else if (assetTime < time) {
                time = assetTime;
            }
            unchecked {
                ++i;
            }
        }

        return (balance, time);
    }

    // ========== DATA MANAGEMENT ========== //

    function addAsset(
        address asset_,
        address[] calldata locations_
    ) external override permissioned {
        Asset storage asset = assetData[asset_];

        // Ensure asset is not already added
        if (asset.approved) revert TRSRY_AssetAlreadyApproved(asset_);

        // Check that asset is a contract
        if (asset_.code.length == 0) revert TRSRY_AssetNotContract(asset_);

        // Set asset as approved and add to array
        asset.approved = true;
        assets.push(asset_);

        // Validate balance locations and store
        uint256 len = locations_.length;
        for (uint256 i; i < len; ) {
            if (locations_[i] == address(0))
                revert TRSRY_InvalidParams(1, abi.encode(locations_[i]));
            asset.locations.push(locations_[i]);
            unchecked {
                ++i;
            }
        }

        // Initialize cache with current value
        (asset.lastBalance, asset.updatedAt) = _getCurrentBalance(asset_);
    }

    // TODO remove asset?

    function addAssetLocation(address asset_, address location_) external override permissioned {
        Asset storage asset = assetData[asset_];

        // Check that asset is approved
        if (!asset.approved) revert TRSRY_AssetNotApproved(asset_);

        // Check that the location is not the zero address
        if (location_ == address(0)) revert TRSRY_InvalidParams(1, abi.encode(location_));

        // Check that location is not already added
        uint256 len = asset.locations.length;
        for (uint256 i; i < len; ) {
            if (asset.locations[i] == location_)
                revert TRSRY_InvalidParams(1, abi.encode(location_));
            unchecked {
                ++i;
            }
        }

        // Add location to array
        asset.locations.push(location_);
    }

    function removeAssetLocation(address asset_, address location_) external override permissioned {
        Asset storage asset = assetData[asset_];

        // Check that asset is approved
        if (!asset.approved) revert TRSRY_AssetNotApproved(asset_);

        // Remove location
        // Don't have to check if it's already added because the loop will just not perform any actions is not
        uint256 len = asset.locations.length;
        for (uint256 i; i < len; ) {
            if (asset.locations[i] == location_) {
                asset.locations[i] = asset.locations[len - 1];
                asset.locations.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }
    }

    function addCategoryGroup(CategoryGroup group_) external override permissioned {
        // Check if the category group exists
        if (_categoryGroupExists(group_)) revert TRSRY_CategoryGroupExists(group_);

        // Store new category group
        categoryGroups.push(group_);
    }

    function addCategory(Category category_, CategoryGroup group_) external override permissioned {
        // Check if the category group exists
        if (!_categoryGroupExists(group_)) revert TRSRY_CategoryGroupDoesNotExist(group_);

        // Check if the category exists by seeing if it has a non-zero category group
        if (fromCategoryGroup(categoryToGroup[category_]) != bytes32(0))
            revert TRSRY_CategoryExists(category_);

        // Store category data
        categoryToGroup[category_] = group_;
        groupToCategories[group_].push(category_);
    }

    // TODO remove category?

    function _categoryGroupExists(CategoryGroup categoryGroup_) internal view returns (bool) {
        // It's expected that the number of category groups will be fairly small
        // so we should be able to iterate through them instead of creating a mapping
        uint256 len = categoryGroups.length;
        for (uint256 i; i < len; ) {
            if (fromCategoryGroup(categoryGroups[i]) == fromCategoryGroup(categoryGroup_))
                return true;
            unchecked {
                ++i;
            }
        }
        return false;
    }

    function categorize(address asset_, Category category_) external override permissioned {
        // Check that address is not zero
        if (asset_ == address(0)) revert TRSRY_InvalidParams(0, abi.encode(asset_));

        // Check if the category exists by seeing if it has a non-zero category group
        CategoryGroup group = categoryToGroup[category_];
        if (fromCategoryGroup(group) == bytes32(0)) revert TRSRY_CategoryDoesNotExist(category_);

        // Store category data for address
        categorization[asset_][group] = category_;
    }
}
