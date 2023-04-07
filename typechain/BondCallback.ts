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
} from "./common";

export type PermissionsStruct = {
  keycode: PromiseOrValue<BytesLike>;
  funcSelector: PromiseOrValue<BytesLike>;
};

export type PermissionsStructOutput = [string, string] & {
  keycode: string;
  funcSelector: string;
};

export interface BondCallbackInterface extends utils.Interface {
  functions: {
    "MINTR()": FunctionFragment;
    "ROLES()": FunctionFragment;
    "TRSRY()": FunctionFragment;
    "aggregator()": FunctionFragment;
    "amountsForMarket(uint256)": FunctionFragment;
    "approvedMarkets(address,uint256)": FunctionFragment;
    "batchToTreasury(address[])": FunctionFragment;
    "blacklist(address,uint256)": FunctionFragment;
    "callback(uint256,uint256,uint256)": FunctionFragment;
    "changeKernel(address)": FunctionFragment;
    "configureDependencies()": FunctionFragment;
    "gdao()": FunctionFragment;
    "isActive()": FunctionFragment;
    "kernel()": FunctionFragment;
    "operator()": FunctionFragment;
    "priorBalances(address)": FunctionFragment;
    "requestPermissions()": FunctionFragment;
    "setOperator(address)": FunctionFragment;
    "whitelist(address,uint256)": FunctionFragment;
  };

  getFunction(
    nameOrSignatureOrTopic:
      | "MINTR"
      | "ROLES"
      | "TRSRY"
      | "aggregator"
      | "amountsForMarket"
      | "approvedMarkets"
      | "batchToTreasury"
      | "blacklist"
      | "callback"
      | "changeKernel"
      | "configureDependencies"
      | "gdao"
      | "isActive"
      | "kernel"
      | "operator"
      | "priorBalances"
      | "requestPermissions"
      | "setOperator"
      | "whitelist"
  ): FunctionFragment;

  encodeFunctionData(functionFragment: "MINTR", values?: undefined): string;
  encodeFunctionData(functionFragment: "ROLES", values?: undefined): string;
  encodeFunctionData(functionFragment: "TRSRY", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "aggregator",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "amountsForMarket",
    values: [PromiseOrValue<BigNumberish>]
  ): string;
  encodeFunctionData(
    functionFragment: "approvedMarkets",
    values: [PromiseOrValue<string>, PromiseOrValue<BigNumberish>]
  ): string;
  encodeFunctionData(
    functionFragment: "batchToTreasury",
    values: [PromiseOrValue<string>[]]
  ): string;
  encodeFunctionData(
    functionFragment: "blacklist",
    values: [PromiseOrValue<string>, PromiseOrValue<BigNumberish>]
  ): string;
  encodeFunctionData(
    functionFragment: "callback",
    values: [
      PromiseOrValue<BigNumberish>,
      PromiseOrValue<BigNumberish>,
      PromiseOrValue<BigNumberish>
    ]
  ): string;
  encodeFunctionData(
    functionFragment: "changeKernel",
    values: [PromiseOrValue<string>]
  ): string;
  encodeFunctionData(
    functionFragment: "configureDependencies",
    values?: undefined
  ): string;
  encodeFunctionData(functionFragment: "gdao", values?: undefined): string;
  encodeFunctionData(functionFragment: "isActive", values?: undefined): string;
  encodeFunctionData(functionFragment: "kernel", values?: undefined): string;
  encodeFunctionData(functionFragment: "operator", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "priorBalances",
    values: [PromiseOrValue<string>]
  ): string;
  encodeFunctionData(
    functionFragment: "requestPermissions",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "setOperator",
    values: [PromiseOrValue<string>]
  ): string;
  encodeFunctionData(
    functionFragment: "whitelist",
    values: [PromiseOrValue<string>, PromiseOrValue<BigNumberish>]
  ): string;

