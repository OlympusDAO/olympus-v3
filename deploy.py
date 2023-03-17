from foundrydeploy import Network, Deployer, TEST_SIGNER

contracts = [
    # (Contract Label, ContractPath:ContractName, ContractAddress)
    # (
    #     "LABEL1",
    #     "src/Contract1.sol:ContractName1",
    #     "0x1111111111111111111111111111111111111111",
    # ),
    # ("LABEL2", "src/Contract2.sol:ContractName2"),
    # ("LABEL3", "", "0x2222222222222222222222222222222222222222"),
    ("KERNEL", "src/Kernel.sol:Kernel"),
]

deployer = Deployer(
    Network.LOCAL,
    TEST_SIGNER,
    contracts,
    is_legacy=True,  # for legacy transactions
    debug=False,  # if True, prints the calling commands and raw output
)

path = [
    # Format :
    # (ACTION_TYPE, CONTRACT_LABEL, [ARG, ... ])
    # Both Deploy and Send will be skipped
    # (Deployer.SKIP_START, 0, 0),
    # (Deployer.DEPLOY, "LABEL1", ["Arg1", "Arg2", "11ether"]),
    # (
    #     Deployer.SEND,
    #     "LABEL1",
    #     ["functionName", "9999999999", "00" * 32, "00" * 32, "0"],
    # ),
    # (Deployer.SKIP_END, 0, 0),
    # It will be skipped, since we passed an address above (0x11..11)
    # (Deployer.DEPLOY, "LABEL1", ["Arg1", "Arg2", "11ether"]),
    # # Will find out the `functionName` signature and call it to the address of LABEL1
    # # (Deployer.SEND, "LABEL1",   ["functionName", "9999999999", "00"*32, "00"*32, "0"]),
    # # Deploys LABEL2 and passes LABEL1 address as the first argument
    # (Deployer.DEPLOY, "LABEL2", ["$LABEL1", "arg2", "1gwei"]),
    # (Deployer.DEPLOY, "LABEL2", ["$LABEL1", "arg2", "1gwei"]),
    (Deployer.DEPLOY, "KERNEL", []),
    
    # # Will find out the `functionName` signature and call it to the address of LABEL1
    # (Deployer.SEND, "LABEL2", ["functionName", "9999999999"]),
    # Since LABEL3 has no contract path, it's the same as calling `cast send 0x2222222222222222222222222222222222222222 1gwei`
    # (Deployer.SEND, "LABEL3", ["function_name(uint256)", "1gwei"])
]

deployer.path(path)