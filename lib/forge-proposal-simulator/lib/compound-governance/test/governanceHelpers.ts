import { time, mine } from "@nomicfoundation/hardhat-network-helpers";
import { BigNumberish, EventLog, AddressLike, Addressable } from "ethers";
import { ethers } from "hardhat";
import {
  Comp,
  GovernorAlpha,
  GovernorBravoDelegate,
  Timelock,
} from "../typechain-types";

/**
 * Propose and fast forward to voting period of given governor
 * @returns Proposal id
 */
export async function propose(
  governor: GovernorAlpha | GovernorBravoDelegate,
  targets: AddressLike[] = [ethers.ZeroAddress],
  values: BigNumberish[] = [0],
  callDatas: string[] = ["0x"],
  description = "Test Proposal"
): Promise<bigint> {
  const tx = await governor.propose(
    targets,
    values,
    Array(values.length).fill(""),
    callDatas,
    description
  );

  await mine((await governor.votingDelay()) + 1n);

  // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
  return ((await tx.wait())!.logs[0] as EventLog).args[0];
}

export async function proposeAndPass(
  governor: GovernorBravoDelegate,
  targets: AddressLike[] = [ethers.ZeroAddress],
  values: BigNumberish[] = [0],
  callDatas: string[] = ["0x"],
  description = "Test Proposal"
): Promise<bigint> {
  const proposalId = await propose(
    governor,
    targets,
    values,
    callDatas,
    description
  );
  await governor.castVote(proposalId, 1);

  await mine(await governor.votingPeriod());

  return proposalId;
}

/**
 *
 * @param governor The governor to use (must have a signer with sufficient delegations)
 * @param targets Targets for each proposal action
 * @param values Value for each proposal action
 * @param callDatas Calldata for each proposal action
 * @param description The proposal description
 * @returns Proposal id for the new proposal
 */
export async function proposeAndQueue(
  governor: GovernorBravoDelegate,
  targets: AddressLike[] = [ethers.ZeroAddress],
  values: BigNumberish[] = [0],
  callDatas: string[] = ["0x"],
  description = "Test Proposal"
): Promise<bigint> {
  const proposalId = await proposeAndPass(
    governor,
    targets,
    values,
    callDatas,
    description
  );

  await governor.queue(proposalId);

  return proposalId;
}

/**
 * Propose, pass, queue, and execute a proposal
 * @param governor The governor to use (must have a signer with sufficient delegations)
 * @param targets Targets for each proposal action
 * @param values Value for each proposal action
 * @param callDatas Calldata for each proposal action
 * @param description The proposal description
 * @returns Proposal id for the new proposal
 */
export async function proposeAndExecute(
  governor: GovernorBravoDelegate,
  targets: AddressLike[] = [ethers.ZeroAddress],
  values: BigNumberish[] = [0],
  callDatas: string[] = ["0x"],
  description = "Test Proposal"
): Promise<bigint> {
  const proposalId = await proposeAndQueue(
    governor,
    targets,
    values,
    callDatas,
    description
  );
  await time.increase(
    await ethers.provider.call({
      to: await governor.timelock(),
      data: ethers.id("delay()").substring(0, 10),
    })
  );
  await governor.execute(proposalId);
  return proposalId;
}

export async function setupGovernorAlpha() {
  const [owner] = await ethers.getSigners();

  const Timelock = await ethers.getContractFactory("Timelock");
  const Comp = await ethers.getContractFactory("Comp");
  const GovernorAlpha = await ethers.getContractFactory("GovernorAlpha");

  const timelock = await Timelock.deploy(owner, 172800);
  const comp = await Comp.deploy(owner);
  const governorAlpha: GovernorAlpha = (await GovernorAlpha.deploy(
    timelock,
    comp,
    owner
  )) as unknown as GovernorAlpha;

  const eta =
    BigInt(await time.latest()) + 100n + (await timelock.MINIMUM_DELAY());
  // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
  const txData = (
    await timelock.setPendingAdmin.populateTransaction(governorAlpha)
  ).data!;
  await timelock.queueTransaction(timelock, 0, "", txData, eta);
  await time.increaseTo(eta);
  await timelock.executeTransaction(timelock, 0, "", txData, eta);
  await governorAlpha.__acceptAdmin();

  return { governorAlpha, timelock, comp };
}

export async function setupGovernorBravo(
  timelock: Timelock,
  comp: Comp,
  governorAlpha: GovernorAlpha
) {
  const [owner] = await ethers.getSigners();
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
  await governorBravo._initiate(governorAlpha);

  return { governorBravo };
}

export async function getTypedDomain(address: Addressable, chainId: bigint) {
  return {
    name: "Compound Governor Bravo",
    chainId: chainId.toString(),
    verifyingContract: await address.getAddress(),
  };
}

export function getVoteTypes() {
  return {
    Ballot: [
      { name: "proposalId", type: "uint256" },
      { name: "support", type: "uint8" },
    ],
  };
}
export function getVoteWithReasonTypes() {
  return {
    Ballot: [
      { name: "proposalId", type: "uint256" },
      { name: "support", type: "uint8" },
      { name: "reason", type: "string" },
    ],
  };
}

export async function getTypedDomainComp(
  address: Addressable,
  chainId: bigint
) {
  return {
    name: "Compound",
    chainId: chainId.toString(),
    verifyingContract: await address.getAddress(),
  };
}

export function getDelegationTypes() {
  return {
    Delegation: [
      { name: "delegatee", type: "address" },
      { name: "nonce", type: "uint256" },
      { name: "expiry", type: "uint256" },
    ],
  };
}

export function getProposeTypes() {
  return {
    Proposal: [
      { name: "targets", type: "address[]" },
      { name: "values", type: "uint256[]" },
      { name: "signatures", type: "string[]" },
      { name: "calldatas", type: "bytes[]" },
      { name: "description", type: "string" },
      { name: "proposalId", type: "uint256" },
    ],
  };
}

export enum ProposalState {
  Pending,
  Active,
  Canceled,
  Defeated,
  Succeeded,
  Queued,
  Expired,
  Executed,
}
