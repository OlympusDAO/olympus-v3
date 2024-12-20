// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {ModuleTestFixtureGenerator} from "src/test/lib/ModuleTestFixtureGenerator.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";
import {OlympusConvertibleDepository} from "src/modules/CDEPO/OlympusConvertibleDepository.sol";

abstract contract CDEPOTest is Test {
    using ModuleTestFixtureGenerator for OlympusConvertibleDepository;

    Kernel public kernel;
    OlympusConvertibleDepository public CDEPO;
    MockERC20 public reserveToken;
    MockERC4626 public vault;
    address public godmode;
    address public recipient = address(0x1);
    address public recipientTwo = address(0x2);
    uint256 public constant INITIAL_VAULT_BALANCE = 10e18;
    uint16 public reclaimRate = 99e2;

    uint48 public constant INITIAL_BLOCK = 100000000;

    function setUp() public {
        vm.warp(INITIAL_BLOCK);

        reserveToken = new MockERC20("Reserve Token", "RST", 18);
        vault = new MockERC4626(reserveToken, "sReserve Token", "sRST");

        // Mint reserve tokens to the vault without depositing, so that the conversion is not 1
        reserveToken.mint(address(vault), INITIAL_VAULT_BALANCE);

        kernel = new Kernel();
        CDEPO = new OlympusConvertibleDepository(address(kernel), address(vault));

        // Generate fixtures
        godmode = CDEPO.generateGodmodeFixture(type(OlympusConvertibleDepository).name);

        // Install modules and policies on Kernel
        kernel.executeAction(Actions.InstallModule, address(CDEPO));
        kernel.executeAction(Actions.ActivatePolicy, godmode);

        // Set reclaim rate
        vm.prank(godmode);
        CDEPO.setReclaimRate(reclaimRate);
    }

    // ========== ASSERTIONS ========== //

    function _assertReserveTokenBalance(
        uint256 recipientAmount_,
        uint256 recipientTwoAmount_
    ) internal {
        assertEq(
            reserveToken.balanceOf(recipient),
            recipientAmount_,
            "recipient: reserve token balance"
        );
        assertEq(
            reserveToken.balanceOf(recipientTwo),
            recipientTwoAmount_,
            "recipientTwo: reserve token balance"
        );

        assertEq(
            reserveToken.totalSupply(),
            reserveToken.balanceOf(address(CDEPO.vault())) + recipientAmount_ + recipientTwoAmount_,
            "reserve token balance: total supply"
        );
    }

    function _assertCDEPOBalance(uint256 recipientAmount_, uint256 recipientTwoAmount_) internal {
        assertEq(CDEPO.balanceOf(recipient), recipientAmount_, "recipient: CDEPO balance");
        assertEq(CDEPO.balanceOf(recipientTwo), recipientTwoAmount_, "recipientTwo: CDEPO balance");

        assertEq(
            CDEPO.totalSupply(),
            recipientAmount_ + recipientTwoAmount_,
            "CDEPO balance: total supply"
        );
    }

    function _assertVaultBalance(
        uint256 recipientAmount_,
        uint256 recipientTwoAmount_,
        uint256 forfeitedAmount_
    ) internal {
        assertEq(
            vault.totalAssets(),
            recipientAmount_ + recipientTwoAmount_ + INITIAL_VAULT_BALANCE + forfeitedAmount_,
            "vault: total assets"
        );

        assertGt(vault.balanceOf(address(CDEPO)), 0, "CDEPO: vault balance > 0");
        assertEq(vault.balanceOf(recipient), 0, "recipient: vault balance = 0");
        assertEq(vault.balanceOf(recipientTwo), 0, "recipientTwo: vault balance = 0");
    }

    function _assertTotalShares(uint256 withdrawnAmount_) internal {
        // Calculate the amount of reserve tokens that remain in the vault
        uint256 vaultLockedReserveTokens = reserveToken.totalSupply() - withdrawnAmount_;

        // Convert to shares
        uint256 expectedShares = vault.previewWithdraw(vaultLockedReserveTokens);

        assertEq(CDEPO.totalShares(), expectedShares, "total shares");
    }

    // ========== MODIFIERS ========== //

    function _mintReserveToken(address to_, uint256 amount_) internal {
        reserveToken.mint(to_, amount_);
    }

    modifier givenAddressHasReserveToken(address to_, uint256 amount_) {
        _mintReserveToken(to_, amount_);
        _;
    }

    function _approveReserveTokenSpending(
        address owner_,
        address spender_,
        uint256 amount_
    ) internal {
        vm.prank(owner_);
        reserveToken.approve(spender_, amount_);
    }

    modifier givenReserveTokenSpendingIsApproved(
        address owner_,
        address spender_,
        uint256 amount_
    ) {
        _approveReserveTokenSpending(owner_, spender_, amount_);
        _;
    }

    function _approveConvertibleDepositTokenSpending(
        address owner_,
        address spender_,
        uint256 amount_
    ) internal {
        vm.prank(owner_);
        CDEPO.approve(spender_, amount_);
    }

    modifier givenConvertibleDepositTokenSpendingIsApproved(
        address owner_,
        address spender_,
        uint256 amount_
    ) {
        _approveConvertibleDepositTokenSpending(owner_, spender_, amount_);
        _;
    }

    function _mint(uint256 amount_) internal {
        vm.prank(recipient);
        CDEPO.mint(amount_);
    }

    function _mintFor(address owner_, address to_, uint256 amount_) internal {
        vm.prank(owner_);
        CDEPO.mintFor(to_, amount_);
    }

    modifier givenRecipientHasCDEPO(uint256 amount_) {
        _mint(amount_);
        _;
    }

    modifier givenAddressHasCDEPO(address to_, uint256 amount_) {
        _mintFor(to_, to_, amount_);
        _;
    }

    modifier givenReclaimRateIsSet(uint16 reclaimRate_) {
        vm.prank(godmode);
        CDEPO.setReclaimRate(reclaimRate_);

        reclaimRate = reclaimRate_;
        _;
    }
}
