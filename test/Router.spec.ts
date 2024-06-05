import { abi as ERC20_ABI } from "../artifacts/contracts/test/MockERC20.sol/MockERC20.json";
import { abi as WETH_ABI } from "../artifacts/contracts/test/WETH.sol/WETH.json";
import { abi as POOL_ABI } from "../artifacts/contracts/Pool.sol/Pool.json";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { expect } from "chai";

import { forkNetwork, deployContract, ThenArgRecursive, computePoolAddress, precision } from "./shared/helpers";
import addresses from "./shared/addresses.json";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

const chainlink = addresses.arbitrum.chainlink;
const { uniswapv3 } = addresses.arbitrum.dexes;
const { tokens } = addresses.arbitrum;

async function fixture() {
    const [deployer, user1, user2] = await ethers.getSigners();
    const poolDeployer = await deployContract(deployer, "PoolDeployer", [])
    console.log("poolInitCodeHash:", await poolDeployer.poolInitCodeHash())
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
    const usdce = await ethers.getContractAt(ERC20_ABI, tokens.usdce)
    const wethPool = await ethers.getContractAt(POOL_ABI, wethPoolAddress)
    const usdtPool = await ethers.getContractAt(POOL_ABI, usdtPoolAddress)

    const callee = await deployContract(deployer, "Callee", [factory.address])
    const router = await deployContract(deployer, "Router", [factory.address, tokens.weth])
    const time = await deployContract(deployer, "Time", [])
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
        usdce,
        wethPool,
        usdtPool,
        callee,
        router,
        time
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

describe("Router", async () => {
    context("arbitrum", () => {

        context("207259510", async () => {
            let fix: ThenArgRecursive<ReturnType<typeof arbitrumFixture>>;

            beforeEach(async () => {
                fix = await arbitrumFixture(207259510);

                // setup PriceFeed
                const chainlinkPriceIntegration = await deployContract(fix.deployer, "ChainlinkPriceFeedIntegration", [])
                const univ3PriceIntegration = await deployContract(fix.deployer, "UniswapV3PriceFeedIntegration", [uniswapv3.factory])
                await chainlinkPriceIntegration.setPriceFeed(tokens.weth, chainlink["eth/usd"])
                await chainlinkPriceIntegration.setPriceFeed(tokens.wbtc, chainlink["btc/usd"])
                await chainlinkPriceIntegration.setPriceFeed(tokens.usdt, chainlink["usdt/usd"])
                await chainlinkPriceIntegration.setPriceFeed(tokens.usdc, chainlink["usdc/usd"])
                await fix.pricefeed.setIntegrations([chainlinkPriceIntegration.address, univ3PriceIntegration.address])

                // setup DEX Aggregator
                const univ3DEXIntegration = await deployContract(fix.deployer, "UniswapV3DEXIntegration", [uniswapv3.factory, uniswapv3.staticQuoter, uniswapv3.router])
                await fix.aggregator.addDEX(univ3DEXIntegration.address, "UniswapV3")

                await fix.factory.setMinQuoteRate("10200")
                // setup basetoken MUT & LT
                await fix.factory.setBaseTokenMUT([tokens.weth, tokens.usdt, tokens.usdce], ["8000", "8000", "8000"])
                await fix.factory.setBaseTokenLT([tokens.weth, tokens.usdt, tokens.usdce], ["8500", "8500", "8500"])
                // setup collateral MUT & LT
                await fix.factory.setCollateralMUT([tokens.weth, tokens.usdt, tokens.usdce], ["8000", "8000", "8000"])
                await fix.factory.setCollateralLT([tokens.weth, tokens.usdt, tokens.usdce], ["8500", "8500", "8500"])

                // wrap 10 ETH => WETH
                await fix.weth.deposit({ value: "10000000000000000000" })
                // swap 0.01 ETH => USDT
                await fix.weth.transfer(fix.aggregator.address, "10000000000000000")
                await fix.aggregator.swap("0x0000000000000000000000000000000000000000", tokens.weth, tokens.usdt, "0", fix.deployer.address)
                // swap 0.01 ETH => USDC.e
                await fix.weth.transfer(fix.aggregator.address, "10000000000000000")
                await fix.aggregator.swap("0x0000000000000000000000000000000000000000", tokens.weth, tokens.usdce, "0", fix.deployer.address)

                // transfer 1 ETH & 10 USDT to callee
                await fix.weth.transfer(fix.callee.address, "1000000000000000000")
                await fix.usdt.transfer(fix.callee.address, "10000000")
                // deposit 1 WETH & 10 USDT
                await fix.callee.mint(fix.wethPool.address, fix.callee.address, BigNumber.from("1000000000000000000"), "0x")
                await fix.callee.mint(fix.usdtPool.address, fix.callee.address, BigNumber.from("10000000"), "0x")
            });

            it("openTradePosition", async () => {
                const baseToken = tokens.weth
                const quoteToken = tokens.usdt
                const collateral = tokens.usdce
                const baseAmount = BigNumber.from("1000000000000000") // 0.001 WETH
                const timestamp = await fix.time.timestamp()
                const deadline = timestamp.add(15 * 60) // 15 minutes

                const basePrice = await fix.pricefeed.getLowestPrice(baseToken, quoteToken)
                const minCollateralAmount = await fix.positionStorage.getMinCollateralAmount({
                    owner: fix.deployer.address,
                    baseToken,
                    quoteToken,
                    collateral,
                    baseAmount,
                    quoteAmount: "0",
                    collateralAmount: "0",
                    deadline,
                    stoplossPrice: "0",
                    takeProfitPrice: "0"
                })

                const collateralAmount = minCollateralAmount.add(1)
                const quoteAmountRange = await fix.positionStorage.getQuoteAmountRange({
                    owner: fix.deployer.address,
                    baseToken,
                    quoteToken,
                    collateral,
                    baseAmount,
                    quoteAmount: "0",
                    collateralAmount,
                    deadline,
                    stoplossPrice: "0",
                    takeProfitPrice: "0"
                })
                const quoteAmount = quoteAmountRange['minQuoteAmount'].eq(quoteAmountRange['maxQuoteAmount']) ? quoteAmountRange['minQuoteAmount'] : quoteAmountRange['minQuoteAmount'].add(1)

                const params = {
                    baseToken,
                    quoteToken,
                    collateral,
                    baseAmount,
                    quoteAmount,
                    collateralAmount,
                    deadline,
                    stoplossPrice: basePrice.mul(9).div(10), // decrease 10%
                    takeProfitPrice: basePrice.mul(105).div(100), // increase 5%
                    txDeadline: deadline,
                }
                // setup tradeable tokens
                await fix.factory.setPoolBaseTokens(tokens.usdt, [tokens.weth], [true])

                await fix.weth.approve(fix.router.address, baseAmount)
                await fix.usdce.approve(fix.router.address, collateralAmount)
                await fix.factory.setPoolMaxOpenInterest(tokens.usdt, quoteAmount)

                console.log((await fix.positionStorage.estimateGas.previewTradePosition({
                    owner: fix.deployer.address,
                    baseToken,
                    quoteToken,
                    collateral,
                    baseAmount,
                    quoteAmount,
                    collateralAmount,
                    deadline,
                    stoplossPrice: basePrice.mul(9).div(10), // decrease 10%,
                    takeProfitPrice: basePrice.mul(105).div(100) // increase 5%
                })).toString())
                console.log((await fix.router.estimateGas.open(params)).toString())
            });
        });
    });
});