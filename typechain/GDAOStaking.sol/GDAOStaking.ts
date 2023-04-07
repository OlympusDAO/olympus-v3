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
import type {
  FunctionFragment,
  Result,
  EventFragment,
} from "@ethersproject/abi";
import type { Listener, Provider } from "@ethersproject/providers";
import type {
  TypedEventFilter,
  TypedEvent,
  TypedListener,
  OnEvent,
  PromiseOrValue,
} from "../common";

export interface GDAOStakingInterface extends utils.Interface {
  functions: {
    "GDAO()": FunctionFragment;
    "authority()": FunctionFragment;
    "claim(address,bool)": FunctionFragment;
    "distributor()": FunctionFragment;
    "epoch()": FunctionFragment;
    "forfeit()": FunctionFragment;
    "index()": FunctionFragment;
    "rebase()": FunctionFragment;
    "sGDAO()": FunctionFragment;
    "secondsToNextEpoch()": FunctionFragment;
    "setAuthority(address)": FunctionFragment;
    "setDistributor(address)": FunctionFragment;
    "setWarmupLength(uint256)": FunctionFragment;
    "stake(address,uint256,bool,bool)": FunctionFragment;
    "supplyInWarmup()": FunctionFragment;
    "toggleLock()": FunctionFragment;
    "unstake(address,uint256,bool,bool)": FunctionFragment;
    "unwrap(address,uint256)": FunctionFragment;
    "warmupInfo(address)": FunctionFragment;
    "warmupPeriod()": FunctionFragment;
    "wrap(address,uint256)": FunctionFragment;
    "xGDAO()": FunctionFragment;
  };

  getFunction(
    nameOrSignatureOrTopic:
      | "GDAO"
      | "authority"
      | "claim"
      | "distributor"
      | "epoch"
      | "forfeit"
      | "index"
      | "rebase"
      | "sGDAO"
      | "secondsToNextEpoch"
      | "setAuthority"
      | "setDistributor"
      | "setWarmupLength"
      | "stake"
      | "supplyInWarmup"
      | "toggleLock"
      | "unstake"
      | "unwrap"
      | "warmupInfo"
      | "warmupPeriod"
      | "wrap"
      | "xGDAO"
  ): FunctionFragment;

  encodeFunctionData(functionFragment: "GDAO", values?: undefined): string;
  encodeFunctionData(functionFragment: "authority", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "claim",
    values: [PromiseOrValue<string>, PromiseOrValue<boolean>]
  ): string;
  encodeFunctionData(
    functionFragment: "distributor",
    values?: undefined
  ): string;
  encodeFunctionData(functionFragment: "epoch", values?: undefined): string;
  encodeFunctionData(functionFragment: "forfeit", values?: undefined): string;
  encodeFunctionData(functionFragment: "index", values?: undefined): string;
  encodeFunctionData(functionFragment: "rebase", values?: undefined): string;
  encodeFunctionData(functionFragment: "sGDAO", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "secondsToNextEpoch",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "setAuthority",
    values: [PromiseOrValue<string>]
  ): string;
  encodeFunctionData(
    functionFragment: "setDistributor",
    values: [PromiseOrValue<string>]
  ): string;
  encodeFunctionData(
    functionFragment: "setWarmupLength",
    values: [PromiseOrValue<BigNumberish>]
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
    functionFragment: "supplyInWarmup",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "toggleLock",
    values?: undefined
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
  encodeFunctionData(
    functionFragment: "unwrap",
    values: [PromiseOrValue<string>, PromiseOrValue<BigNumberish>]
  ): string;
  encodeFunctionData(
    functionFragment: "warmupInfo",
    values: [PromiseOrValue<string>]
  ): string;
  encodeFunctionData(
    functionFragment: "warmupPeriod",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "wrap",
    values: [PromiseOrValue<string>, PromiseOrValue<BigNumberish>]
  ): string;
  encodeFunctionData(functionFragment: "xGDAO", values?: undefined): string;

  decodeFunctionResult(functionFragment: "GDAO", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "authority", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "claim", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "distributor",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "epoch", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "forfeit", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "index", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "rebase", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "sGDAO", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "secondsToNextEpoch",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "setAuthority",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "setDistributor",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "setWarmupLength",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "stake", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "supplyInWarmup",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "toggleLock", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "unstake", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "unwrap", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "warmupInfo", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "warmupPeriod",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "wrap", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "xGDAO", data: BytesLike): Result;

  events: {
    "AuthorityUpdated(address)": EventFragment;
    "DistributorSet(address)": EventFragment;
    "WarmupSet(uint256)": EventFragment;
  };

  getEvent(nameOrSignatureOrTopic: "AuthorityUpdated"): EventFragment;
  getEvent(nameOrSignatureOrTopic: "DistributorSet"): EventFragment;
  getEvent(nameOrSignatureOrTopic: "WarmupSet"): EventFragment;
}

export interface AuthorityUpdatedEventObject {
  authority: string;
}
export type AuthorityUpdatedEvent = TypedEvent<
  [string],
  AuthorityUpdatedEventObject
>;

export type AuthorityUpdatedEventFilter =
  TypedEventFilter<AuthorityUpdatedEvent>;

export interface DistributorSetEventObject {
  distributor: string;
}
export type DistributorSetEvent = TypedEvent<
  [string],
  DistributorSetEventObject
>;

export type DistributorSetEventFilter = TypedEventFilter<DistributorSetEvent>;

export interface WarmupSetEventObject {
  warmup: BigNumber;
}
export type WarmupSetEvent = TypedEvent<[BigNumber], WarmupSetEventObject>;

export type WarmupSetEventFilter = TypedEventFilter<WarmupSetEvent>;

export interface GDAOStaking extends BaseContract {
  connect(signerOrProvider: Signer | Provider | string): this;
  attach(addressOrName: string): this;
  deployed(): Promise<this>;

