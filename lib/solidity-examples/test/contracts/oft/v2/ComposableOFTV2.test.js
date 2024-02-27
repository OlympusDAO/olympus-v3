const { expect } = require("chai")
const { ethers } = require("hardhat")

describe("ComposableOFT v2: ", function () {
    const srcChainId = 1
    const dstChainId = 2

    let srcEndpoint, dstEndpoint, srcOFT, dstOFT, srcStaking, dstStaking, dstPath, srcPath
    let owner, alice, bob, carol
    let dstStakingAddressBytes32, srcStakingAddressBytes32

    before(async function () {
        const LZEndpointMock = await ethers.getContractFactory("LZEndpointMock")
        const OFT = await ethers.getContractFactory("ExampleOFTV2")
        const OFTStakingMock = await ethers.getContractFactory("OFTStakingMockV2")

        srcEndpoint = await LZEndpointMock.deploy(srcChainId)
        dstEndpoint = await LZEndpointMock.deploy(dstChainId)

        srcOFT = await OFT.deploy(srcEndpoint.address, ethers.utils.parseEther("1000000"), 6)
        dstOFT = await OFT.deploy(dstEndpoint.address, 0, 6)

        srcStaking = await OFTStakingMock.deploy(srcOFT.address)
        dstStaking = await OFTStakingMock.deploy(dstOFT.address)

        // internal bookkeeping for endpoints (not part of a real deploy, just for this test)
        srcEndpoint.setDestLzEndpoint(dstOFT.address, dstEndpoint.address)
        dstEndpoint.setDestLzEndpoint(srcOFT.address, srcEndpoint.address)

        // set each contracts source address so it can send to each other
        dstPath = ethers.utils.solidityPack(["address", "address"], [dstOFT.address, srcOFT.address])
        srcPath = ethers.utils.solidityPack(["address", "address"], [srcOFT.address, dstOFT.address])
        await srcOFT.setTrustedRemote(dstChainId, dstPath) // for A, set B
        await dstOFT.setTrustedRemote(srcChainId, srcPath) // for B, set A

        // set each contracts source address so it can send to each other
        dstStakingAddressBytes32 = ethers.utils.defaultAbiCoder.encode(["address"], [dstStaking.address])
        srcStakingAddressBytes32 = ethers.utils.defaultAbiCoder.encode(["address"], [srcStaking.address])
        await srcStaking.setRemoteStakingContract(dstChainId, dstStakingAddressBytes32)
        await dstStaking.setRemoteStakingContract(srcChainId, srcStakingAddressBytes32)

        //set destination min gas
        await srcOFT.setMinDstGas(dstChainId, parseInt(await srcOFT.PT_SEND()), 225000)
        await srcOFT.setUseCustomAdapterParams(true)

        owner = (await ethers.getSigners())[0]
        alice = (await ethers.getSigners())[1]
        bob = (await ethers.getSigners())[2]
        carol = (await ethers.getSigners())[3]
    })

    it("deposit on dst chain", async function () {
        // owner transfer 100 ether token to alice
        const amount = ethers.utils.parseEther("100")

        await srcOFT.transfer(alice.address, amount)
        expect(await srcOFT.balanceOf(alice.address)).to.equal(amount)

        // alice deposit 100 ether token to dst chain and transfer to bob
        await srcOFT.connect(alice).approve(srcStaking.address, amount)

        const adapterParam = ethers.utils.solidityPack(["uint16", "uint256"], [1, 225000 + 300000]) // min gas of OFT + gas for call
        // deposit on dst chain
        const fee = await srcStaking.quoteForDeposit(dstChainId, bob.address, amount, adapterParam)

        await srcStaking.connect(alice).depositToDstChain(dstChainId, bob.address, amount, adapterParam, { value: fee[0] })

        // check balance
        expect(await srcOFT.balanceOf(alice.address)).to.equal(0)
        expect(await dstOFT.balanceOf(dstStaking.address)).to.equal(amount)
        expect(await dstStaking.balances(bob.address)).to.equal(amount)

        // withdraw
        await dstStaking.connect(bob).withdraw(amount)
        expect(await dstOFT.balanceOf(dstStaking.address)).to.equal(0)
        expect(await dstOFT.balanceOf(bob.address)).to.equal(amount)
    })

    it("failed to call on oft received for paused", async function () {
        // owner transfer 50 ether token to alice
        const amount = ethers.utils.parseEther("50")
        await srcOFT.transfer(alice.address, amount)
        expect(await srcOFT.balanceOf(alice.address)).to.equal(amount)

        // carol 100 ether token to dst chain and transfer to bob
        await srcOFT.connect(alice).approve(srcStaking.address, amount)

        await dstStaking.setPaused(true) // paused on dst chain

        const adapterParam = ethers.utils.solidityPack(["uint16", "uint256"], [1, 225000 + 300000]) // min gas of OFT + gas for call

        // deposit on dst chain
        const fee = await srcStaking.quoteForDeposit(dstChainId, carol.address, amount, adapterParam)
        await srcStaking.connect(alice).depositToDstChain(dstChainId, carol.address, amount, adapterParam, { value: fee[0] })

        // check balance
        expect(await srcOFT.balanceOf(alice.address)).to.equal(0)
        expect(await dstOFT.balanceOf(dstOFT.address)).to.equal(amount)
        expect(await dstStaking.balances(carol.address)).to.equal(0) // failed to call onOFTReceived() for paused

        // should be 0 for failure to call onOFTReceived()
        expect(await dstOFT.balanceOf(dstStaking.address)).to.equal(0)
    })

    it("retry to call onOFTReceived() by calling retryMessage()", async function () {
        await dstStaking.setPaused(false) // unpaused on dst chain

        const amount = ethers.utils.parseEther("50")
        const amountSD = amount.div(Math.pow(10, 12))
        const payloadForCall = ethers.utils.defaultAbiCoder.encode(["uint8", "bytes"], [1, carol.address])

        // retry to call onOFTReceived()
        const payload = ethers.utils.solidityPack(
            ["uint8", "bytes32", "uint64", "bytes32", "uint64", "bytes"],
            [1, dstStakingAddressBytes32, amountSD, srcStakingAddressBytes32, 300000, payloadForCall]
        )

        // console.log("_from", alice.address)
        // console.log("_to", dstOFT.address)
        // console.log("_amount", amount)
        // console.log("payload", payload)
        await dstOFT.retryMessage(srcChainId, srcPath, 2, payload)
        expect(await dstStaking.balances(carol.address)).to.equal(amount)
        expect(await dstOFT.balanceOf(dstStaking.address)).to.equal(amount)
    })
})
