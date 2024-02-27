import { expect } from "chai";
import { ethers } from "hardhat";
import { getTypedDomainComp, getDelegationTypes } from "./governanceHelpers";
import {
  loadFixture,
  time,
  mine,
} from "@nomicfoundation/hardhat-network-helpers";

describe("Comp", function () {
  async function deployFixtures() {
    const [owner, otherAccount] = await ethers.getSigners();
    const Comp = await ethers.getContractFactory("Comp");
    const comp = await Comp.deploy(await owner.getAddress());

    return { owner, otherAccount, comp };
  }

  describe("Approvals", function () {
    it("Approve", async function () {
      const { owner, otherAccount, comp } = await loadFixture(deployFixtures);

      await expect(comp.approve(otherAccount, 100))
        .to.emit(comp, "Approval")
        .withArgs(owner.address, otherAccount.address, 100);
      expect(await comp.allowance(owner, otherAccount)).to.eq(100);
    });

    it("Over uint96", async function () {
      const { otherAccount, comp } = await loadFixture(deployFixtures);

      await expect(
        comp.approve(otherAccount, ethers.MaxUint256 - 1n)
      ).to.be.revertedWith("Comp::approve: amount exceeds 96 bits");
    });

    it("Infinite approval", async function () {
      const { otherAccount, comp, owner } = await loadFixture(deployFixtures);

      await expect(comp.approve(otherAccount, ethers.MaxUint256))
        .to.emit(comp, "Approval")
        .withArgs(owner.address, otherAccount.address, 2n ** 96n - 1n);

      await expect(
        comp.connect(otherAccount).transferFrom(owner, otherAccount, 100)
      ).to.not.emit(comp, "Approval");

      expect(await comp.allowance(owner, otherAccount)).to.equal(
        2n ** 96n - 1n
      );
    });
  });

  describe("Transfer", function () {
    it("happy path", async function () {
      const { owner, otherAccount, comp } = await loadFixture(deployFixtures);
      await expect(comp.transfer(otherAccount, 100))
        .to.emit(comp, "Transfer")
        .withArgs(owner.address, otherAccount.address, 100);
    });

    it("Error: over uint96", async function () {
      const { otherAccount, comp } = await loadFixture(deployFixtures);
      await expect(
        comp.transfer(otherAccount, ethers.MaxUint256 - 1n)
      ).to.be.revertedWith("Comp::transfer: amount exceeds 96 bits");
    });
  });

  describe("Transfer From", function () {
    it("happy path", async function () {
      const { owner, otherAccount, comp } = await loadFixture(deployFixtures);
      await comp.approve(otherAccount, 100);
      await expect(
        comp.connect(otherAccount).transferFrom(owner, otherAccount, 100)
      )
        .to.emit(comp, "Transfer")
        .withArgs(owner.address, otherAccount.address, 100)
        .to.emit(comp, "Approval");
      expect(await comp.balanceOf(otherAccount)).to.eq(100);
      expect(await comp.allowance(owner, otherAccount)).to.eq(0);
    });

    it("Error: over uint96", async function () {
      const { owner, otherAccount, comp } = await loadFixture(deployFixtures);
      await expect(
        comp
          .connect(otherAccount)
          .transferFrom(owner, otherAccount, ethers.MaxUint256 - 1n)
      ).to.be.revertedWith("Comp::approve: amount exceeds 96 bits");
    });
  });

  describe("Transfer Tokens", function () {
    it("Error: from zero address", async function () {
      const { otherAccount, comp } = await loadFixture(deployFixtures);
      await expect(
        comp.transferFrom(ethers.ZeroAddress, otherAccount, 0)
      ).to.be.revertedWith(
        "Comp::_transferTokens: cannot transfer from the zero address"
      );
    });

    it("Error: to zero address", async function () {
      const { comp } = await loadFixture(deployFixtures);
      await expect(comp.transfer(ethers.ZeroAddress, 100)).to.be.revertedWith(
        "Comp::_transferTokens: cannot transfer to the zero address"
      );
    });

    it("Error: exceeds balance", async function () {
      const { comp, owner, otherAccount } = await loadFixture(deployFixtures);
      await expect(
        comp.connect(otherAccount).transfer(owner, 100)
      ).to.be.revertedWith(
        "Comp::_transferTokens: transfer amount exceeds balance"
      );
    });
  });

  describe("Delegate", function () {
    it("happy path", async function () {
      const { comp, owner } = await loadFixture(deployFixtures);
      await expect(comp.delegate(owner))
        .to.emit(comp, "DelegateChanged")
        .withArgs(owner.address, ethers.ZeroAddress, owner.address);
      expect(await comp.delegates(owner)).to.eq(owner.address);
      expect(await comp.getCurrentVotes(owner)).to.eq(
        BigInt("10000000") * 10n ** 18n
      );
    });

    describe("By sig", function () {
      it("happy path", async function () {
        const { comp, owner } = await loadFixture(deployFixtures);
        const domain = await getTypedDomainComp(
          comp,
          (
            await ethers.provider.getNetwork()
          ).chainId
        );
        const delegationTypes = await getDelegationTypes();

        const sig = await owner.signTypedData(domain, delegationTypes, {
          delegatee: owner.address,
          nonce: 0,
          expiry: (await time.latest()) + 100,
        });
        const r = "0x" + sig.substring(2, 66);
        const s = "0x" + sig.substring(66, 130);
        const v = "0x" + sig.substring(130, 132);

        await expect(
          comp.delegateBySig(
            owner.address,
            0,
            (await time.latest()) + 100,
            v,
            r,
            s
          )
        )
          .to.emit(comp, "DelegateChanged")
          .withArgs(owner.address, ethers.ZeroAddress, owner.address);
      });

      it("Error: invalid nonce", async function () {
        const { comp, owner, otherAccount } = await loadFixture(deployFixtures);
        const domain = await getTypedDomainComp(
          comp,
          (
            await ethers.provider.getNetwork()
          ).chainId
        );
        const delegationTypes = await getDelegationTypes();

        let sig = await owner.signTypedData(domain, delegationTypes, {
          delegatee: owner.address,
          nonce: 0,
          expiry: (await time.latest()) + 100,
        });
        let r = "0x" + sig.substring(2, 66);
        let s = "0x" + sig.substring(66, 130);
        let v = "0x" + sig.substring(130, 132);

        await comp.delegateBySig(
          owner.address,
          0,
          (await time.latest()) + 100,
          v,
          r,
          s
        );

        sig = await owner.signTypedData(domain, delegationTypes, {
          delegatee: otherAccount.address,
          nonce: 2,
          expiry: (await time.latest()) + 100,
        });
        r = "0x" + sig.substring(2, 66);
        s = "0x" + sig.substring(66, 130);
        v = "0x" + sig.substring(130, 132);

        await expect(
          comp.delegateBySig(otherAccount.address, 2, 0, v, r, s)
        ).to.be.revertedWith("Comp::delegateBySig: invalid nonce");
      });

      it("Error: invalid signature", async function () {
        const { comp, owner } = await loadFixture(deployFixtures);
        const domain = await getTypedDomainComp(
          comp,
          (
            await ethers.provider.getNetwork()
          ).chainId
        );
        const delegationTypes = await getDelegationTypes();

        const sig = await owner.signTypedData(domain, delegationTypes, {
          delegatee: owner.address,
          nonce: 0,
          expiry: (await time.latest()) + 100,
        });
        const r = "0x" + sig.substring(2, 66);
        const s = "0x" + sig.substring(66, 130);
        const v = "0x00";

        await expect(
          comp.delegateBySig(
            owner.address,
            0,
            (await time.latest()) + 100,
            v,
            r,
            s
          )
        ).to.revertedWith("Comp::delegateBySig: invalid signature");
      });

      it("Error: expired", async function () {
        const { comp, owner } = await loadFixture(deployFixtures);
        const domain = await getTypedDomainComp(
          comp,
          (
            await ethers.provider.getNetwork()
          ).chainId
        );
        const delegationTypes = await getDelegationTypes();

        const sig = await owner.signTypedData(domain, delegationTypes, {
          delegatee: owner.address,
          nonce: 0,
          expiry: (await time.latest()) - 100,
        });
        const r = "0x" + sig.substring(2, 66);
        const s = "0x" + sig.substring(66, 130);
        const v = "0x" + sig.substring(130, 132);

        await expect(
          comp.delegateBySig(
            owner.address,
            0,
            (await time.latest()) - 100,
            v,
            r,
            s
          )
        ).to.be.revertedWith("Comp::delegateBySig: signature expired");
      });
    });
  });

  describe("Get current votes", function () {
    it("Happy path", async function () {
      const { comp, owner } = await loadFixture(deployFixtures);
      expect(await comp.getCurrentVotes(owner)).to.eq(0);

      await comp.delegate(owner);
      expect(await comp.getCurrentVotes(owner)).to.eq(10000000n * 10n ** 18n);
    });
  });

  describe("Get prior votes", function () {
    it("happy path", async function () {
      const { comp, otherAccount } = await loadFixture(deployFixtures);
      await comp.transfer(otherAccount, 100);
      const blockNumber1 = await ethers.provider.getBlockNumber();
      await comp.connect(otherAccount).delegate(otherAccount);
      await mine(100);
      await comp.transfer(otherAccount, 100);
      const blockNumber2 = await ethers.provider.getBlockNumber();
      await mine();
      await comp.transfer(otherAccount, 200);
      const blockNumber3 = await ethers.provider.getBlockNumber();
      await mine();

      expect(await comp.getPriorVotes(otherAccount, blockNumber1 - 1)).to.eq(0);
      expect(await comp.getPriorVotes(otherAccount, blockNumber1)).to.eq(0);
      expect(await comp.getPriorVotes(otherAccount, blockNumber2)).to.eq(200);
      expect(await comp.getPriorVotes(otherAccount, blockNumber3 - 1)).to.eq(
        200
      );
      expect(await comp.getPriorVotes(otherAccount, blockNumber3)).to.eq(400);
    });

    it("Happy path: new account", async function () {
      const { comp, otherAccount } = await loadFixture(deployFixtures);
      const blockNumber1 = await ethers.provider.getBlockNumber();
      await mine();
      expect(await comp.getPriorVotes(otherAccount, blockNumber1)).to.eq(0);
    });

    it("Error: block number must be past", async function () {
      const { comp, owner } = await loadFixture(deployFixtures);
      const blockNumber = await ethers.provider.getBlockNumber();

      await expect(comp.getPriorVotes(owner, blockNumber)).to.be.revertedWith(
        "Comp::getPriorVotes: not yet determined"
      );
    });
  });

  describe("Move delegates", function () {
    it("Move from owner to other account", async function () {
      const { comp, owner, otherAccount } = await loadFixture(deployFixtures);
      await comp.delegate(owner);
      await comp.connect(otherAccount).delegate(otherAccount);

      await expect(comp.transfer(otherAccount, 100))
        .to.emit(comp, "DelegateVotesChanged")
        .withArgs(otherAccount.address, 0, 100)
        .to.emit(comp, "DelegateVotesChanged")
        .withArgs(
          owner.address,
          10000000n * 10n ** 18n,
          10000000n * 10n ** 18n - 100n
        );
    });

    it("Delegate to zero address", async function () {
      const { comp, owner } = await loadFixture(deployFixtures);
      await comp.delegate(owner);
      await comp.delegate(ethers.ZeroAddress);
      expect(await comp.getCurrentVotes(owner)).to.eq(0);
    });

    it("Move delegates twice in one block", async function () {
      const { comp, owner, otherAccount } = await loadFixture(deployFixtures);
      const Multicall = await ethers.getContractFactory("Multicall");
      const multicall = await Multicall.deploy();

      await comp.transfer(otherAccount, 100);

      const domain = await getTypedDomainComp(
        comp,
        (
          await ethers.provider.getNetwork()
        ).chainId
      );
      const delegationTypes = await getDelegationTypes();

      const expiry = (await time.latest()) + 100;
      const sig = await owner.signTypedData(domain, delegationTypes, {
        delegatee: otherAccount.address,
        nonce: 0,
        expiry,
      });
      const r = "0x" + sig.substring(2, 66);
      const s = "0x" + sig.substring(66, 130);
      const v = "0x" + sig.substring(130, 132);

      const sig2 = await otherAccount.signTypedData(domain, delegationTypes, {
        delegatee: otherAccount.address,
        nonce: 0,
        expiry,
      });
      const r2 = "0x" + sig2.substring(2, 66);
      const s2 = "0x" + sig2.substring(66, 130);
      const v2 = "0x" + sig2.substring(130, 132);

      const calldata1 = (
        await comp.delegateBySig.populateTransaction(
          otherAccount.address,
          0,
          expiry,
          v,
          r,
          s
        )
      ).data;

      const calldata2 = (
        await comp.delegateBySig.populateTransaction(
          otherAccount.address,
          0,
          expiry,
          v2,
          r2,
          s2
        )
      ).data;

      await multicall.aggregate([
        { target: await comp.getAddress(), callData: calldata1 },
        { target: await comp.getAddress(), callData: calldata2 },
      ]);
    });
  });
});