  interface: GDAOStakingInterface;

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

    authority(overrides?: CallOverrides): Promise<[string]>;

    claim(
      _to: PromiseOrValue<string>,
      _rebasing: PromiseOrValue<boolean>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

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

    forfeit(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    index(overrides?: CallOverrides): Promise<[BigNumber]>;

    rebase(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    sGDAO(overrides?: CallOverrides): Promise<[string]>;

    secondsToNextEpoch(overrides?: CallOverrides): Promise<[BigNumber]>;

    setAuthority(
      _newAuthority: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    setDistributor(
      _distributor: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    setWarmupLength(
      _warmupPeriod: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    stake(
      _to: PromiseOrValue<string>,
      _amount: PromiseOrValue<BigNumberish>,
      _rebasing: PromiseOrValue<boolean>,
      _claim: PromiseOrValue<boolean>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    supplyInWarmup(overrides?: CallOverrides): Promise<[BigNumber]>;

    toggleLock(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    unstake(
      _to: PromiseOrValue<string>,
      _amount: PromiseOrValue<BigNumberish>,
      _trigger: PromiseOrValue<boolean>,
      _rebasing: PromiseOrValue<boolean>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    unwrap(
      _to: PromiseOrValue<string>,
      _amount: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    warmupInfo(
      arg0: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<
      [BigNumber, BigNumber, BigNumber, boolean] & {
        deposit: BigNumber;
        gons: BigNumber;
        expiry: BigNumber;
        lock: boolean;
      }
    >;

    warmupPeriod(overrides?: CallOverrides): Promise<[BigNumber]>;

    wrap(
      _to: PromiseOrValue<string>,
      _amount: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    xGDAO(overrides?: CallOverrides): Promise<[string]>;
  };

  GDAO(overrides?: CallOverrides): Promise<string>;

  authority(overrides?: CallOverrides): Promise<string>;

  claim(
    _to: PromiseOrValue<string>,
    _rebasing: PromiseOrValue<boolean>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

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

  forfeit(
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  index(overrides?: CallOverrides): Promise<BigNumber>;

  rebase(
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  sGDAO(overrides?: CallOverrides): Promise<string>;

  secondsToNextEpoch(overrides?: CallOverrides): Promise<BigNumber>;

  setAuthority(
    _newAuthority: PromiseOrValue<string>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  setDistributor(
    _distributor: PromiseOrValue<string>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  setWarmupLength(
    _warmupPeriod: PromiseOrValue<BigNumberish>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  stake(
    _to: PromiseOrValue<string>,
    _amount: PromiseOrValue<BigNumberish>,
    _rebasing: PromiseOrValue<boolean>,
    _claim: PromiseOrValue<boolean>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  supplyInWarmup(overrides?: CallOverrides): Promise<BigNumber>;

  toggleLock(
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  unstake(
    _to: PromiseOrValue<string>,
    _amount: PromiseOrValue<BigNumberish>,
    _trigger: PromiseOrValue<boolean>,
    _rebasing: PromiseOrValue<boolean>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  unwrap(
    _to: PromiseOrValue<string>,
    _amount: PromiseOrValue<BigNumberish>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  warmupInfo(
    arg0: PromiseOrValue<string>,
    overrides?: CallOverrides
  ): Promise<
    [BigNumber, BigNumber, BigNumber, boolean] & {
      deposit: BigNumber;
      gons: BigNumber;
      expiry: BigNumber;
      lock: boolean;
    }
  >;

  warmupPeriod(overrides?: CallOverrides): Promise<BigNumber>;

  wrap(
    _to: PromiseOrValue<string>,
    _amount: PromiseOrValue<BigNumberish>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  xGDAO(overrides?: CallOverrides): Promise<string>;

  callStatic: {
    GDAO(overrides?: CallOverrides): Promise<string>;

    authority(overrides?: CallOverrides): Promise<string>;

    claim(
      _to: PromiseOrValue<string>,
      _rebasing: PromiseOrValue<boolean>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

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

    forfeit(overrides?: CallOverrides): Promise<BigNumber>;

    index(overrides?: CallOverrides): Promise<BigNumber>;

    rebase(overrides?: CallOverrides): Promise<BigNumber>;

    sGDAO(overrides?: CallOverrides): Promise<string>;

    secondsToNextEpoch(overrides?: CallOverrides): Promise<BigNumber>;

    setAuthority(
      _newAuthority: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<void>;

    setDistributor(
      _distributor: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<void>;

    setWarmupLength(
      _warmupPeriod: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<void>;

    stake(
      _to: PromiseOrValue<string>,
      _amount: PromiseOrValue<BigNumberish>,
      _rebasing: PromiseOrValue<boolean>,
      _claim: PromiseOrValue<boolean>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    supplyInWarmup(overrides?: CallOverrides): Promise<BigNumber>;

    toggleLock(overrides?: CallOverrides): Promise<void>;

    unstake(
      _to: PromiseOrValue<string>,
      _amount: PromiseOrValue<BigNumberish>,
      _trigger: PromiseOrValue<boolean>,
      _rebasing: PromiseOrValue<boolean>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    unwrap(
      _to: PromiseOrValue<string>,
      _amount: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    warmupInfo(
      arg0: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<
      [BigNumber, BigNumber, BigNumber, boolean] & {
        deposit: BigNumber;
        gons: BigNumber;
        expiry: BigNumber;
        lock: boolean;
      }
    >;

    warmupPeriod(overrides?: CallOverrides): Promise<BigNumber>;

    wrap(
      _to: PromiseOrValue<string>,
      _amount: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    xGDAO(overrides?: CallOverrides): Promise<string>;
  };

  filters: {
    "AuthorityUpdated(address)"(
      authority?: PromiseOrValue<string> | null
    ): AuthorityUpdatedEventFilter;
    AuthorityUpdated(
      authority?: PromiseOrValue<string> | null
    ): AuthorityUpdatedEventFilter;

    "DistributorSet(address)"(distributor?: null): DistributorSetEventFilter;
    DistributorSet(distributor?: null): DistributorSetEventFilter;

    "WarmupSet(uint256)"(warmup?: null): WarmupSetEventFilter;
    WarmupSet(warmup?: null): WarmupSetEventFilter;
  };

  estimateGas: {
    GDAO(overrides?: CallOverrides): Promise<BigNumber>;

    authority(overrides?: CallOverrides): Promise<BigNumber>;

    claim(
      _to: PromiseOrValue<string>,
      _rebasing: PromiseOrValue<boolean>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    distributor(overrides?: CallOverrides): Promise<BigNumber>;

    epoch(overrides?: CallOverrides): Promise<BigNumber>;

    forfeit(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    index(overrides?: CallOverrides): Promise<BigNumber>;

    rebase(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    sGDAO(overrides?: CallOverrides): Promise<BigNumber>;

    secondsToNextEpoch(overrides?: CallOverrides): Promise<BigNumber>;

    setAuthority(
      _newAuthority: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    setDistributor(
      _distributor: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    setWarmupLength(
      _warmupPeriod: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    stake(
      _to: PromiseOrValue<string>,
      _amount: PromiseOrValue<BigNumberish>,
      _rebasing: PromiseOrValue<boolean>,
      _claim: PromiseOrValue<boolean>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    supplyInWarmup(overrides?: CallOverrides): Promise<BigNumber>;

    toggleLock(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    unstake(
      _to: PromiseOrValue<string>,
      _amount: PromiseOrValue<BigNumberish>,
      _trigger: PromiseOrValue<boolean>,
      _rebasing: PromiseOrValue<boolean>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    unwrap(
      _to: PromiseOrValue<string>,
      _amount: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    warmupInfo(
      arg0: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    warmupPeriod(overrides?: CallOverrides): Promise<BigNumber>;

    wrap(
      _to: PromiseOrValue<string>,
      _amount: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    xGDAO(overrides?: CallOverrides): Promise<BigNumber>;
  };

  populateTransaction: {
    GDAO(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    authority(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    claim(
      _to: PromiseOrValue<string>,
      _rebasing: PromiseOrValue<boolean>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    distributor(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    epoch(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    forfeit(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    index(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    rebase(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    sGDAO(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    secondsToNextEpoch(
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    setAuthority(
      _newAuthority: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    setDistributor(
      _distributor: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    setWarmupLength(
      _warmupPeriod: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    stake(
      _to: PromiseOrValue<string>,
      _amount: PromiseOrValue<BigNumberish>,
      _rebasing: PromiseOrValue<boolean>,
      _claim: PromiseOrValue<boolean>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    supplyInWarmup(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    toggleLock(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    unstake(
      _to: PromiseOrValue<string>,
      _amount: PromiseOrValue<BigNumberish>,
      _trigger: PromiseOrValue<boolean>,
      _rebasing: PromiseOrValue<boolean>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    unwrap(
      _to: PromiseOrValue<string>,
      _amount: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    warmupInfo(
      arg0: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    warmupPeriod(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    wrap(
      _to: PromiseOrValue<string>,
      _amount: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    xGDAO(overrides?: CallOverrides): Promise<PopulatedTransaction>;
  };
}