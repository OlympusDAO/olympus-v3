// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {
    ICCIPFeeOnRampConfig,
    ICCIPFeeQuoter20,
    ICCIPFeeRouter,
    ICCIPFeeTypeAndVersion
} from "src/scripts/ops/lib/CCIPFeeBudgetLib.sol";
import {CCIPFeeBudgetLibTest} from "src/test/scripts/ops/lib/CCIPFeeBudgetLib/CCIPFeeBudgetLibTest.sol";

contract CCIPFeeBudgetLibTests_readOhmDestGasOverhead is CCIPFeeBudgetLibTest {
    // ========== ROUTER AND ON-RAMP VERSION ========== //

    // given the router has no on-ramp for the destination
    //   [X] it reverts
    function test_givenNoOnRamp_reverts() public {
        router.setReturn(ICCIPFeeRouter.getOnRamp.selector, abi.encode(address(0)));

        _expectRevertMessage(
            "CCIPFeeBudgetLib: the local router has no on-ramp for remote"
        );
        _read();
    }

    // given the on-ramp has no code
    //   [X] it reverts
    function test_givenOnRampHasNoCode_reverts() public {
        router.setReturn(ICCIPFeeRouter.getOnRamp.selector, abi.encode(makeAddr("eoa")));

        _expectRevertMessage(
            string.concat("CCIPFeeBudgetLib: the on-ramp of the lane ", LANE, " has no code")
        );
        _read();
    }

    // given the on-ramp does not answer typeAndVersion
    //   [X] it reverts
    function test_givenOnRampTypeAndVersionReverts_reverts() public {
        onRamp.setRevert(ICCIPFeeTypeAndVersion.typeAndVersion.selector);

        _expectRevertMessage(
            string.concat(
                "CCIPFeeBudgetLib: the on-ramp of the lane ",
                LANE,
                " does not answer typeAndVersion()"
            )
        );
        _read();
    }

    // given the on-ramp typeAndVersion does not parse
    //   [X] it reverts
    function test_givenOnRampVersionUnparsable_reverts() public {
        _setVersion(onRamp, "OnRamp");

        _expectRevertMessage(
            string.concat(
                "CCIPFeeBudgetLib: the on-ramp of the lane ",
                LANE,
                " reports typeAndVersion 'OnRamp', not a '<family> <major>.<minor>' string"
            )
        );
        _read();
    }

    // given the on-ramp family is unknown
    //   [X] it reverts
    function test_givenOnRampFamilyUnknown_reverts() public {
        _setVersion(onRamp, "OnRampV9 2.0.0");

        _expectRevertUnsupportedOnRamp("OnRampV9 2.0.0");
        _read();
    }

    // given the on-ramp family is right but the major is outside 1 to 2
    //   [X] it reverts
    function test_givenOnRampMajorUnsupported_reverts() public {
        _setVersion(onRamp, "OnRamp 3.0.0");
        _expectRevertUnsupportedOnRamp("OnRamp 3.0.0");
        _read();

        _setVersion(onRamp, "OnRamp 0.9.0");
        _expectRevertUnsupportedOnRamp("OnRamp 0.9.0");
        _read();
    }

    // given the legacy family with a minor other than 5
    //   [X] it reverts
    function test_givenLegacyOnRampMinorUnsupported_reverts() public {
        _setVersion(onRamp, "EVM2EVMOnRamp 1.6.0");
        _expectRevertUnsupportedOnRamp("EVM2EVMOnRamp 1.6.0");
        _read();

        _setVersion(onRamp, "EVM2EVMOnRamp 2.5.0");
        _expectRevertUnsupportedOnRamp("EVM2EVMOnRamp 2.5.0");
        _read();
    }

    // ========== ON-RAMP DYNAMIC CONFIG ========== //

    // given an OnRamp lane
    //   given the dynamic config reverts
    //     [X] it reverts
    function test_givenOnRamp20Lane_givenDynamicConfigReverts_reverts() public givenOnRamp20Lane {
        onRamp.setRevert(ICCIPFeeOnRampConfig.getDynamicConfig.selector);

        _expectRevertMessage(
            string.concat(
                "CCIPFeeBudgetLib: the on-ramp of the lane ",
                LANE,
                " does not answer getDynamicConfig()"
            )
        );
        _read();
    }

    // given an OnRamp lane
    //   given the dynamic config is empty
    //     [X] it reverts
    function test_givenOnRamp20Lane_givenDynamicConfigEmpty_reverts() public givenOnRamp20Lane {
        _setOnRampConfig(new uint256[](0));

        _expectRevertMessage(
            string.concat(
                "CCIPFeeBudgetLib: the on-ramp of the lane ",
                LANE,
                " does not answer getDynamicConfig()"
            )
        );
        _read();
    }

    // given an OnRamp lane
    //   given word zero of the dynamic config is not an address
    //     [X] it reverts
    function test_givenOnRamp20Lane_givenFeeQuoterWordDirty_reverts() public givenOnRamp20Lane {
        uint256[] memory words = new uint256[](3);
        words[0] = uint256(uint160(address(feeQuoter))) | (1 << 160);
        _setOnRampConfig(words);

        _expectRevertDoesNotFit("getDynamicConfig().feeQuoter");
        _read();
    }

    // given an OnRamp lane
    //   given word zero of the dynamic config is zero
    //     [X] it reverts
    function test_givenOnRamp20Lane_givenFeeQuoterZero_reverts() public givenOnRamp20Lane {
        _setOnRampConfig(new uint256[](3));

        _expectRevertMessage(
            string.concat("CCIPFeeBudgetLib: the on-ramp of the lane ", LANE, " has no fee quoter")
        );
        _read();
    }

    // given an OnRamp lane
    //   given word zero of the dynamic config names an account without code
    //     [X] it reverts
    function test_givenOnRamp20Lane_givenFeeQuoterHasNoCode_reverts() public givenOnRamp20Lane {
        uint256[] memory words = new uint256[](3);
        words[0] = uint256(uint160(makeAddr("eoa")));
        _setOnRampConfig(words);

        _expectRevertMessage(
            string.concat("CCIPFeeBudgetLib: the fee quoter of the lane ", LANE, " has no code")
        );
        _read();
    }

    // given an OnRamp lane
    //   given word zero names a contract of another family
    //     [X] it reverts
    function test_givenOnRamp20Lane_givenWordZeroIsNotAFeeQuoter_reverts() public givenOnRamp20Lane {
        _setVersion(feeQuoter, "PriceRegistry 2.0.0");

        _expectRevertUnsupportedFeeQuoter("PriceRegistry 2.0.0");
        _read();
    }

    // given an OnRamp lane
    //   given the fee quoter major is not 2
    //     [X] it reverts
    function test_givenOnRamp20Lane_givenFeeQuoterMajorUnsupported_reverts()
        public
        givenOnRamp20Lane
    {
        _setVersion(feeQuoter, "FeeQuoter 1.6.3");
        _expectRevertUnsupportedFeeQuoter("FeeQuoter 1.6.3");
        _read();

        _setVersion(feeQuoter, "FeeQuoter 3.0.0");
        _expectRevertUnsupportedFeeQuoter("FeeQuoter 3.0.0");
        _read();
    }

    // ========== FEE QUOTER TOKEN ENTRY SHAPE ========== //

    // given an OnRamp lane
    //   given the token entry has six words, the 1.6 layout
    //     [X] it reverts
    function test_givenOnRamp20Lane_givenTokenEntryHasSixWords_reverts() public givenOnRamp20Lane {
        _setTokenEntry20Words(6);

        _expectRevertWords("getTokenTransferFeeConfig", 6, 4);
        _read();
    }

    // given an OnRamp lane
    //   given the token entry has five words, an appended field
    //     [X] it reverts
    function test_givenOnRamp20Lane_givenTokenEntryHasFiveWords_reverts() public givenOnRamp20Lane {
        _setTokenEntry20Words(5);

        _expectRevertWords("getTokenTransferFeeConfig", 5, 4);
        _read();
    }

    // given an OnRamp lane
    //   given the token entry has three words, a dropped field
    //     [X] it reverts
    function test_givenOnRamp20Lane_givenTokenEntryHasThreeWords_reverts()
        public
        givenOnRamp20Lane
    {
        _setTokenEntry20Words(3);

        _expectRevertWords("getTokenTransferFeeConfig", 3, 4);
        _read();
    }

    // given an OnRamp lane
    //   given the token entry call reverts
    //     [X] it reverts
    function test_givenOnRamp20Lane_givenTokenEntryReverts_reverts() public givenOnRamp20Lane {
        feeQuoter.setRevert(ICCIPFeeQuoter20.getTokenTransferFeeConfig.selector);

        _expectRevertMessage(
            string.concat(
                "CCIPFeeBudgetLib: getTokenTransferFeeConfig reverted on the lane ",
                LANE
            )
        );
        _read();
    }

    // given an OnRamp lane
    //   given the destGasOverhead word does not fit a uint32
    //     [X] it reverts
    function test_givenOnRamp20Lane_givenDestGasOverheadWordDirty_reverts()
        public
        givenOnRamp20Lane
    {
        _setTokenEntry20Raw(10, uint256(type(uint32).max) + 1, 32, 1);

        _expectRevertDoesNotFit("getTokenTransferFeeConfig().destGasOverhead");
        _read();
    }

    // given an OnRamp lane
    //   given the isEnabled word is neither zero nor one
    //     [X] it reverts
    function test_givenOnRamp20Lane_givenIsEnabledWordDirty_reverts() public givenOnRamp20Lane {
        _setTokenEntry20Raw(10, 175_000, 32, 2);

        _expectRevertDoesNotFit("getTokenTransferFeeConfig().isEnabled");
        _read();
    }

    // ========== FEE QUOTER DEST CONFIG SHAPE ========== //

    // given an OnRamp lane without a token entry
    //   given the destination config has nineteen words, the 1.6 layout
    //     [X] it reverts
    function test_givenOnRamp20Lane_givenNoTokenEntry_givenDestConfigHasNineteenWords_reverts()
        public
        givenOnRamp20Lane
    {
        _setNoTokenEntry20();
        _setDestConfig20Words(19);

        _expectRevertWords("getDestChainConfig", 19, 11);
        _read();
    }

    // given an OnRamp lane without a token entry
    //   given the destination config has twelve words, an appended field
    //     [X] it reverts
    function test_givenOnRamp20Lane_givenNoTokenEntry_givenDestConfigHasTwelveWords_reverts()
        public
        givenOnRamp20Lane
    {
        _setNoTokenEntry20();
        _setDestConfig20Words(12);

        _expectRevertWords("getDestChainConfig", 12, 11);
        _read();
    }

    // given an OnRamp lane without a token entry
    //   given the chain family selector is SVM
    //     [X] it reverts
    function test_givenOnRamp20Lane_givenNoTokenEntry_givenFamilyIsSvm_reverts()
        public
        givenOnRamp20Lane
    {
        _setNoTokenEntry20();
        _setDestConfig20(SVM_FAMILY_WORD, CHAIN_DEFAULT);

        _expectRevertMessage(
            string.concat(
                "CCIPFeeBudgetLib: getDestChainConfig().chainFamilySelector on the lane ",
                LANE,
                " is ",
                vm.toString(SVM_FAMILY_WORD),
                ", expected the EVM family; the layout or the destination differs from the supported one"
            )
        );
        _read();
    }

    // given an OnRamp lane without a token entry
    //   given the chain family word carries the EVM selector with dirty low bytes
    //     [X] it reverts
    function test_givenOnRamp20Lane_givenNoTokenEntry_givenFamilyWordDirty_reverts()
        public
        givenOnRamp20Lane
    {
        _setNoTokenEntry20();
        bytes32 dirty = EVM_FAMILY_WORD | bytes32(uint256(1));
        _setDestConfig20(dirty, CHAIN_DEFAULT);

        _expectRevertMessage(
            string.concat(
                "CCIPFeeBudgetLib: getDestChainConfig().chainFamilySelector on the lane ",
                LANE,
                " is ",
                vm.toString(dirty),
                ", expected the EVM family; the layout or the destination differs from the supported one"
            )
        );
        _read();
    }

    // given an OnRamp lane without a token entry
    //   given the default word does not fit a uint32
    //     [X] it reverts
    function test_givenOnRamp20Lane_givenNoTokenEntry_givenDefaultWordDirty_reverts()
        public
        givenOnRamp20Lane
    {
        _setNoTokenEntry20();
        _setDestConfig20(EVM_FAMILY_WORD, uint256(type(uint32).max) + 1);

        _expectRevertDoesNotFit("getDestChainConfig().defaultTokenDestGasOverhead");
        _read();
    }

    // ========== SUCCESS: ONRAMP LANES ========== //

    // given an OnRamp 2.0.0 lane
    //   given a token entry
    //     [X] it returns the entry, flags it as a token entry and names both versions
    function test_givenOnRamp20Lane_givenTokenEntry()
        public
        givenOnRamp20Lane
        givenTokenEntry(175_000)
    {
        (uint32 overhead, bool isTokenEntry, string memory source) = _read();

        assertEq(overhead, 175_000, "overhead should be the token entry");
        assertTrue(isTokenEntry, "should be a token entry");
        assertEq(source, "OHM token entry, FeeQuoter 2.0.0 via OnRamp 2.0.0", "source");
    }

    // given an OnRamp 2.0.0 lane
    //   given no token entry
    //     [X] it returns the chain default, flags it as such and names both versions
    function test_givenOnRamp20Lane_givenNoTokenEntry() public givenOnRamp20Lane givenNoTokenEntry {
        (uint32 overhead, bool isTokenEntry, string memory source) = _read();

        assertEq(overhead, CHAIN_DEFAULT, "overhead should be the chain default");
        assertFalse(isTokenEntry, "should not be a token entry");
        assertEq(source, "chain default, FeeQuoter 2.0.0 via OnRamp 2.0.0 (no OHM entry)", "source");
    }

    // given an OnRamp 1.6.0 lane with the five-word dynamic config
    //   given a token entry
    //     [X] it reads the fee quoter from word zero
    function test_givenOnRamp16Lane_givenTokenEntry()
        public
        givenOnRamp16Lane
        givenTokenEntry(200_000)
    {
        (uint32 overhead, bool isTokenEntry, string memory source) = _read();

        assertEq(overhead, 200_000, "overhead should be the token entry");
        assertTrue(isTokenEntry, "should be a token entry");
        assertEq(source, "OHM token entry, FeeQuoter 2.0.0 via OnRamp 1.6.0", "source");
    }

    // given an OnRamp 1.6.0 lane
    //   given no token entry
    //     [X] it returns the chain default
    function test_givenOnRamp16Lane_givenNoTokenEntry() public givenOnRamp16Lane givenNoTokenEntry {
        (uint32 overhead, bool isTokenEntry, string memory source) = _read();

        assertEq(overhead, CHAIN_DEFAULT, "overhead should be the chain default");
        assertFalse(isTokenEntry, "should not be a token entry");
        assertEq(source, "chain default, FeeQuoter 2.0.0 via OnRamp 1.6.0 (no OHM entry)", "source");
    }

    // given an OnRamp lane whose dynamic config has an appended member
    //   given a token entry
    //     [X] it still reads the fee quoter from word zero
    function test_givenOnRamp20Lane_givenDynamicConfigHasAppendedWord_givenTokenEntry()
        public
        givenOnRamp20Lane
        givenTokenEntry(175_000)
    {
        _setOnRampConfigNamingQuoter(4);

        (uint32 overhead, bool isTokenEntry, ) = _read();

        assertEq(overhead, 175_000, "overhead should be the token entry");
        assertTrue(isTokenEntry, "should be a token entry");
    }

    // given an OnRamp lane whose dynamic config is the single fee quoter word
    //   given a token entry
    //     [X] it reads the fee quoter from word zero
    function test_givenOnRamp20Lane_givenDynamicConfigHasOneWord_givenTokenEntry()
        public
        givenOnRamp20Lane
        givenTokenEntry(175_000)
    {
        _setOnRampConfigNamingQuoter(1);

        (uint32 overhead, bool isTokenEntry, ) = _read();

        assertEq(overhead, 175_000, "overhead should be the token entry");
        assertTrue(isTokenEntry, "should be a token entry");
    }

    // given an OnRamp lane of any 1.x or 2.x version with a FeeQuoter of any 2.x version
    //   given a token entry
    //     [X] it reads the entry and names the versions read
    function test_givenOnRampAndFeeQuoterMinorsVary_givenTokenEntry(
        uint8 onRampMajorSeed_,
        uint32 onRampMinor_,
        uint32 onRampPatch_,
        uint32 quoterMinor_,
        uint32 quoterPatch_
    ) public givenOnRamp20Lane givenTokenEntry(175_000) {
        // The on-ramp major is 1 or 2, the accepted interval
        uint256 onRampMajor = bound(onRampMajorSeed_, 1, 2);
        string memory onRampVersion = string.concat(
            "OnRamp ",
            vm.toString(onRampMajor),
            ".",
            vm.toString(uint256(onRampMinor_)),
            ".",
            vm.toString(uint256(onRampPatch_))
        );
        string memory quoterVersion = string.concat(
            "FeeQuoter 2.",
            vm.toString(uint256(quoterMinor_)),
            ".",
            vm.toString(uint256(quoterPatch_))
        );
        _setVersion(onRamp, onRampVersion);
        _setVersion(feeQuoter, quoterVersion);

        (uint32 overhead, bool isTokenEntry, string memory source) = _read();

        assertEq(overhead, 175_000, "overhead should be the token entry");
        assertTrue(isTokenEntry, "should be a token entry");
        assertEq(
            source,
            string.concat("OHM token entry, ", quoterVersion, " via ", onRampVersion),
            "source should name the versions read"
        );
    }

    // given an OnRamp lane
    //   given a token entry of any budget
    //     [X] it returns that budget unchanged
    function test_givenOnRamp20Lane_givenTokenEntryOfAnyBudget(uint32 budget_) public givenOnRamp20Lane {
        _setTokenEntry20(budget_);

        (uint32 overhead, bool isTokenEntry, ) = _read();

        assertEq(overhead, budget_, "overhead should be the token entry");
        assertTrue(isTokenEntry, "should be a token entry");
    }

    // ========== LEGACY 1.5 LANES ========== //

    // given a legacy lane
    //   given the token entry has six words
    //     [X] it reverts
    function test_givenLegacyLane_givenTokenEntryHasSixWords_reverts() public givenLegacyLane {
        _setTokenEntry15Words(6);

        _expectRevertWords("getTokenTransferFeeConfig", 6, 7);
        _read();
    }

    // given a legacy lane
    //   given the token entry has eight words
    //     [X] it reverts
    function test_givenLegacyLane_givenTokenEntryHasEightWords_reverts() public givenLegacyLane {
        _setTokenEntry15Words(8);

        _expectRevertWords("getTokenTransferFeeConfig", 8, 7);
        _read();
    }

    // given a legacy lane
    //   given the isEnabled word is neither zero nor one
    //     [X] it reverts
    function test_givenLegacyLane_givenIsEnabledWordDirty_reverts() public givenLegacyLane {
        _setTokenEntry15Raw(175_000, 2);

        _expectRevertDoesNotFit("getTokenTransferFeeConfig().isEnabled");
        _read();
    }

    // given a legacy lane without a token entry
    //   given the dynamic config has twelve words
    //     [X] it reverts
    function test_givenLegacyLane_givenNoTokenEntry_givenDynamicConfigHasTwelveWords_reverts()
        public
        givenLegacyLane
    {
        _setTokenEntry15Raw(0, 0);
        _setOnRampConfig(new uint256[](12));

        _expectRevertWords("getDynamicConfig", 12, 13);
        _read();
    }

    // given a legacy lane
    //   given a token entry
    //     [X] it returns the entry and names the on-ramp version
    function test_givenLegacyLane_givenTokenEntry()
        public
        givenLegacyLane
        givenLegacyTokenEntry(175_000)
    {
        (uint32 overhead, bool isTokenEntry, string memory source) = _read();

        assertEq(overhead, 175_000, "overhead should be the token entry");
        assertTrue(isTokenEntry, "should be a token entry");
        assertEq(source, "OHM token entry, EVM2EVMOnRamp 1.5.0", "source");
    }

    // given a legacy lane
    //   given no token entry
    //     [X] it returns the lane default from word eleven of the dynamic config
    function test_givenLegacyLane_givenNoTokenEntry() public givenLegacyLane givenLegacyNoTokenEntry {
        (uint32 overhead, bool isTokenEntry, string memory source) = _read();

        assertEq(overhead, CHAIN_DEFAULT, "overhead should be the lane default");
        assertFalse(isTokenEntry, "should not be a token entry");
        assertEq(source, "chain default, EVM2EVMOnRamp 1.5.0 (no OHM entry)", "source");
    }

    // given a legacy lane of any 1.5 patch version
    //   given a token entry
    //     [X] it reads the entry
    function test_givenLegacyLanePatchVaries_givenTokenEntry(
        uint32 patch_
    ) public givenLegacyLane givenLegacyTokenEntry(175_000) {
        string memory version = string.concat("EVM2EVMOnRamp 1.5.", vm.toString(uint256(patch_)));
        _setVersion(onRamp, version);

        (uint32 overhead, bool isTokenEntry, string memory source) = _read();

        assertEq(overhead, 175_000, "overhead should be the token entry");
        assertTrue(isTokenEntry, "should be a token entry");
        assertEq(source, string.concat("OHM token entry, ", version), "source");
    }
}
