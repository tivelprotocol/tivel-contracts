import { abi as ERC20_ABI } from "../artifacts/contracts/test/MockERC20.sol/MockERC20.json";
import { abi as WETH_ABI } from "../artifacts/contracts/test/WETH.sol/WETH.json";
import { abi as POOL_ABI } from "../artifacts/contracts/Pool.sol/Pool.json";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { expect } from "chai";

import { forkNetwork, deployContract, ThenArgRecursive, computePoolAddress } from "./shared/helpers";
import addresses from "./shared/addresses.json";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

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

    const failedCallee = await deployContract(deployer, "FailedCallee", [])
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
        failedCallee,
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

describe("Pool", async () => {
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
                await fix.weth.transfer(fix.failedCallee.address, "2000000000000000000")
                await fix.weth.transfer(fix.callee.address, "2000000000000000000")
                await fix.usdt.transfer(fix.callee.address, "10000000")
            });

            it("initialize", async () => {
                expect(await fix.wethPool.factory()).equals(fix.factory.address)
                expect(await fix.wethPool.quoteToken()).equals(tokens.weth)
                expect(await fix.wethPool.precision()).equals(BigNumber.from("1000000000000000000"))
                expect(await fix.wethPool.interest()).equals(BigNumber.from("500"))

                expect(await fix.usdtPool.factory()).equals(fix.factory.address)
                expect(await fix.usdtPool.quoteToken()).equals(tokens.usdt)
                expect(await fix.usdtPool.precision()).equals(BigNumber.from("1000000"))
                expect(await fix.usdtPool.interest()).equals(BigNumber.from("600"))
            });

            it("setInterest", async () => {
                await expect(fix.wethPool.setInterest(BigNumber.from("700"))).to.be.revertedWith('Forbidden')
            });

            it("setMaxOpenInterest", async () => {
                await expect(fix.wethPool.setMaxOpenInterest(BigNumber.from("700"))).to.be.revertedWith('Forbidden')
            });

            it("setBaseTokens", async () => {
                await expect(fix.wethPool.setBaseTokens([tokens.usdt, tokens.usdce], [true, true])).to.be.revertedWith('Forbidden')
            });

            it("availLiquidity", async () => {
                await expect(fix.wethPool.availLiquidity()).to.be.revertedWith('Forbidden')
            });

            it("mint", async () => {
                const amount = BigNumber.from("1000000000000000000") // 1 WETH

                const userBalanceBefore = await fix.weth.balanceOf(fix.callee.address)
                const poolBalanceBefore = await fix.weth.balanceOf(fix.wethPool.address)
                await expect(fix.failedCallee.mint(fix.wethPool.address, fix.failedCallee.address, amount, "0x")).to.be.revertedWith('InsufficientInput')
                const posBefore = await fix.wethPool.liquidityPosition(fix.callee.address)
                expect(posBefore['liquidity']).equals(BigNumber.from("0"))
                expect(posBefore['pendingFee']).equals(BigNumber.from("0"))
                expect(posBefore['feeDebt']).equals(BigNumber.from("0"))
                await fix.callee.mint(fix.wethPool.address, fix.callee.address, amount, "0x")
                const pos = await fix.wethPool.liquidityPosition(fix.callee.address)
                expect(pos['liquidity']).equals(amount)
                expect(pos['pendingFee']).equals(BigNumber.from("0"))
                expect(pos['feeDebt']).equals(BigNumber.from("0"))
                expect(await fix.wethPool.quoteReserve()).equals(amount)
                expect(await fix.wethPool.accFeePerShare()).equals(BigNumber.from("0"))
                
                const userBalanceAfter = await fix.weth.balanceOf(fix.callee.address)
                const poolBalanceAfter = await fix.weth.balanceOf(fix.wethPool.address)
                expect(userBalanceAfter).equals(userBalanceBefore.sub(amount))
                expect(poolBalanceAfter).equals(poolBalanceBefore.add(amount))
            });

            it("addBurnRequest", async () => {
                const amount = BigNumber.from("1000000000000000000") // 1 WETH

                const userBalanceBefore = await fix.weth.balanceOf(fix.callee.address)
                const poolBalanceBefore = await fix.weth.balanceOf(fix.wethPool.address)
                await fix.callee.mint(fix.wethPool.address, fix.callee.address, amount, "0x")
                const pos = await fix.wethPool.liquidityPosition(fix.callee.address)
                expect(pos['liquidity']).equals(amount)
                expect(pos['withdrawingLiquidity']).equals(BigNumber.from("0"))
                expect(pos['pendingFee']).equals(BigNumber.from("0"))
                expect(pos['feeDebt']).equals(BigNumber.from("0"))

                const withdrawalAmount = BigNumber.from("100000000000000000") // 0.1 WETH
                await expect(fix.callee.addBurnRequest(fix.wethPool.address, amount.add(1), fix.callee.address, "0x")).to.be.revertedWith('InsufficientOutput')
                await fix.callee.addBurnRequest(fix.wethPool.address, withdrawalAmount, fix.callee.address, "0x")
                const posAfter = await fix.wethPool.liquidityPosition(fix.callee.address)
                const userBalanceAfter = await fix.weth.balanceOf(fix.callee.address)
                const poolBalanceAfter = await fix.weth.balanceOf(fix.wethPool.address)
                expect(userBalanceAfter).equals(userBalanceBefore.sub(amount))
                expect(poolBalanceAfter).equals(poolBalanceBefore.add(amount))
                expect(posAfter['liquidity']).equals(amount)
                expect(posAfter['withdrawingLiquidity']).equals(pos['withdrawingLiquidity'].add(withdrawalAmount))
                expect(posAfter['pendingFee']).equals(BigNumber.from("0"))
                expect(posAfter['feeDebt']).equals(BigNumber.from("0"))
                await expect(fix.callee.addBurnRequest(fix.wethPool.address, amount.sub(withdrawalAmount).add(1), fix.callee.address, "0x")).to.be.revertedWith('InsufficientOutput')
            });

            it("burn", async () => {
                const amount = BigNumber.from("1000000000000000000") // 1 WETH

                const userBalanceBefore = await fix.weth.balanceOf(fix.callee.address)
                const poolBalanceBefore = await fix.weth.balanceOf(fix.wethPool.address)
                await fix.callee.mint(fix.wethPool.address, fix.callee.address, amount, "0x")
                const pos = await fix.wethPool.liquidityPosition(fix.callee.address)
                expect(pos['liquidity']).equals(amount)
                expect(pos['withdrawingLiquidity']).equals(BigNumber.from("0"))
                expect(pos['pendingFee']).equals(BigNumber.from("0"))
                expect(pos['feeDebt']).equals(BigNumber.from("0"))

                const withdrawalAmount = BigNumber.from("100000000000000000") // 0.1 WETH
                await fix.callee.addBurnRequest(fix.wethPool.address, withdrawalAmount, fix.callee.address, "0x")
                await fix.withdrawalMonitor.execute(fix.wethPool.address)
                const posAfter = await fix.wethPool.liquidityPosition(fix.callee.address)
                const userBalanceAfter = await fix.weth.balanceOf(fix.callee.address)
                const poolBalanceAfter = await fix.weth.balanceOf(fix.wethPool.address)
                expect(userBalanceAfter).equals(userBalanceBefore.sub(amount).add(withdrawalAmount))
                expect(poolBalanceAfter).equals(poolBalanceBefore.add(amount).sub(withdrawalAmount))
                expect(posAfter['liquidity']).equals(amount.sub(withdrawalAmount))
                expect(posAfter['withdrawingLiquidity']).equals(BigNumber.from("0"))
                expect(posAfter['pendingFee']).equals(BigNumber.from("0"))
                expect(posAfter['feeDebt']).equals(BigNumber.from("0"))
                await expect(fix.callee.addBurnRequest(fix.wethPool.address, amount.sub(withdrawalAmount).add(1), fix.callee.address, "0x")).to.be.revertedWith('InsufficientOutput')
            });
        });
    });
});