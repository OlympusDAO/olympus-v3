/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import type {
  BaseContract,
  BigNumber,
  BigNumberish,
  BytesLike,
  CallOverrides,
  ContractTransaction,
  Overrides,
  PopulatedTransaction,
  Signer,
  utils,
} from "ethers";
import type { FunctionFragment, Result } from "@ethersproject/abi";
import type { Listener, Provider } from "@ethersproject/providers";
import type {
  TypedEventFilter,
  TypedEvent,
  TypedListener,
  OnEvent,
  PromiseOrValue,
} from "../common";

export interface MockStakingInterface extends utils.Interface {
  functions: {
    "GDAO()": FunctionFragment;
    "distributor()": FunctionFragment;
    "epoch()": FunctionFragment;
    "rebase()": FunctionFragment;
    "sGDAO()": FunctionFragment;
    "setDistributor(address)": FunctionFragment;
    "stake(address,uint256,bool,bool)": FunctionFragment;
    "unstake(address,uint256,bool,bool)": FunctionFragment;
    "xGDAO()": FunctionFragment;
  };

  getFunction(
    nameOrSignatureOrTopic:
      | "GDAO"
      | "distributor"
      | "epoch"
      | "rebase"
      | "sGDAO"
      | "setDistributor"
      | "stake"
      | "unstake"
      | "xGDAO"
  ): FunctionFragment;

  encodeFunctionData(functionFragment: "GDAO", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "distributor",
    values?: undefined
  ): string;
  encodeFunctionData(functionFragment: "epoch", values?: undefined): string;
  encodeFunctionData(functionFragment: "rebase", values?: undefined): string;
  encodeFunctionData(functionFragment: "sGDAO", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "setDistributor",
    values: [PromiseOrValue<string>]
  ): string;
  encodeFunctionData(
    functionFragment: "stake",
    values: [
      PromiseOrValue<string>,
      PromiseOrValue<BigNumberish>,
      PromiseOrValue<boolean>,
      PromiseOrValue<boolean>
    ]
  ): string;
  encodeFunctionData(
    functionFragment: "unstake",
    values: [
      PromiseOrValue<string>,
      PromiseOrValue<BigNumberish>,
      PromiseOrValue<boolean>,
      PromiseOrValue<boolean>
    ]
  ): string;
  encodeFunctionData(functionFragment: "xGDAO", values?: undefined): string;

  decodeFunctionResult(functionFragment: "GDAO", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "distributor",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "epoch", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "rebase", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "sGDAO", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "setDistributor",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "stake", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "unstake", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "xGDAO", data: BytesLike): Result;

  events: {};
}

export interface MockStaking extends BaseContract {
  connect(signerOrProvider: Signer | Provider | string): this;
  attach(addressOrName: string): this;
  deployed(): Promise<this>;

  interface: MockStakingInterface;

  queryFilter<TEvent extends TypedEvent>(
    event: TypedEventFilter<TEvent>,
    fromBlockOrBlockhash?: string | number | undefined,
    toBlock?: string | number | undefined
  ): Promise<Array<TEvent>>;

  listeners<TEvent extends TypedEvent>(
    eventFilter?: TypedEventFilter<TEvent>
  ): Array<TypedListener<TEvent>>;
  listeners(eventName?: string): Array<Listener>;
  removeAllListeners<TEvent extends TypedEvent>(
    eventFilter: TypedEventFilter<TEvent>
  ): this;
  removeAllListeners(eventName?: string): this;
  off: OnEvent<this>;
  on: OnEvent<this>;
  once: OnEvent<this>;
  removeListener: OnEvent<this>;

