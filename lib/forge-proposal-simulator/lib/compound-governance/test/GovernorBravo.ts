import {
  loadFixture,
  time,
  mine,
  impersonateAccount,
} from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import {
  setupGovernorBravo,
  setupGovernorAlpha,
  propose,
  proposeAndPass,
  proposeAndQueue,
  getTypedDomain,
  getVoteTypes,
  getVoteWithReasonTypes,
  getProposeTypes,
  ProposalState,
  proposeAndExecute,
} from "./governanceHelpers";
import {
  GovernorBravoDelegate,
  GovernorBravoDelegator,
} from "../typechain-types";

describe("Governor Bravo", function () {
  async function deployFixtures() {
    const [owner, otherAccount] = await ethers.getSigners();
    const { governorAlpha, timelock, comp } = await setupGovernorAlpha();
    const { governorBravo } = await setupGovernorBravo(
      timelock,
      comp,
      governorAlpha
    );

    return { owner, otherAccount, governorBravo, comp };
  }

  describe("Initialize", function () {
    it("Happy Path", async function () {
      const GovernorBravoDelegator = await ethers.getContractFactory(
        "GovernorBravoDelegator"
      );
      const GovernorBravoDelegate = await ethers.getContractFactory(
        "GovernorBravoDelegate"
      );
      const addresses = (await ethers.getSigners()).slice(3);
      const governorBravoDelegate = await GovernorBravoDelegate.deploy();
      await GovernorBravoDelegator.deploy(
        addresses[0],
        addresses[1],
        addresses[2],
        governorBravoDelegate,
        5760,
        100,
        BigInt("1000") * 10n ** 18n
      );
    });

    it("Error: voting period", async function () {
      const GovernorBravoDelegator = await ethers.getContractFactory(
        "GovernorBravoDelegator"
      );
      const GovernorBravoDelegate = await ethers.getContractFactory(
        "GovernorBravoDelegate"
      );
      const addresses = (await ethers.getSigners()).slice(3);
      const governorBravoDelegate = await GovernorBravoDelegate.deploy();
      await expect(
        GovernorBravoDelegator.deploy(
          addresses[0],
          addresses[1],
          addresses[2],
          governorBravoDelegate,
          5759,
          100,
          BigInt("1000") * 10n ** 18n
        )
      ).to.be.revertedWith("GovernorBravo::initialize: invalid voting period");

      await expect(
        GovernorBravoDelegator.deploy(
          addresses[0],
          addresses[1],
          addresses[2],
          governorBravoDelegate,
          80641,
          100,
          BigInt("1000") * 10n ** 18n
        )
      ).to.be.revertedWith("GovernorBravo::initialize: invalid voting period");
    });

    it("Error: voting delay", async function () {
      const GovernorBravoDelegator = await ethers.getContractFactory(
        "GovernorBravoDelegator"
      );
      const GovernorBravoDelegate = await ethers.getContractFactory(
        "GovernorBravoDelegate"
      );
      const addresses = (await ethers.getSigners()).slice(3);
      const governorBravoDelegate = await GovernorBravoDelegate.deploy();
      await expect(
        GovernorBravoDelegator.deploy(
          addresses[0],
          addresses[1],
          addresses[2],
          governorBravoDelegate,
          5760,
          0,
          BigInt("1000") * 10n ** 18n
        )
      ).to.be.revertedWith("GovernorBravo::initialize: invalid voting delay");

      await expect(
        GovernorBravoDelegator.deploy(
          addresses[0],
          addresses[1],
          addresses[2],
          governorBravoDelegate,
          5760,
          40321,
          BigInt("1000") * 10n ** 18n
        )
      ).to.be.revertedWith("GovernorBravo::initialize: invalid voting delay");
    });

    it("Error: proposal threshold", async function () {
      const GovernorBravoDelegator = await ethers.getContractFactory(
        "GovernorBravoDelegator"
      );
      const GovernorBravoDelegate = await ethers.getContractFactory(
        "GovernorBravoDelegate"
      );
      const addresses = (await ethers.getSigners()).slice(3);
      const governorBravoDelegate = await GovernorBravoDelegate.deploy();
      await expect(
        GovernorBravoDelegator.deploy(
          addresses[0],
          addresses[1],
          addresses[2],
          await governorBravoDelegate,
          5760,
          40320,
          BigInt("10") * 10n ** 18n
        )
      ).to.be.revertedWith(
        "GovernorBravo::initialize: invalid proposal threshold"
      );

      await expect(
        GovernorBravoDelegator.deploy(
          addresses[0],
          addresses[1],
          addresses[2],
          governorBravoDelegate,
          5760,
          40320,
          BigInt("100001") * 10n ** 18n
        )
      ).to.be.revertedWith(
        "GovernorBravo::initialize: invalid proposal threshold"
      );
    });

    it("Error: reinitialize", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);
      const addresses = (await ethers.getSigners()).slice(3);

      await expect(
        governorBravo.initialize(
          addresses[0],
          addresses[1],
          5760,
          100,
          BigInt("1000") * 10n ** 18n
        )
      ).to.be.revertedWith(
        "GovernorBravo::initialize: can only initialize once"
      );
    });

    it("Error: invalid comp", async function () {
      const GovernorBravoDelegator = await ethers.getContractFactory(
        "GovernorBravoDelegator"
      );
      const GovernorBravoDelegate = await ethers.getContractFactory(
        "GovernorBravoDelegate"
      );
      const addresses = (await ethers.getSigners()).slice(3);
      const governorBravoDelegate = await GovernorBravoDelegate.deploy();
      await expect(
        GovernorBravoDelegator.deploy(
          addresses[0],
          ethers.zeroPadBytes("0x", 20),
          addresses[2],
          governorBravoDelegate,
          5760,
          40320,
          BigInt("1000") * 10n ** 18n
        )
      ).to.be.revertedWith("GovernorBravo::initialize: invalid comp address");
    });

    it("Error: invalid timelock", async function () {
      const GovernorBravoDelegator = await ethers.getContractFactory(
        "GovernorBravoDelegator"
      );
      const GovernorBravoDelegate = await ethers.getContractFactory(
        "GovernorBravoDelegate"
      );
      const addresses = (await ethers.getSigners()).slice(3);
      const governorBravoDelegate = await GovernorBravoDelegate.deploy();
      await expect(
        GovernorBravoDelegator.deploy(
          ethers.zeroPadBytes("0x", 20),
          addresses[0],
          addresses[2],
          governorBravoDelegate,
          5760,
          40320,
          BigInt("1000") * 10n ** 18n
        )
      ).to.be.revertedWith(
        "GovernorBravo::initialize: invalid timelock address"
      );
    });
  });

  describe("Initiate", function () {
    it("Initiate Twice", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);
      await expect(governorBravo._initiate(governorBravo)).to.be.revertedWith(
        "GovernorBravo::_initiate: can only initiate once"
      );
    });

    it("Admin only", async function () {
      const [owner, otherAccount] = await ethers.getSigners();
      const { governorAlpha, timelock, comp } = await setupGovernorAlpha();

      const GovernorBravoDelegator = await ethers.getContractFactory(
        "GovernorBravoDelegator"
      );
      const GovernorBravoDelegate = await ethers.getContractFactory(
        "GovernorBravoDelegate"
      );

      const governorBravoDelegate = await GovernorBravoDelegate.deploy();
      let governorBravo: GovernorBravoDelegate =
        (await GovernorBravoDelegator.deploy(
          timelock,
          comp,
          owner,
          governorBravoDelegate,
          5760,
          100,
          1000n * 10n ** 18n
        )) as unknown as GovernorBravoDelegate;
      await comp.delegate(owner);
      // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
      const txData = (
        await timelock.setPendingAdmin.populateTransaction(governorBravo)
      ).data!;
      await propose(
        governorAlpha,
        [timelock],
        [0n],
        [txData],
        "Transfer admin for bravo"
      );
      await governorAlpha.castVote(await governorAlpha.votingDelay(), true);
      await mine(await governorAlpha.votingPeriod());
      await governorAlpha.queue(1);
      await time.increase(await timelock.MINIMUM_DELAY());
      await governorAlpha.execute(1);
      governorBravo = GovernorBravoDelegate.attach(
        await governorBravo.getAddress()
      ) as GovernorBravoDelegate;
      await expect(
        governorBravo.connect(otherAccount)._initiate(governorAlpha)
      ).to.be.revertedWith("GovernorBravo::_initiate: admin only");
    });
  });

  describe("Propose", function () {
    it("Happy Path", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);

      let proposalId = await propose(governorBravo);

      await governorBravo.cancel(proposalId);

      proposalId = await propose(governorBravo);
    });

    it("Error: arity Mismatch", async function () {
      const { governorBravo, owner } = await loadFixture(deployFixtures);

      await expect(
        propose(
          governorBravo,
          [governorBravo, governorBravo],
          [0],
          [
            // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
            (
              await governorBravo._setPendingAdmin.populateTransaction(owner)
            ).data!,
          ],
          "Steal governance"
        )
      ).to.be.revertedWith(
        "GovernorBravo::proposeInternal: proposal function information arity mismatch"
      );
    });

    it("Error: below proposal threshold", async function () {
      const { governorBravo, otherAccount } = await loadFixture(deployFixtures);

      await expect(
        propose(governorBravo.connect(otherAccount))
      ).to.be.revertedWith(
        "GovernorBravo::proposeInternal: proposer votes below proposal threshold"
      );
    });

    it("Error: active proposal", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);

      await propose(governorBravo);

      await expect(propose(governorBravo)).to.be.revertedWith(
        "GovernorBravo::proposeInternal: one live proposal per proposer, found an already active proposal"
      );
    });

    it("Error: pending proposal", async function () {
      const { governorBravo, owner } = await loadFixture(deployFixtures);

      // Need to stay in the pending state
      await governorBravo.propose(
        [governorBravo],
        [0],
        [""],
        [
          // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
          (
            await governorBravo._setPendingAdmin.populateTransaction(owner)
          ).data!,
        ],
        "Steal governance"
      );

      await expect(propose(governorBravo)).to.be.revertedWith(
        "GovernorBravo::proposeInternal: one live proposal per proposer, found an already pending proposal"
      );
    });

    it("Error: at least one action", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);

      await expect(
        propose(governorBravo, [], [], [], "Empty")
      ).to.be.revertedWith(
        "GovernorBravo::proposeInternal: must provide actions"
      );
    });

    it("Error: max operations", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);
      await expect(
        propose(
          governorBravo,
          Array(11).fill(governorBravo),
          Array(11).fill("0"),
          Array(11).fill("0x"),
          "11 actions"
        )
      ).to.be.revertedWith("GovernorBravo::proposeInternal: too many actions");
    });

    it("Error: bravo not active", async function () {
      const { timelock, comp } = await setupGovernorAlpha();
      const owner = (await ethers.getSigners())[0];

      const GovernorBravoDelegator = await ethers.getContractFactory(
        "GovernorBravoDelegator"
      );
      const GovernorBravoDelegate = await ethers.getContractFactory(
        "GovernorBravoDelegate"
      );
      const governorBravoDelegate = await GovernorBravoDelegate.deploy();
      let governorBravo = (await GovernorBravoDelegator.deploy(
        timelock,
        comp,
        owner,
        governorBravoDelegate,
        5760,
        100,
        BigInt("1000") * 10n ** 18n
      )) as unknown as GovernorBravoDelegate;
      governorBravo = GovernorBravoDelegate.attach(
        governorBravo
      ) as GovernorBravoDelegate;

      await expect(
        propose(governorBravo, [owner], [1], ["0x"], "Desc")
      ).to.be.revertedWith(
        "GovernorBravo::proposeInternal: Governor Bravo not active"
      );
    });

    describe("By Sig", function () {
      it("Happy Path", async function () {
        const { governorBravo, owner, otherAccount } = await loadFixture(
          deployFixtures
        );
        const domain = await getTypedDomain(
          governorBravo,
          (
            await ethers.provider.getNetwork()
          ).chainId
        );

        const payload = {
          targets: [await governorBravo.getAddress()],
          values: [0],
          signatures: [""],
          calldatas: ["0x1234"],
          description: "My proposal",
          proposalId: 2,
        };

        const sig = await owner.signTypedData(
          domain,
          getProposeTypes(),
          payload
        );

        const r = "0x" + sig.substring(2, 66);
        const s = "0x" + sig.substring(66, 130);
        const v = "0x" + sig.substring(130, 132);

        const currentBlock = BigInt((await time.latestBlock()) + 1);
        const votingDelay = await governorBravo.votingDelay();
        const startBlock = currentBlock + votingDelay;
        const endBlock =
          currentBlock + votingDelay + (await governorBravo.votingPeriod());
        await expect(
          governorBravo
            .connect(otherAccount)
            .proposeBySig(
              payload.targets,
              payload.values,
              payload.signatures,
              payload.calldatas,
              payload.description,
              payload.proposalId,
              v,
              r,
              s
            )
        )
          .to.emit(governorBravo, "ProposalCreated")
          .withArgs(
            2,
            owner.address,
            payload.targets,
            payload.values,
            payload.signatures,
            payload.calldatas,
            startBlock,
            endBlock,
            payload.description
          );
      });

      it("Error: invalid sig", async function () {
        const { governorBravo, owner, otherAccount } = await loadFixture(
          deployFixtures
        );
        const domain = await getTypedDomain(
          governorBravo,
          (
            await ethers.provider.getNetwork()
          ).chainId
        );

        const payload = {
          targets: [await governorBravo.getAddress()],
          values: [0],
          signatures: [""],
          calldatas: ["0x1234"],
          description: "My proposal",
          proposalId: 2,
        };

        const sig = await owner.signTypedData(
          domain,
          getProposeTypes(),
          payload
        );

        const r = "0x" + sig.substring(2, 66);
        const s = "0x" + sig.substring(66, 130);
        const v = "0x00";

        const currentBlock = BigInt((await time.latestBlock()) + 1);
        const votingDelay = await governorBravo.votingDelay();
        currentBlock + votingDelay + (await governorBravo.votingPeriod());
        await expect(
          governorBravo
            .connect(otherAccount)
            .proposeBySig(
              payload.targets,
              payload.values,
              payload.signatures,
              payload.calldatas,
              payload.description,
              payload.proposalId,
              v,
              r,
              s
            )
        ).to.be.revertedWith("GovernorBravo::proposeBySig: invalid signature");
      });

      it("Error: invalid proposal id", async function () {
        const { governorBravo, owner, otherAccount } = await loadFixture(
          deployFixtures
        );
        const domain = await getTypedDomain(
          governorBravo,
          (
            await ethers.provider.getNetwork()
          ).chainId
        );

        const payload = {
          targets: [await governorBravo.getAddress()],
          values: [0],
          signatures: [""],
          calldatas: ["0x1234"],
          description: "My proposal",
          proposalId: 3,
        };

        const sig = await owner.signTypedData(
          domain,
          getProposeTypes(),
          payload
        );

        const r = "0x" + sig.substring(2, 66);
        const s = "0x" + sig.substring(66, 130);
        const v = "0x" + sig.substring(130, 132);

        await expect(
          governorBravo
            .connect(otherAccount)
            .proposeBySig(
              payload.targets,
              payload.values,
              payload.signatures,
              payload.calldatas,
              payload.description,
              payload.proposalId,
              v,
              r,
              s
            )
        ).to.be.revertedWith(
          "GovernorBravo::proposeBySig: invalid proposal id"
        );
      });
    });

    describe("Whitelist", function () {
      it("Happy Path", async function () {
        const { governorBravo, owner, otherAccount } = await loadFixture(
          deployFixtures
        );

        await governorBravo._setWhitelistAccountExpiration(
          otherAccount,
          (await time.latest()) + 1000
        );

        await propose(
          governorBravo.connect(otherAccount),
          [governorBravo],
          [0],
          [
            // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
            (
              await governorBravo._setPendingAdmin.populateTransaction(owner)
            ).data!,
          ],
          "Steal governance"
        );
      });
    });
  });

  describe("Queue", function () {
    it("Happy Path", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);
      const proposalId = await proposeAndPass(
        governorBravo,
        [governorBravo],
        [1],
        ["0x"],
        "Will queue"
      );

      await governorBravo.queue(proposalId);
    });

    it("Error: identical actions", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);
      const proposalId = await proposeAndPass(
        governorBravo,
        [governorBravo, governorBravo],
        [1, 1],
        ["0x", "0x"],
        "Will queue"
      );

      await expect(governorBravo.queue(proposalId)).to.be.revertedWith(
        "GovernorBravo::queueOrRevertInternal: identical proposal action already queued at eta"
      );
    });

    it("Error: proposal not passed", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);
      const proposalId = await propose(
        governorBravo,
        [governorBravo],
        [1],
        ["0x"],
        "Not passed"
      );

      await expect(governorBravo.queue(proposalId)).to.be.revertedWith(
        "GovernorBravo::queue: proposal can only be queued if it is succeeded"
      );
    });
  });

  describe("Execute", function () {
    it("Happy Path", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);
      await proposeAndExecute(governorBravo);
    });

    it("Error: not queued", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);
      const proposalId = await propose(governorBravo);

      await expect(governorBravo.execute(proposalId)).to.be.revertedWith(
        "GovernorBravo::execute: proposal can only be executed if it is queued"
      );
    });
  });

  describe("Cancel", function () {
    it("Happy Path: proposer cancel", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);
      const proposalId = await proposeAndPass(governorBravo);

      await governorBravo.cancel(proposalId);
    });

    it("Happy Path: below threshold", async function () {
      const { governorBravo, comp, otherAccount } = await loadFixture(
        deployFixtures
      );
      const proposalId = await proposeAndPass(governorBravo);

      await comp.delegate(otherAccount);
      await governorBravo.connect(otherAccount).cancel(proposalId);
    });

    it("Error: above threshold", async function () {
      const { governorBravo, otherAccount } = await loadFixture(deployFixtures);
      const proposalId = await proposeAndPass(governorBravo);

      await expect(
        governorBravo.connect(otherAccount).cancel(proposalId)
      ).to.be.revertedWith("GovernorBravo::cancel: proposer above threshold");
    });

    it("Error: cancel executed proposal", async function () {
      const { governorBravo, owner } = await loadFixture(deployFixtures);
      const tx = { to: await governorBravo.timelock(), value: 1000 };
      await owner.sendTransaction(tx);
      const proposalId = await proposeAndExecute(
        governorBravo,
        [owner],
        [1],
        ["0x"],
        "Will be executed"
      );

      await expect(governorBravo.cancel(proposalId)).to.be.revertedWith(
        "GovernorBravo::cancel: cannot cancel executed proposal"
      );
    });

    describe("Whitelisted", function () {
      it("Happy Path", async function () {
        const { governorBravo, owner, otherAccount } = await loadFixture(
          deployFixtures
        );

        await governorBravo._setWhitelistAccountExpiration(
          otherAccount,
          (await time.latest()) + 1000
        );
        const proposalId = await propose(governorBravo.connect(otherAccount));

        await governorBravo._setWhitelistGuardian(owner);
        await governorBravo.cancel(proposalId);
      });

      it("Error: whitelisted proposer", async function () {
        const { governorBravo, otherAccount } = await loadFixture(
          deployFixtures
        );

        await governorBravo._setWhitelistAccountExpiration(
          otherAccount,
          (await time.latest()) + 1000
        );
        const proposalId = await propose(governorBravo.connect(otherAccount));

        await expect(governorBravo.cancel(proposalId)).to.be.revertedWith(
          "GovernorBravo::cancel: whitelisted proposer"
        );
      });

      it("Error: whitelisted proposer above threshold", async function () {
        const { governorBravo, owner, otherAccount, comp } = await loadFixture(
          deployFixtures
        );

        await governorBravo._setWhitelistAccountExpiration(
          otherAccount,
          (await time.latest()) + 1000
        );
        const proposalId = await propose(governorBravo.connect(otherAccount));
        await comp.transfer(
          otherAccount,
          BigInt("100000") * BigInt("10") ** BigInt("18")
        );
        await comp.connect(otherAccount).delegate(otherAccount);

        await governorBravo._setWhitelistGuardian(owner);
        await expect(governorBravo.cancel(proposalId)).to.be.revertedWith(
          "GovernorBravo::cancel: whitelisted proposer"
        );
      });
    });
  });

  describe("Vote", function () {
    it("With Reason", async function () {
      const { governorBravo, owner } = await loadFixture(deployFixtures);
      const proposalId = await propose(governorBravo);

      await expect(
        governorBravo.castVoteWithReason(proposalId, 0, "We need more info")
      )
        .to.emit(governorBravo, "VoteCast")
        .withArgs(
          owner.address,
          proposalId,
          0,
          BigInt("10000000000000000000000000"),
          "We need more info"
        );
    });

    it("Error: double vote", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);
      const proposalId = await propose(governorBravo);

      await governorBravo.castVote(proposalId, 2);
      expect((await governorBravo.proposals(proposalId)).abstainVotes).to.equal(
        "10000000000000000000000000"
      );
      await expect(governorBravo.castVote(proposalId, 1)).to.be.revertedWith(
        "GovernorBravo::castVoteInternal: voter already voted"
      );
    });

    it("Error: voting closed", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);
      const proposalId = await propose(governorBravo);

      await mine(await governorBravo.votingPeriod());
      await expect(governorBravo.castVote(proposalId, 1)).to.be.revertedWith(
        "GovernorBravo::castVoteInternal: voting is closed"
      );
    });

    it("Error: invalid vote type", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);
      const proposalId = await propose(governorBravo);
      await expect(governorBravo.castVote(proposalId, 3)).to.be.revertedWith(
        "GovernorBravo::castVoteInternal: invalid vote type"
      );
    });

    describe("By Sig", function () {
      it("Happy Path", async function () {
        const { governorBravo, owner } = await loadFixture(deployFixtures);
        const domain = await getTypedDomain(
          governorBravo,
          (
            await ethers.provider.getNetwork()
          ).chainId
        );

        const proposalId = await propose(governorBravo);

        const sig = await owner.signTypedData(domain, getVoteTypes(), {
          proposalId,
          support: 1,
        });

        const r = "0x" + sig.substring(2, 66);
        const s = "0x" + sig.substring(66, 130);
        const v = "0x" + sig.substring(130, 132);
        await expect(governorBravo.castVoteBySig(proposalId, 1, v, r, s))
          .to.emit(governorBravo, "VoteCast")
          .withArgs(
            owner.address,
            proposalId,
            1,
            BigInt("10000000000000000000000000"),
            ""
          );
      });

      it("Error: invalid sig", async function () {
        const { governorBravo, owner } = await loadFixture(deployFixtures);
        const domain = await getTypedDomain(
          governorBravo,
          (
            await ethers.provider.getNetwork()
          ).chainId
        );

        const proposalId = await propose(governorBravo);

        const sig = await owner.signTypedData(domain, getVoteTypes(), {
          proposalId,
          support: 1,
        });

        const r = "0x" + sig.substring(2, 66);
        const s = "0x" + sig.substring(66, 130);
        const v = "0x00";
        await expect(
          governorBravo.castVoteBySig(proposalId, 1, v, r, s)
        ).to.be.revertedWith("GovernorBravo::castVoteBySig: invalid signature");
      });

      it("Happy Path with reason", async function () {
        const { governorBravo, owner, otherAccount } = await loadFixture(
          deployFixtures
        );
        const domain = await getTypedDomain(
          governorBravo,
          (
            await ethers.provider.getNetwork()
          ).chainId
        );

        const proposalId = await propose(governorBravo);

        const sig = await owner.signTypedData(
          domain,
          getVoteWithReasonTypes(),
          {
            proposalId,
            support: 1,
            reason: "Great Idea!",
          }
        );

        const r = "0x" + sig.substring(2, 66);
        const s = "0x" + sig.substring(66, 130);
        const v = "0x" + sig.substring(130, 132);
        await expect(
          governorBravo
            .connect(otherAccount)
            .castVoteWithReasonBySig(proposalId, 1, "Great Idea!", v, r, s)
        )
          .to.emit(governorBravo, "VoteCast")
          .withArgs(
            owner.address,
            proposalId,
            1,
            BigInt("10000000000000000000000000"),
            "Great Idea!"
          );
      });

      it("Error: invalid signature with reason", async function () {
        const { governorBravo, owner } = await loadFixture(deployFixtures);
        const domain = await getTypedDomain(
          governorBravo,
          (
            await ethers.provider.getNetwork()
          ).chainId
        );

        const proposalId = await propose(governorBravo);

        const sig = await owner.signTypedData(
          domain,
          getVoteWithReasonTypes(),
          {
            proposalId,
            support: 1,
            reason: "Great Idea!",
          }
        );

        const r = "0x" + sig.substring(2, 66);
        const s = "0x" + sig.substring(66, 130);
        const v = "0x00";
        await expect(
          governorBravo.castVoteWithReasonBySig(
            proposalId,
            1,
            "Great Idea!",
            v,
            r,
            s
          )
        ).to.be.rejectedWith(
          "GovernorBravo::castVoteWithReasonBySig: invalid signature"
        );
      });
    });
  });

  it("Get Actions", async function () {
    const { governorBravo } = await loadFixture(deployFixtures);
    const proposalId = await propose(
      governorBravo,
      [governorBravo],
      [0],
      [ethers.AbiCoder.defaultAbiCoder().encode(["string"], ["encoded value"])],
      "My proposal"
    );

    expect(await governorBravo.getActions(proposalId)).to.deep.equal([
      [await governorBravo.getAddress()],
      [0],
      [""],
      [ethers.AbiCoder.defaultAbiCoder().encode(["string"], ["encoded value"])],
    ]);
  });

  it("Get Receipt", async function () {
    const { governorBravo, owner } = await loadFixture(deployFixtures);
    const proposalId = await propose(governorBravo);

    await governorBravo.castVote(proposalId, 2);
    expect(await governorBravo.getReceipt(proposalId, owner)).to.deep.equal([
      true,
      2,
      BigInt("10000000000000000000000000"),
    ]);
  });

  describe("State", async function () {
    it("Canceled", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);
      const proposalId = await propose(governorBravo);

      await governorBravo.cancel(proposalId);

      expect(await governorBravo.state(proposalId)).to.equal(
        ProposalState.Canceled
      );
    });

    it("Pending", async function () {
      const { governorBravo, owner } = await loadFixture(deployFixtures);
      await governorBravo.propose([owner], [0], [""], ["0x"], "Test Proposal");

      expect(await governorBravo.state(2)).to.equal(ProposalState.Pending);
    });

    it("Active", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);
      const proposalId = await propose(governorBravo);

      expect(await governorBravo.state(proposalId)).to.equal(
        ProposalState.Active
      );
    });

    it("Defeated: quorum", async function () {
      const { governorBravo, comp, otherAccount } = await loadFixture(
        deployFixtures
      );
      await comp.transfer(otherAccount, BigInt("100000"));
      await comp.connect(otherAccount).delegate(otherAccount);

      const proposalId = await propose(governorBravo);
      await governorBravo.connect(otherAccount).castVote(proposalId, 1);
      await mine(await governorBravo.votingPeriod());

      expect(await governorBravo.state(proposalId)).to.equal(
        ProposalState.Defeated
      );
    });

    it("Defeated: against", async function () {
      const { governorBravo, comp, otherAccount } = await loadFixture(
        deployFixtures
      );
      await comp.transfer(
        otherAccount,
        BigInt("400000") * BigInt("10") ** BigInt("18") // quorum
      );
      await comp.connect(otherAccount).delegate(otherAccount);

      const proposalId = await propose(governorBravo);
      await governorBravo.connect(otherAccount).castVote(proposalId, 1);
      await governorBravo.castVote(proposalId, 0);
      await mine(await governorBravo.votingPeriod());

      expect(await governorBravo.state(proposalId)).to.equal(
        ProposalState.Defeated
      );
    });

    it("Error: invalid state", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);
      await expect(governorBravo.state(1)).to.be.revertedWith(
        "GovernorBravo::state: invalid proposal id"
      );
    });

    it("Succeeded", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);
      const proposalId = await proposeAndPass(governorBravo);

      expect(await governorBravo.state(proposalId)).to.equal(
        ProposalState.Succeeded
      );
    });

    it("Executed", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);
      const proposalId = await proposeAndExecute(governorBravo);
      expect(await governorBravo.state(proposalId)).to.equal(
        ProposalState.Executed
      );
    });

    it("Expired", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);
      const proposalId = await proposeAndQueue(governorBravo);

      const timelockAddress = await governorBravo.timelock();
      const timelock = await ethers.getContractAt("Timelock", timelockAddress);

      await time.increase(
        (await timelock.GRACE_PERIOD()) + (await timelock.delay())
      );

      expect(await governorBravo.state(proposalId)).to.equal(
        ProposalState.Expired
      );
    });

    it("Queued", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);
      const proposalId = await proposeAndQueue(governorBravo);

      expect(await governorBravo.state(proposalId)).to.equal(
        ProposalState.Queued
      );
    });
  });

  describe("Admin Functions", function () {
    describe("Set Voting Delay", function () {
      it("Admin only", async function () {
        const { governorBravo, otherAccount } = await loadFixture(
          deployFixtures
        );
        await expect(
          governorBravo.connect(otherAccount)._setVotingDelay(2)
        ).to.be.revertedWith("GovernorBravo::_setVotingDelay: admin only");
      });

      it("Invalid voting delay", async function () {
        const { governorBravo } = await loadFixture(deployFixtures);
        await expect(governorBravo._setVotingDelay(0)).to.be.revertedWith(
          "GovernorBravo::_setVotingDelay: invalid voting delay"
        );
        await expect(governorBravo._setVotingDelay(40321)).to.be.revertedWith(
          "GovernorBravo::_setVotingDelay: invalid voting delay"
        );
      });

      it("Happy Path", async function () {
        const { governorBravo } = await loadFixture(deployFixtures);
        await expect(governorBravo._setVotingDelay(2))
          .to.emit(governorBravo, "VotingDelaySet")
          .withArgs(100, 2);
      });
    });

    describe("Set Voting Period", function () {
      it("Admin only", async function () {
        const { governorBravo, otherAccount } = await loadFixture(
          deployFixtures
        );
        await expect(
          governorBravo.connect(otherAccount)._setVotingPeriod(2)
        ).to.be.revertedWith("GovernorBravo::_setVotingPeriod: admin only");
      });

      it("Invalid voting period", async function () {
        const { governorBravo } = await loadFixture(deployFixtures);
        await expect(governorBravo._setVotingPeriod(5759)).to.be.revertedWith(
          "GovernorBravo::_setVotingPeriod: invalid voting period"
        );
        await expect(governorBravo._setVotingPeriod(80641)).to.be.revertedWith(
          "GovernorBravo::_setVotingPeriod: invalid voting period"
        );
      });

      it("Happy Path", async function () {
        const { governorBravo } = await loadFixture(deployFixtures);
        await expect(governorBravo._setVotingPeriod(5761))
          .to.emit(governorBravo, "VotingPeriodSet")
          .withArgs(5760, 5761);
      });
    });

    describe("Set Proposal Threshold", function () {
      it("Admin only", async function () {
        const { governorBravo, otherAccount } = await loadFixture(
          deployFixtures
        );
        await expect(
          governorBravo.connect(otherAccount)._setProposalThreshold(2)
        ).to.be.revertedWith(
          "GovernorBravo::_setProposalThreshold: admin only"
        );
      });

      it("Invalid proposal threshold", async function () {
        const { governorBravo } = await loadFixture(deployFixtures);
        await expect(
          governorBravo._setProposalThreshold(1000)
        ).to.be.revertedWith(
          "GovernorBravo::_setProposalThreshold: invalid proposal threshold"
        );
        await expect(
          governorBravo._setProposalThreshold(100001n * 10n ** 18n)
        ).to.be.revertedWith(
          "GovernorBravo::_setProposalThreshold: invalid proposal threshold"
        );
      });

      it("Happy Path", async function () {
        const { governorBravo } = await loadFixture(deployFixtures);
        await expect(governorBravo._setProposalThreshold(1001n * 10n ** 18n))
          .to.emit(governorBravo, "ProposalThresholdSet")
          .withArgs(1000n * 10n ** 18n, 1001n * 10n ** 18n);
      });
    });

    describe("Set Pending Admin", function () {
      it("Admin only", async function () {
        const { governorBravo, otherAccount } = await loadFixture(
          deployFixtures
        );
        await expect(
          governorBravo.connect(otherAccount)._setPendingAdmin(otherAccount)
        ).to.be.revertedWith("GovernorBravo:_setPendingAdmin: admin only");
      });

      it("Happy Path", async function () {
        const { governorBravo, otherAccount } = await loadFixture(
          deployFixtures
        );
        await expect(governorBravo._setPendingAdmin(otherAccount))
          .to.emit(governorBravo, "NewPendingAdmin")
          .withArgs(ethers.ZeroAddress, otherAccount.address);
      });
    });

    describe("Accept Pending Admin", function () {
      it("Invalid Address (zero address)", async function () {
        const { governorBravo } = await loadFixture(deployFixtures);
        await impersonateAccount(ethers.ZeroAddress);
        await expect(governorBravo._acceptAdmin()).to.be.revertedWith(
          "GovernorBravo:_acceptAdmin: pending admin only"
        );
      });

      it("Pending Admin Only", async function () {
        const { governorBravo, otherAccount } = await loadFixture(
          deployFixtures
        );
        await expect(
          governorBravo.connect(otherAccount)._acceptAdmin()
        ).to.be.revertedWith("GovernorBravo:_acceptAdmin: pending admin only");
      });

      it("Happy Path", async function () {
        const { governorBravo, otherAccount, owner } = await loadFixture(
          deployFixtures
        );
        await governorBravo._setPendingAdmin(otherAccount);
        await expect(governorBravo.connect(otherAccount)._acceptAdmin())
          .to.emit(governorBravo, "NewAdmin")
          .withArgs(owner.address, otherAccount.address);
      });
    });
  });

  describe("Whitelist", function () {
    it("Set whitelist guardian: admin only", async function () {
      const { governorBravo, otherAccount } = await loadFixture(deployFixtures);
      await expect(
        governorBravo.connect(otherAccount)._setWhitelistGuardian(otherAccount)
      ).to.be.revertedWith("GovernorBravo::_setWhitelistGuardian: admin only");
    });

    it("Set whitelist guardian: happy path", async function () {
      const { governorBravo, otherAccount } = await loadFixture(deployFixtures);
      await expect(governorBravo._setWhitelistGuardian(otherAccount))
        .to.emit(governorBravo, "WhitelistGuardianSet")
        .withArgs(ethers.ZeroAddress, otherAccount.address);
    });

    it("Set whitelist account expiration: admin only", async function () {
      const { governorBravo, otherAccount } = await loadFixture(deployFixtures);
      await expect(
        governorBravo
          .connect(otherAccount)
          ._setWhitelistAccountExpiration(otherAccount, 0)
      ).to.be.revertedWith(
        "GovernorBravo::_setWhitelistAccountExpiration: admin only"
      );
    });

    it("Set whitelist account expiration: happy path", async function () {
      const { governorBravo, otherAccount } = await loadFixture(deployFixtures);
      await governorBravo._setWhitelistGuardian(otherAccount);
      await expect(
        governorBravo
          .connect(otherAccount)
          ._setWhitelistAccountExpiration(otherAccount, 0)
      )
        .to.emit(governorBravo, "WhitelistAccountExpirationSet")
        .withArgs(otherAccount.address, 0);
    });
  });

  describe("Set Implementation", function () {
    it("Admin only", async function () {
      const { governorBravo, otherAccount } = await loadFixture(deployFixtures);
      const GovernorBravoDelegator = await ethers.getContractFactory(
        "GovernorBravoDelegator"
      );
      const governorBravoDelegator = GovernorBravoDelegator.attach(
        await governorBravo.getAddress()
      ) as GovernorBravoDelegator;
      await expect(
        governorBravoDelegator
          .connect(otherAccount)
          ._setImplementation(otherAccount)
      ).to.be.revertedWith(
        "GovernorBravoDelegator::_setImplementation: admin only"
      );
    });

    it("Invalid address", async function () {
      const { governorBravo } = await loadFixture(deployFixtures);
      const GovernorBravoDelegator = await ethers.getContractFactory(
        "GovernorBravoDelegator"
      );
      const governorBravoDelegator = GovernorBravoDelegator.attach(
        await governorBravo.getAddress()
      ) as GovernorBravoDelegator;
      await expect(
        governorBravoDelegator._setImplementation(ethers.ZeroAddress)
      ).to.be.revertedWith(
        "GovernorBravoDelegator::_setImplementation: invalid implementation address"
      );
    });

    it("Happy path", async function () {
      const { governorBravo, owner } = await loadFixture(deployFixtures);
      const GovernorBravoDelegator = await ethers.getContractFactory(
        "GovernorBravoDelegator"
      );
      const governorBravoDelegator = GovernorBravoDelegator.attach(
        await governorBravo.getAddress()
      ) as GovernorBravoDelegator;
      const oldImpl = await governorBravoDelegator.implementation();
      await expect(governorBravoDelegator._setImplementation(owner.address))
        .to.emit(governorBravo, "NewImplementation")
        .withArgs(oldImpl, owner.address);
    });
  });
});
