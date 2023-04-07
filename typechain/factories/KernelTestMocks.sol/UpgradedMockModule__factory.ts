/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import { Signer, utils, Contract, ContractFactory, Overrides } from "ethers";
import type { Provider, TransactionRequest } from "@ethersproject/providers";
import type { PromiseOrValue } from "../../common";
import type {
  UpgradedMockModule,
  UpgradedMockModuleInterface,
} from "../../KernelTestMocks.sol/UpgradedMockModule";

const _abi = [
  {
    inputs: [
      {
        internalType: "contract Kernel",
        name: "kernel_",
        type: "address",
      },
      {
        internalType: "contract MockModule",
        name: "oldModule_",
        type: "address",
      },
    ],
    stateMutability: "nonpayable",
    type: "constructor",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "caller_",
        type: "address",
      },
    ],
    name: "KernelAdapter_OnlyKernel",
    type: "error",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "policy_",
        type: "address",
      },
    ],
    name: "Module_PolicyNotPermitted",
    type: "error",
  },
  {
    inputs: [],
    name: "INIT",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "KEYCODE",
    outputs: [
      {
        internalType: "Keycode",
        name: "",
        type: "bytes5",
      },
    ],
    stateMutability: "pure",
    type: "function",
  },
  {
    inputs: [],
    name: "VERSION",
    outputs: [
      {
        internalType: "uint8",
        name: "major",
        type: "uint8",
      },
      {
        internalType: "uint8",
        name: "minor",
        type: "uint8",
      },
    ],
    stateMutability: "pure",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "contract Kernel",
        name: "newKernel_",
        type: "address",
      },
    ],
    name: "changeKernel",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "kernel",
    outputs: [
      {
        internalType: "contract Kernel",
        name: "",
        type: "address",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "permissionedCall",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "permissionedState",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "publicCall",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "publicState",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
] as const;

const _bytecode =
  "0x608060405234801561001057600080fd5b506040516104b43803806104b483398101604081905261002f91610078565b600080546001600160a01b039384166001600160a01b031991821617909155600180549290931691161790556100b2565b6001600160a01b038116811461007557600080fd5b50565b6000806040838503121561008b57600080fd5b825161009681610060565b60208401519092506100a781610060565b809150509250929050565b6103f3806100c16000396000f3fe608060405234801561001057600080fd5b50600436106100835760003560e01c80631ae7ec2e14610088578063382b325f146100ae5780634657b36c146100b8578063a7167caf146100cb578063abfe7614146100d3578063c69ab056146100ea578063d4aae0c4146100f3578063ea64391414610113578063ffa1ad741461011b575b600080fd5b61009061012f565b6040516001600160d81b031990911681526020015b60405180910390f35b6100b661013b565b005b6100b66100c6366004610317565b610152565b6100b66101aa565b6100dc60025481565b6040519081526020016100a5565b6100dc60035481565b600054610106906001600160a01b031681565b6040516100a59190610347565b6100b661026e565b6040805160008082526020820152016100a5565b644d4f434b5960d81b90565b6002805490600061014b8361035b565b9190505550565b6000546001600160a01b03163314610188573360405163053e900f60e21b815260040161017f9190610347565b60405180910390fd5b600080546001600160a01b0319166001600160a01b0392909216919091179055565b6000546001600160a01b031663f166d9eb6101c361012f565b6040516001600160e01b031960e084901b811682526001600160d81b03199290921660048201523360248201526000359091166044820152606401602060405180830381865afa15801561021b573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019061023f9190610382565b61025e57336040516311bf00c960e01b815260040161017f9190610347565b6003805490600061014b8361035b565b6000546001600160a01b0316331461029b573360405163053e900f60e21b815260040161017f9190610347565b600160009054906101000a90046001600160a01b03166001600160a01b031663c69ab0566040518163ffffffff1660e01b8152600401602060405180830381865afa1580156102ee573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019061031291906103a4565b600355565b60006020828403121561032957600080fd5b81356001600160a01b038116811461034057600080fd5b9392505050565b6001600160a01b0391909116815260200190565b60006001820161037b57634e487b7160e01b600052601160045260246000fd5b5060010190565b60006020828403121561039457600080fd5b8151801515811461034057600080fd5b6000602082840312156103b657600080fd5b505191905056fea2646970667358221220140609745e8a59374b7037dd5ed05bd315e5453f27d8a2e3d934a535614401be64736f6c634300080f0033";

type UpgradedMockModuleConstructorParams =
  | [signer?: Signer]
  | ConstructorParameters<typeof ContractFactory>;

const isSuperArgs = (
  xs: UpgradedMockModuleConstructorParams
): xs is ConstructorParameters<typeof ContractFactory> => xs.length > 1;

export class UpgradedMockModule__factory extends ContractFactory {
  constructor(...args: UpgradedMockModuleConstructorParams) {
    if (isSuperArgs(args)) {
      super(...args);
    } else {
      super(_abi, _bytecode, args[0]);
    }
  }

  override deploy(
    kernel_: PromiseOrValue<string>,
    oldModule_: PromiseOrValue<string>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<UpgradedMockModule> {
    return super.deploy(
      kernel_,
      oldModule_,
      overrides || {}
    ) as Promise<UpgradedMockModule>;
  }
  override getDeployTransaction(
    kernel_: PromiseOrValue<string>,
    oldModule_: PromiseOrValue<string>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): TransactionRequest {
    return super.getDeployTransaction(kernel_, oldModule_, overrides || {});
  }
  override attach(address: string): UpgradedMockModule {
    return super.attach(address) as UpgradedMockModule;
  }
  override connect(signer: Signer): UpgradedMockModule__factory {
    return super.connect(signer) as UpgradedMockModule__factory;
  }

  static readonly bytecode = _bytecode;
  static readonly abi = _abi;
  static createInterface(): UpgradedMockModuleInterface {
    return new utils.Interface(_abi) as UpgradedMockModuleInterface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): UpgradedMockModule {
    return new Contract(address, _abi, signerOrProvider) as UpgradedMockModule;
  }
}