import { abi as ERC20_ABI } from "../artifacts/contracts/test/MockERC20.sol/MockERC20.json";
import { abi as WETH_ABI } from "../artifacts/contracts/test/WETH.sol/WETH.json";
import { abi as POOL_ABI } from "../artifacts/contracts/Pool.sol/Pool.json";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { expect } from "chai";

import { forkNetwork, deployContract, ThenArgRecursive, computePoolAddress } from "./shared/helpers";
import addresses from "./shared/addresses.json";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { defaultAbiCoder } from "@ethersproject/abi";

const { uniswapv3 } = addresses.arbitrum.dexes;
const { tokens } = addresses.arbitrum;

async function fixture() {
    const [deployer, user1, user2] = await ethers.getSigners();
    const poolDeployer = await deployContract(deployer, "PoolDeployer", [])
    // console.log("poolInitCodeHash:", await poolDeployer.poolInitCodeHash())
    const positionStorage = await deployContract(deployer, "PositionStorage", [])
    const withdrawalMonitor = await deployContract(deployer, "WithdrawalMonitor", ["0x0000000000000000000000000000000000000000"])
    const userStorage = await deployContract(deployer, "UserStorage", [])
    const pricefeed = await deployContract(deployer, "PriceFeed", [])
    const aggregator = await deployContract(deployer, "DEXAggregator", [])
    const factory = await deployFactory(deployer, [poolDeployer.address, positionStorage.address, withdrawalMonitor.address, userStorage.address, pricefeed.address, aggregator.address]);
    await poolDeployer.setFactory(factory.address)
    await positionStorage.setFactory(factory.address)
    await withdrawalMonitor.setFactory(factory.address)

    const wethPoolAddress = computePoolAddress(poolDeployer.address, tokens.weth)
    const usdtPoolAddress = computePoolAddress(poolDeployer.address, tokens.usdt)

    await factory.createPool(tokens.weth, BigNumber.from("500"))
    await factory.createPool(tokens.usdt, BigNumber.from("600"))
    
    const weth = await ethers.getContractAt(WETH_ABI, tokens.weth)
    const usdt = await ethers.getContractAt(ERC20_ABI, tokens.usdt)
    const wethPool = await ethers.getContractAt(POOL_ABI, wethPoolAddress)
    const usdtPool = await ethers.getContractAt(POOL_ABI, usdtPoolAddress)

    const callee = await deployContract(deployer, "Callee", [factory.address])
    return {
        deployer,
        poolDeployer,
        positionStorage,
        withdrawalMonitor,
        userStorage,
        pricefeed,
        aggregator,
        user1,
        user2,
        factory,
        weth,
        usdt,
        wethPool,
        usdtPool,
        callee
    };
}

async function deployFactory(deployer: SignerWithAddress, agrs: any[]) {
    return deployContract(
        deployer,
        "Factory",
        agrs
    )
}

// async function ethereumFixture(blockNumber: number) {
//     await forkNetwork("mainnet", blockNumber);
//     return fixture();
// }

async function arbitrumFixture(blockNumber: number) {
    await forkNetwork("arbitrum", blockNumber);
    return fixture();
}