  decodeFunctionResult(functionFragment: "MINTR", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "ROLES", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "TRSRY", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "aggregator", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "amountsForMarket",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "approvedMarkets",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "batchToTreasury",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "blacklist", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "callback", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "changeKernel",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "configureDependencies",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "gdao", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "isActive", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "kernel", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "operator", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "priorBalances",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "requestPermissions",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "setOperator",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "whitelist", data: BytesLike): Result;

  events: {};
}

export interface BondCallback extends BaseContract {
  connect(signerOrProvider: Signer | Provider | string): this;
  attach(addressOrName: string): this;
  deployed(): Promise<this>;

  interface: BondCallbackInterface;

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
    MINTR(overrides?: CallOverrides): Promise<[string]>;

    ROLES(overrides?: CallOverrides): Promise<[string]>;

    TRSRY(overrides?: CallOverrides): Promise<[string]>;

    aggregator(overrides?: CallOverrides): Promise<[string]>;

    amountsForMarket(
      id_: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<[BigNumber, BigNumber] & { in_: BigNumber; out_: BigNumber }>;

    approvedMarkets(
      arg0: PromiseOrValue<string>,
      arg1: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<[boolean]>;

    batchToTreasury(
      tokens_: PromiseOrValue<string>[],
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    blacklist(
      teller_: PromiseOrValue<string>,
      id_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    callback(
      id_: PromiseOrValue<BigNumberish>,
      inputAmount_: PromiseOrValue<BigNumberish>,
      outputAmount_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    changeKernel(
      newKernel_: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    configureDependencies(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    gdao(overrides?: CallOverrides): Promise<[string]>;

    isActive(overrides?: CallOverrides): Promise<[boolean]>;

    kernel(overrides?: CallOverrides): Promise<[string]>;

    operator(overrides?: CallOverrides): Promise<[string]>;

    priorBalances(
      arg0: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<[BigNumber]>;

    requestPermissions(
      overrides?: CallOverrides
    ): Promise<
      [PermissionsStructOutput[]] & { requests: PermissionsStructOutput[] }
    >;

    setOperator(
      operator_: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    whitelist(
      teller_: PromiseOrValue<string>,
      id_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;
  };

  MINTR(overrides?: CallOverrides): Promise<string>;

  ROLES(overrides?: CallOverrides): Promise<string>;

  TRSRY(overrides?: CallOverrides): Promise<string>;

  aggregator(overrides?: CallOverrides): Promise<string>;

  amountsForMarket(
    id_: PromiseOrValue<BigNumberish>,
    overrides?: CallOverrides
  ): Promise<[BigNumber, BigNumber] & { in_: BigNumber; out_: BigNumber }>;

  approvedMarkets(
    arg0: PromiseOrValue<string>,
    arg1: PromiseOrValue<BigNumberish>,
    overrides?: CallOverrides
  ): Promise<boolean>;

  batchToTreasury(
    tokens_: PromiseOrValue<string>[],
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  blacklist(
    teller_: PromiseOrValue<string>,
    id_: PromiseOrValue<BigNumberish>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  callback(
    id_: PromiseOrValue<BigNumberish>,
    inputAmount_: PromiseOrValue<BigNumberish>,
    outputAmount_: PromiseOrValue<BigNumberish>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  changeKernel(
    newKernel_: PromiseOrValue<string>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  configureDependencies(
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  gdao(overrides?: CallOverrides): Promise<string>;

  isActive(overrides?: CallOverrides): Promise<boolean>;

  kernel(overrides?: CallOverrides): Promise<string>;

  operator(overrides?: CallOverrides): Promise<string>;

  priorBalances(
    arg0: PromiseOrValue<string>,
    overrides?: CallOverrides
  ): Promise<BigNumber>;

  requestPermissions(
    overrides?: CallOverrides
  ): Promise<PermissionsStructOutput[]>;

  setOperator(
    operator_: PromiseOrValue<string>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  whitelist(
    teller_: PromiseOrValue<string>,
    id_: PromiseOrValue<BigNumberish>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  callStatic: {
    MINTR(overrides?: CallOverrides): Promise<string>;

    ROLES(overrides?: CallOverrides): Promise<string>;

    TRSRY(overrides?: CallOverrides): Promise<string>;

    aggregator(overrides?: CallOverrides): Promise<string>;

    amountsForMarket(
      id_: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<[BigNumber, BigNumber] & { in_: BigNumber; out_: BigNumber }>;

    approvedMarkets(
      arg0: PromiseOrValue<string>,
      arg1: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<boolean>;

    batchToTreasury(
      tokens_: PromiseOrValue<string>[],
      overrides?: CallOverrides
    ): Promise<void>;

    blacklist(
      teller_: PromiseOrValue<string>,
      id_: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<void>;

    callback(
      id_: PromiseOrValue<BigNumberish>,
      inputAmount_: PromiseOrValue<BigNumberish>,
      outputAmount_: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<void>;

    changeKernel(
      newKernel_: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<void>;

    configureDependencies(overrides?: CallOverrides): Promise<string[]>;

    gdao(overrides?: CallOverrides): Promise<string>;

    isActive(overrides?: CallOverrides): Promise<boolean>;

    kernel(overrides?: CallOverrides): Promise<string>;

    operator(overrides?: CallOverrides): Promise<string>;

    priorBalances(
      arg0: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    requestPermissions(
      overrides?: CallOverrides
    ): Promise<PermissionsStructOutput[]>;

    setOperator(
      operator_: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<void>;

    whitelist(
      teller_: PromiseOrValue<string>,
      id_: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<void>;
  };

  filters: {};

  estimateGas: {
    MINTR(overrides?: CallOverrides): Promise<BigNumber>;

    ROLES(overrides?: CallOverrides): Promise<BigNumber>;

    TRSRY(overrides?: CallOverrides): Promise<BigNumber>;

    aggregator(overrides?: CallOverrides): Promise<BigNumber>;

    amountsForMarket(
      id_: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    approvedMarkets(
      arg0: PromiseOrValue<string>,
      arg1: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    batchToTreasury(
      tokens_: PromiseOrValue<string>[],
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    blacklist(
      teller_: PromiseOrValue<string>,
      id_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    callback(
      id_: PromiseOrValue<BigNumberish>,
      inputAmount_: PromiseOrValue<BigNumberish>,
      outputAmount_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    changeKernel(
      newKernel_: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    configureDependencies(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    gdao(overrides?: CallOverrides): Promise<BigNumber>;

    isActive(overrides?: CallOverrides): Promise<BigNumber>;

    kernel(overrides?: CallOverrides): Promise<BigNumber>;

    operator(overrides?: CallOverrides): Promise<BigNumber>;

    priorBalances(
      arg0: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    requestPermissions(overrides?: CallOverrides): Promise<BigNumber>;

    setOperator(
      operator_: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    whitelist(
      teller_: PromiseOrValue<string>,
      id_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;
  };

  populateTransaction: {
    MINTR(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    ROLES(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    TRSRY(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    aggregator(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    amountsForMarket(
      id_: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    approvedMarkets(
      arg0: PromiseOrValue<string>,
      arg1: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    batchToTreasury(
      tokens_: PromiseOrValue<string>[],
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    blacklist(
      teller_: PromiseOrValue<string>,
      id_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    callback(
      id_: PromiseOrValue<BigNumberish>,
      inputAmount_: PromiseOrValue<BigNumberish>,
      outputAmount_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    changeKernel(
      newKernel_: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    configureDependencies(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    gdao(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    isActive(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    kernel(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    operator(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    priorBalances(
      arg0: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    requestPermissions(
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    setOperator(
      operator_: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    whitelist(
      teller_: PromiseOrValue<string>,
      id_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;
  };
}