  functions: {
    GDAO(overrides?: CallOverrides): Promise<[string]>;

    distributor(overrides?: CallOverrides): Promise<[string]>;

    epoch(
      overrides?: CallOverrides
    ): Promise<
      [BigNumber, BigNumber, BigNumber, BigNumber] & {
        length: BigNumber;
        number: BigNumber;
        end: BigNumber;
        distribute: BigNumber;
      }
    >;

    rebase(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    sGDAO(overrides?: CallOverrides): Promise<[string]>;

    setDistributor(
      distributor_: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    stake(
      to_: PromiseOrValue<string>,
      amount_: PromiseOrValue<BigNumberish>,
      rebasing_: PromiseOrValue<boolean>,
      claim_: PromiseOrValue<boolean>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    unstake(
      to_: PromiseOrValue<string>,
      amount_: PromiseOrValue<BigNumberish>,
      trigger_: PromiseOrValue<boolean>,
      rebasing_: PromiseOrValue<boolean>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    xGDAO(overrides?: CallOverrides): Promise<[string]>;
  };

  GDAO(overrides?: CallOverrides): Promise<string>;

  distributor(overrides?: CallOverrides): Promise<string>;

  epoch(
    overrides?: CallOverrides
  ): Promise<
    [BigNumber, BigNumber, BigNumber, BigNumber] & {
      length: BigNumber;
      number: BigNumber;
      end: BigNumber;
      distribute: BigNumber;
    }
  >;

  rebase(
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  sGDAO(overrides?: CallOverrides): Promise<string>;

  setDistributor(
    distributor_: PromiseOrValue<string>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  stake(
    to_: PromiseOrValue<string>,
    amount_: PromiseOrValue<BigNumberish>,
    rebasing_: PromiseOrValue<boolean>,
    claim_: PromiseOrValue<boolean>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  unstake(
    to_: PromiseOrValue<string>,
    amount_: PromiseOrValue<BigNumberish>,
    trigger_: PromiseOrValue<boolean>,
    rebasing_: PromiseOrValue<boolean>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  xGDAO(overrides?: CallOverrides): Promise<string>;

  callStatic: {
    GDAO(overrides?: CallOverrides): Promise<string>;

    distributor(overrides?: CallOverrides): Promise<string>;

    epoch(
      overrides?: CallOverrides
    ): Promise<
      [BigNumber, BigNumber, BigNumber, BigNumber] & {
        length: BigNumber;
        number: BigNumber;
        end: BigNumber;
        distribute: BigNumber;
      }
    >;

    rebase(overrides?: CallOverrides): Promise<BigNumber>;

    sGDAO(overrides?: CallOverrides): Promise<string>;

    setDistributor(
      distributor_: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<void>;

    stake(
      to_: PromiseOrValue<string>,
      amount_: PromiseOrValue<BigNumberish>,
      rebasing_: PromiseOrValue<boolean>,
      claim_: PromiseOrValue<boolean>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    unstake(
      to_: PromiseOrValue<string>,
      amount_: PromiseOrValue<BigNumberish>,
      trigger_: PromiseOrValue<boolean>,
      rebasing_: PromiseOrValue<boolean>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    xGDAO(overrides?: CallOverrides): Promise<string>;
  };

  filters: {};

  estimateGas: {
    GDAO(overrides?: CallOverrides): Promise<BigNumber>;

    distributor(overrides?: CallOverrides): Promise<BigNumber>;

    epoch(overrides?: CallOverrides): Promise<BigNumber>;

    rebase(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    sGDAO(overrides?: CallOverrides): Promise<BigNumber>;

    setDistributor(
      distributor_: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    stake(
      to_: PromiseOrValue<string>,
      amount_: PromiseOrValue<BigNumberish>,
      rebasing_: PromiseOrValue<boolean>,
      claim_: PromiseOrValue<boolean>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    unstake(
      to_: PromiseOrValue<string>,
      amount_: PromiseOrValue<BigNumberish>,
      trigger_: PromiseOrValue<boolean>,
      rebasing_: PromiseOrValue<boolean>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    xGDAO(overrides?: CallOverrides): Promise<BigNumber>;
  };

  populateTransaction: {
    GDAO(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    distributor(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    epoch(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    rebase(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    sGDAO(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    setDistributor(
      distributor_: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    stake(
      to_: PromiseOrValue<string>,
      amount_: PromiseOrValue<BigNumberish>,
      rebasing_: PromiseOrValue<boolean>,
      claim_: PromiseOrValue<boolean>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    unstake(
      to_: PromiseOrValue<string>,
      amount_: PromiseOrValue<BigNumberish>,
      trigger_: PromiseOrValue<boolean>,
      rebasing_: PromiseOrValue<boolean>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    xGDAO(overrides?: CallOverrides): Promise<PopulatedTransaction>;
  };
}