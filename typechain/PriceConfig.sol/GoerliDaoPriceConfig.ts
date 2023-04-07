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

export type PermissionsStruct = {
  keycode: PromiseOrValue<BytesLike>;
  funcSelector: PromiseOrValue<BytesLike>;
};

export type PermissionsStructOutput = [string, string] & {
  keycode: string;
  funcSelector: string;
};

export interface GoerliDaoPriceConfigInterface extends utils.Interface {
  functions: {
    "ROLES()": FunctionFragment;
    "changeKernel(address)": FunctionFragment;
    "changeMinimumTargetPrice(uint256)": FunctionFragment;
    "changeMovingAverageDuration(uint48)": FunctionFragment;
    "changeObservationFrequency(uint48)": FunctionFragment;
    "changeUpdateThresholds(uint48,uint48)": FunctionFragment;
    "configureDependencies()": FunctionFragment;
    "initialize(uint256[],uint48)": FunctionFragment;
    "isActive()": FunctionFragment;
    "kernel()": FunctionFragment;
    "requestPermissions()": FunctionFragment;
  };

  getFunction(
    nameOrSignatureOrTopic:
      | "ROLES"
      | "changeKernel"
      | "changeMinimumTargetPrice"
      | "changeMovingAverageDuration"
      | "changeObservationFrequency"
      | "changeUpdateThresholds"
      | "configureDependencies"
      | "initialize"
      | "isActive"
      | "kernel"
      | "requestPermissions"
  ): FunctionFragment;

  encodeFunctionData(functionFragment: "ROLES", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "changeKernel",
    values: [PromiseOrValue<string>]
  ): string;
  encodeFunctionData(
    functionFragment: "changeMinimumTargetPrice",
    values: [PromiseOrValue<BigNumberish>]
  ): string;
  encodeFunctionData(
    functionFragment: "changeMovingAverageDuration",
    values: [PromiseOrValue<BigNumberish>]
  ): string;
  encodeFunctionData(
    functionFragment: "changeObservationFrequency",
    values: [PromiseOrValue<BigNumberish>]
  ): string;
  encodeFunctionData(
    functionFragment: "changeUpdateThresholds",
    values: [PromiseOrValue<BigNumberish>, PromiseOrValue<BigNumberish>]
  ): string;
  encodeFunctionData(
    functionFragment: "configureDependencies",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "initialize",
    values: [PromiseOrValue<BigNumberish>[], PromiseOrValue<BigNumberish>]
  ): string;
  encodeFunctionData(functionFragment: "isActive", values?: undefined): string;
  encodeFunctionData(functionFragment: "kernel", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "requestPermissions",
    values?: undefined
  ): string;

  decodeFunctionResult(functionFragment: "ROLES", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "changeKernel",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "changeMinimumTargetPrice",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "changeMovingAverageDuration",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "changeObservationFrequency",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "changeUpdateThresholds",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "configureDependencies",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "initialize", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "isActive", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "kernel", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "requestPermissions",
    data: BytesLike
  ): Result;

  events: {};
}

export interface GoerliDaoPriceConfig extends BaseContract {
  connect(signerOrProvider: Signer | Provider | string): this;
  attach(addressOrName: string): this;
  deployed(): Promise<this>;

  interface: GoerliDaoPriceConfigInterface;

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
    ROLES(overrides?: CallOverrides): Promise<[string]>;

    changeKernel(
      newKernel_: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    changeMinimumTargetPrice(
      minimumTargetPrice_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    changeMovingAverageDuration(
      movingAverageDuration_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    changeObservationFrequency(
      observationFrequency_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    changeUpdateThresholds(
      ohmEthUpdateThreshold_: PromiseOrValue<BigNumberish>,
      reserveEthUpdateThreshold_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    configureDependencies(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    initialize(
      startObservations_: PromiseOrValue<BigNumberish>[],
      lastObservationTime_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    isActive(overrides?: CallOverrides): Promise<[boolean]>;

    kernel(overrides?: CallOverrides): Promise<[string]>;

    requestPermissions(
      overrides?: CallOverrides
    ): Promise<
      [PermissionsStructOutput[]] & { permissions: PermissionsStructOutput[] }
    >;
  };

  ROLES(overrides?: CallOverrides): Promise<string>;

  changeKernel(
    newKernel_: PromiseOrValue<string>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  changeMinimumTargetPrice(
    minimumTargetPrice_: PromiseOrValue<BigNumberish>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  changeMovingAverageDuration(
    movingAverageDuration_: PromiseOrValue<BigNumberish>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  changeObservationFrequency(
    observationFrequency_: PromiseOrValue<BigNumberish>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  changeUpdateThresholds(
    ohmEthUpdateThreshold_: PromiseOrValue<BigNumberish>,
    reserveEthUpdateThreshold_: PromiseOrValue<BigNumberish>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  configureDependencies(
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  initialize(
    startObservations_: PromiseOrValue<BigNumberish>[],
    lastObservationTime_: PromiseOrValue<BigNumberish>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  isActive(overrides?: CallOverrides): Promise<boolean>;

  kernel(overrides?: CallOverrides): Promise<string>;

  requestPermissions(
    overrides?: CallOverrides
  ): Promise<PermissionsStructOutput[]>;

  callStatic: {
    ROLES(overrides?: CallOverrides): Promise<string>;

    changeKernel(
      newKernel_: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<void>;

    changeMinimumTargetPrice(
      minimumTargetPrice_: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<void>;

    changeMovingAverageDuration(
      movingAverageDuration_: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<void>;

    changeObservationFrequency(
      observationFrequency_: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<void>;

    changeUpdateThresholds(
      ohmEthUpdateThreshold_: PromiseOrValue<BigNumberish>,
      reserveEthUpdateThreshold_: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<void>;

    configureDependencies(overrides?: CallOverrides): Promise<string[]>;

    initialize(
      startObservations_: PromiseOrValue<BigNumberish>[],
      lastObservationTime_: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<void>;

    isActive(overrides?: CallOverrides): Promise<boolean>;

    kernel(overrides?: CallOverrides): Promise<string>;

    requestPermissions(
      overrides?: CallOverrides
    ): Promise<PermissionsStructOutput[]>;
  };

  filters: {};

  estimateGas: {
    ROLES(overrides?: CallOverrides): Promise<BigNumber>;

    changeKernel(
      newKernel_: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    changeMinimumTargetPrice(
      minimumTargetPrice_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    changeMovingAverageDuration(
      movingAverageDuration_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    changeObservationFrequency(
      observationFrequency_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    changeUpdateThresholds(
      ohmEthUpdateThreshold_: PromiseOrValue<BigNumberish>,
      reserveEthUpdateThreshold_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    configureDependencies(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    initialize(
      startObservations_: PromiseOrValue<BigNumberish>[],
      lastObservationTime_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    isActive(overrides?: CallOverrides): Promise<BigNumber>;

    kernel(overrides?: CallOverrides): Promise<BigNumber>;

    requestPermissions(overrides?: CallOverrides): Promise<BigNumber>;
  };

  populateTransaction: {
    ROLES(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    changeKernel(
      newKernel_: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    changeMinimumTargetPrice(
      minimumTargetPrice_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    changeMovingAverageDuration(
      movingAverageDuration_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    changeObservationFrequency(
      observationFrequency_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    changeUpdateThresholds(
      ohmEthUpdateThreshold_: PromiseOrValue<BigNumberish>,
      reserveEthUpdateThreshold_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    configureDependencies(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    initialize(
      startObservations_: PromiseOrValue<BigNumberish>[],
      lastObservationTime_: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    isActive(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    kernel(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    requestPermissions(
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;
  };
}