describe("WithdrawalMonitor", async () => {
    context("arbitrum", () => {

        context("207259510", async () => {
            let fix: ThenArgRecursive<ReturnType<typeof arbitrumFixture>>;

            beforeEach(async () => {
                fix = await arbitrumFixture(207259510);

                // setup DEX Aggregator
                const univ3Integration = await deployContract(fix.deployer, "UniswapV3DEXIntegration", [uniswapv3.factory, uniswapv3.staticQuoter, uniswapv3.router])
                await fix.aggregator.addDEX(univ3Integration.address, "UniswapV3")

                // wrap 10 ETH => WETH
                await fix.weth.deposit({value: "10000000000000000000"})
                // swap 0.01 ETH => USDT
                await fix.weth.transfer(fix.aggregator.address, "10000000000000000")
                await fix.aggregator.swap("0x0000000000000000000000000000000000000000", tokens.weth, tokens.usdt, "0", fix.deployer.address)
                // transfer 2 ETH & 10 USDT to callee
                await fix.weth.transfer(fix.callee.address, "2000000000000000000")
                await fix.usdt.transfer(fix.callee.address, "10000000")
            });

            it("setManager", async () => {
                expect(await fix.withdrawalMonitor.manager()).equals(fix.deployer.address)
                await expect(fix.withdrawalMonitor.connect(fix.user1).setManager(fix.user1.address)).to.be.revertedWith('Forbidden')
                await fix.withdrawalMonitor.setManager(fix.user1.address)
                expect(await fix.withdrawalMonitor.manager()).equals(fix.user1.address)
                await expect(fix.withdrawalMonitor.setManager(fix.user1.address)).to.be.revertedWith('Forbidden')
            });

            it("setKeeper", async () => {
                expect(await fix.withdrawalMonitor.keeper()).equals("0x0000000000000000000000000000000000000000")
                await expect(fix.withdrawalMonitor.connect(fix.user1).setKeeper(fix.user1.address)).to.be.revertedWith('Forbidden')
                await fix.withdrawalMonitor.setKeeper(fix.user1.address)
                expect(await fix.withdrawalMonitor.keeper()).equals(fix.user1.address)
            });

            it("addRequest", async () => {
                const amount = BigNumber.from("1000000000000000000") // 1 WETH
                await expect(fix.withdrawalMonitor.addRequest(fix.deployer.address, fix.weth.address, amount, fix.deployer.address, "0x")).to.be.revertedWith('Forbidden')

                const withdrawalAmount1 = BigNumber.from("200000000000000000") // 0.2 WETH
                const withdrawalAmount2 = BigNumber.from("100000000000000000") // 0.1 WETH
                await fix.callee.mint(fix.wethPool.address, fix.callee.address, amount, "0x")
                await fix.callee.addBurnRequest(fix.wethPool.address, withdrawalAmount1, fix.user1.address, "0x")
                expect(await fix.withdrawalMonitor.requestLength(fix.wethPool.address)).equals(BigNumber.from("1"))
                const request1 = await fix.withdrawalMonitor.request(fix.wethPool.address, 0)
                expect(request1['index']).equals(BigNumber.from("0"))
                expect(request1['owner']).equals(fix.callee.address)
                expect(request1['quoteToken']).equals(fix.weth.address)
                expect(request1['liquidity']).equals(withdrawalAmount1)
                expect(request1['to']).equals(fix.user1.address)
                expect(request1['data']).equals("0x")
                expect(request1['callbackResult']).equals("")
                await fix.callee.addBurnRequest(fix.wethPool.address, withdrawalAmount2, fix.user2.address, "0x")
                expect(await fix.withdrawalMonitor.requestLength(fix.wethPool.address)).equals(BigNumber.from("2"))
                const request1After = await fix.withdrawalMonitor.request(fix.wethPool.address, 0)
                const request2 = await fix.withdrawalMonitor.request(fix.wethPool.address, 1)
                expect(request1After['index']).equals(request1['index'])
                expect(request1After['owner']).equals(request1['owner'])
                expect(request1After['quoteToken']).equals(request1['quoteToken'])
                expect(request1After['liquidity']).equals(request1['liquidity'])
                expect(request1After['to']).equals(request1['to'])
                expect(request1After['data']).equals(request1['data'])
                expect(request1After['callbackResult']).equals(request1['callbackResult'])
                expect(request2['index']).equals(BigNumber.from("1"))
                expect(request2['owner']).equals(fix.callee.address)
                expect(request2['quoteToken']).equals(fix.weth.address)
                expect(request2['liquidity']).equals(withdrawalAmount2)
                expect(request2['to']).equals(fix.user2.address)
                expect(request2['data']).equals("0x")
                expect(request2['callbackResult']).equals("")
            });

            it("checkUpkeep", async () => {
                const amount1 = BigNumber.from("1000000000000000000") // 1 WETH
                const amount2 = BigNumber.from("1000000") // 1 USDT
                await expect(fix.withdrawalMonitor.addRequest(fix.deployer.address, fix.weth.address, amount1, fix.deployer.address, "0x")).to.be.revertedWith('Forbidden')

                const withdrawalAmount1 = BigNumber.from("200000000000000000") // 0.2 WETH
                const withdrawalAmount2 = BigNumber.from("100000") // 0.1 USDT
                await fix.callee.mint(fix.wethPool.address, fix.callee.address, amount1, "0x")
                await fix.callee.mint(fix.usdtPool.address, fix.callee.address, amount2, "0x")

                const checkBefore = await fix.withdrawalMonitor.checkUpkeep("0x")
                expect(checkBefore['upkeepNeeded']).equals(false)
                expect(checkBefore['performData']).equals("0x")

                await fix.callee.addBurnRequest(fix.wethPool.address, withdrawalAmount1, fix.user1.address, "0x")
                const checkAfter = await fix.withdrawalMonitor.checkUpkeep("0x")
                expect(checkAfter['upkeepNeeded']).equals(true)
                const encodedData = defaultAbiCoder.encode(['address[]', 'uint256'], [[fix.wethPool.address, "0x0000000000000000000000000000000000000000"], 1])
                expect(checkAfter['performData']).equals(encodedData)

                await fix.callee.addBurnRequest(fix.usdtPool.address, withdrawalAmount2, fix.user2.address, "0x")
                const checkAfter2 = await fix.withdrawalMonitor.checkUpkeep("0x")
                expect(checkAfter2['upkeepNeeded']).equals(true)
                const encodedData2 = defaultAbiCoder.encode(['address[]', 'uint256'], [[fix.wethPool.address, fix.usdtPool.address], 2])
                expect(checkAfter2['performData']).equals(encodedData2)
            });

            it("performUpkeep", async () => {
                const amount1 = BigNumber.from("1000000000000000000") // 1 WETH
                const amount2 = BigNumber.from("1000000") // 1 USDT
                await expect(fix.withdrawalMonitor.addRequest(fix.deployer.address, fix.weth.address, amount1, fix.deployer.address, "0x")).to.be.revertedWith('Forbidden')

                const withdrawalAmount1 = BigNumber.from("200000000000000000") // 0.2 WETH
                const withdrawalAmount1_2 = BigNumber.from("100000000000000000") // 0.1 WETH
                const withdrawalAmount2 = BigNumber.from("100000") // 0.1 USDT
                await fix.callee.mint(fix.wethPool.address, fix.callee.address, amount1, "0x")
                await fix.callee.mint(fix.usdtPool.address, fix.callee.address, amount2, "0x")

                await fix.callee.addBurnRequest(fix.wethPool.address, withdrawalAmount1, fix.user1.address, "0x")
                await fix.callee.addBurnRequest(fix.wethPool.address, withdrawalAmount1_2, fix.user1.address, "0x")
                await fix.callee.addBurnRequest(fix.usdtPool.address, withdrawalAmount2, fix.user2.address, "0x")

                const check = await fix.withdrawalMonitor.checkUpkeep("0x")
                expect(await fix.withdrawalMonitor.currentIndex(fix.wethPool.address)).equals(BigNumber.from("0"))
                expect(await fix.withdrawalMonitor.currentIndex(fix.usdtPool.address)).equals(BigNumber.from("0"))
                await fix.withdrawalMonitor.performUpkeep(check['performData'])
                expect(await fix.withdrawalMonitor.currentIndex(fix.wethPool.address)).equals(BigNumber.from("1"))
                expect(await fix.withdrawalMonitor.currentIndex(fix.usdtPool.address)).equals(BigNumber.from("1"))
                const check2 = await fix.withdrawalMonitor.checkUpkeep("0x")
                await fix.withdrawalMonitor.performUpkeep(check2['performData'])
                expect(await fix.withdrawalMonitor.currentIndex(fix.wethPool.address)).equals(BigNumber.from("2"))
                expect(await fix.withdrawalMonitor.currentIndex(fix.usdtPool.address)).equals(BigNumber.from("1"))
            });
        });
    });
});