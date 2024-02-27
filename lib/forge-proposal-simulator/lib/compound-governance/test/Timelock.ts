import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { Timelock } from "../typechain-types";
import { AddressLike } from "ethers";

describe("Timelock", function () {
  async function deployFixtures() {
    const [owner, otherAccount] = await ethers.getSigners();
    const Timelock = await ethers.getContractFactory("Timelock");
    const timelock = await Timelock.deploy(owner, 2 * 24 * 60 * 60);

    return { owner, otherAccount, timelock };
  }

  async function queueAndExecute(
    timelock: Timelock,
    target: AddressLike,
    value: bigint,
    callDatas: string
  ): Promise<[AddressLike, bigint, string, string, bigint]> {
    const eta =
      BigInt(await time.latest()) + BigInt((await timelock.delay()) + 1n);
    await timelock.queueTransaction(target, value, "", callDatas, eta);
    await time.increaseTo(eta);
    return [target, value, "", callDatas, eta];
  }

  describe("Constructor", async function () {
    it("Delay must be in bounds", async function () {
      const [owner] = await ethers.getSigners();
      const Timelock = await ethers.getContractFactory("Timelock");
      await expect(Timelock.deploy(owner, 0)).to.be.revertedWith(
        "Timelock::constructor: Delay must exceed minimum delay."
      );
      await expect(
        Timelock.deploy(owner, 30 * 24 * 60 * 60 + 1)
      ).to.be.revertedWith(
        "Timelock::setDelay: Delay must not exceed maximum delay."
      );
    });
  });

  describe("Set delay", function () {
    it("Happy path", async function () {
      const { timelock } = await loadFixture(deployFixtures);
      const calldata = (
        await timelock.setDelay.populateTransaction(3 * 24 * 60 * 60 + 1)
      ).data;
      await expect(
        timelock.executeTransaction(
          ...(await queueAndExecute(timelock, timelock, 0n, calldata))
        )
      )
        .to.emit(timelock, "NewDelay")
        .withArgs(3 * 24 * 60 * 60 + 1);
    });

    it("Admin only", async function () {
      const { timelock } = await loadFixture(deployFixtures);
      await expect(timelock.setDelay(3 * 24 * 60 * 60 + 1)).to.be.revertedWith(
        "Timelock::setDelay: Call must come from Timelock."
      );
    });

    it("Must be within bounds", async function () {
      const { timelock } = await loadFixture(deployFixtures);
      let calldata = (await timelock.setDelay.populateTransaction(1)).data;
      await expect(
        timelock.executeTransaction(
          ...(await queueAndExecute(timelock, timelock, 0n, calldata))
        )
      ).to.be.revertedWith(
        "Timelock::executeTransaction: Transaction execution reverted."
      );

      calldata = (
        await timelock.setDelay.populateTransaction(30 * 24 * 60 * 60 + 1)
      ).data;
      await expect(
        timelock.executeTransaction(
          ...(await queueAndExecute(timelock, timelock, 0n, calldata))
        )
      ).to.be.revertedWith(
        "Timelock::executeTransaction: Transaction execution reverted."
      );
    });
  });

  describe("Transfer Admin", function () {
    it("Happy path", async function () {
      const { timelock, otherAccount } = await loadFixture(deployFixtures);
      const calldata = (
        await timelock.setPendingAdmin.populateTransaction(otherAccount)
      ).data;
      await expect(
        timelock.executeTransaction(
          ...(await queueAndExecute(timelock, timelock, 0n, calldata))
        )
      )
        .to.emit(timelock, "NewPendingAdmin")
        .withArgs(otherAccount.address);

      await expect(timelock.connect(otherAccount).acceptAdmin())
        .to.emit(timelock, "NewAdmin")
        .withArgs(otherAccount.address);
    });

    it("Admin only", async function () {
      const { timelock, otherAccount } = await loadFixture(deployFixtures);

      await expect(timelock.setPendingAdmin(otherAccount)).to.be.revertedWith(
        "Timelock::setPendingAdmin: Call must come from Timelock."
      );
      await expect(timelock.acceptAdmin()).to.be.revertedWith(
        "Timelock::acceptAdmin: Call must come from pendingAdmin."
      );
    });
  });

  describe("Cancel", function () {
    it("Admin only", async function () {
      const { timelock, otherAccount } = await loadFixture(deployFixtures);
      await expect(
        timelock
          .connect(otherAccount)
          .cancelTransaction(timelock, 0, "", "0x", 0)
      ).to.be.revertedWith(
        "Timelock::cancelTransaction: Call must come from admin."
      );
    });

    it("Happy path", async function () {
      const { timelock } = await loadFixture(deployFixtures);
      const eta =
        BigInt(await time.latest()) + BigInt((await timelock.delay()) + 1n);
      await timelock.queueTransaction(timelock, 0, "", "0x", eta);
      await expect(
        timelock.cancelTransaction(timelock, 0, "", "0x", eta)
      ).to.emit(timelock, "CancelTransaction");
    });
  });

  describe("Queue", function () {
    it("Admin only", async function () {
      const { timelock, otherAccount } = await loadFixture(deployFixtures);
      await expect(
        timelock
          .connect(otherAccount)
          .queueTransaction(timelock, 0, "", "0x", 0)
      ).to.be.revertedWith(
        "Timelock::queueTransaction: Call must come from admin."
      );
    });

    it("Eta delay must be fulfilled", async function () {
      const { timelock } = await loadFixture(deployFixtures);
      await expect(
        timelock.queueTransaction(timelock, 0, "", "0x", 0)
      ).to.be.revertedWith(
        "Timelock::queueTransaction: Estimated execution block must satisfy delay."
      );
    });

    it("Happy path", async function () {
      const { timelock } = await loadFixture(deployFixtures);
      const eta =
        BigInt(await time.latest()) + BigInt((await timelock.delay()) + 1n);
      await timelock.queueTransaction(timelock, 0, "", "0x", eta);
    });
  });

  describe("Execute", function () {
    it("Happy path: use signature field", async function () {
      const { timelock, otherAccount } = await loadFixture(deployFixtures);
      const calldata = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address"],
        [otherAccount.address]
      );
      const eta =
        BigInt(await time.latest()) + BigInt((await timelock.delay()) + 1n);
      await timelock.queueTransaction(
        timelock,
        0,
        "setPendingAdmin(address)",
        calldata,
        eta
      );
      await time.increaseTo(eta);
      await expect(
        timelock.executeTransaction(
          timelock,
          0,
          "setPendingAdmin(address)",
          calldata,
          eta
        )
      )
        .to.emit(timelock, "NewPendingAdmin")
        .withArgs(otherAccount.address);
    });

    it("Must be queued", async function () {
      const { timelock, otherAccount } = await loadFixture(deployFixtures);
      const calldata = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address"],
        [otherAccount.address]
      );
      const eta =
        BigInt(await time.latest()) + BigInt((await timelock.delay()) + 1n);
      await time.increaseTo(eta);
      await expect(
        timelock.executeTransaction(
          timelock,
          0,
          "setPendingAdmin(address)",
          calldata,
          eta
        )
      ).to.be.revertedWith(
        "Timelock::executeTransaction: Transaction hasn't been queued."
      );
    });

    it("Must be after eta", async function () {
      const { timelock, otherAccount } = await loadFixture(deployFixtures);
      const calldata = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address"],
        [otherAccount.address]
      );
      const eta =
        BigInt(await time.latest()) + BigInt((await timelock.delay()) + 1n);
      await timelock.queueTransaction(
        timelock,
        0,
        "setPendingAdmin(address)",
        calldata,
        eta
      );
      await expect(
        timelock.executeTransaction(
          timelock,
          0,
          "setPendingAdmin(address)",
          calldata,
          eta
        )
      ).to.be.revertedWith(
        "Timelock::executeTransaction: Transaction hasn't surpassed time lock."
      );
    });

    it("Must be before grace period ends", async function () {
      const { timelock } = await loadFixture(deployFixtures);
      const executionParams = await queueAndExecute(
        timelock,
        timelock,
        0n,
        "0x"
      );
      const gracePeriod = await timelock.GRACE_PERIOD();
      await time.increase(gracePeriod + 20n);

      await expect(
        timelock.executeTransaction(...executionParams)
      ).to.be.revertedWith(
        "Timelock::executeTransaction: Transaction is stale."
      );
    });

    it("Admin only", async function () {
      const { timelock, otherAccount } = await loadFixture(deployFixtures);
      await expect(
        timelock
          .connect(otherAccount)
          .executeTransaction(timelock, 0, "", "0x", 0)
      ).to.be.revertedWith(
        "Timelock::executeTransaction: Call must come from admin."
      );
    });
  });
});
