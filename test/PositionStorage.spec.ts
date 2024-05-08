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
    const usdce = await ethers.getContractAt(ERC20_ABI, tokens.usdce)
    const wethPool = await ethers.getContractAt(POOL_ABI, wethPoolAddress)
    const usdtPool = await ethers.getContractAt(POOL_ABI, usdtPoolAddress)

    const callee = await deployContract(deployer, "Callee", [])
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

describe("PositionStorage", async () => {
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

            it("getMinCollateralAmount", async () => {
                const baseToken = tokens.weth
                const quoteToken = tokens.usdt
                const collateral = tokens.usdce
                const baseAmount = BigNumber.from("1000000000000000") // 0.001 WETH
                const timestamp = await fix.time.timestamp()
                const deadline = timestamp.add(15 * 60) // 15 minutes

                const prec = precision(30)
                const minQuoteRate = await fix.factory.minQuoteRate()
                const baseTokenMUT = await fix.factory.baseTokenMUT(baseToken)
                const collateralMUT = await fix.factory.collateralMUT(collateral)
                const basePrice = await fix.pricefeed.getLowestPrice(baseToken, quoteToken)
                const baseValue = baseAmount.mul(basePrice).div(prec)
                const minCollateralValue = baseValue.mul(minQuoteRate.sub(baseTokenMUT)).div(collateralMUT)
                const collateralPrice = await fix.pricefeed.getLowestPrice(collateral, quoteToken)
                const minCollateralAmount = minCollateralValue.mul(prec).div(collateralPrice)

                const params = {
                    owner: fix.deployer.address,
                    baseToken,
                    quoteToken,
                    collateral,
                    baseAmount,
                    quoteAmount: "0",
                    collateralAmount: "0",
                    deadline,
                    stoplossPrice: "0"
                }
                expect(await fix.positionStorage.getMinCollateralAmount(params)).equals(minCollateralAmount)
            });

            it("getQuoteAmountRange", async () => {
                const baseToken = tokens.weth
                const quoteToken = tokens.usdt
                const collateral = tokens.usdce
                const baseAmount = BigNumber.from("1000000000000000") // 0.001 WETH
                const timestamp = await fix.time.timestamp()
                const deadline = timestamp.add(15 * 60) // 15 minutes

                const prec = precision(30)
                const minQuoteRate = await fix.factory.minQuoteRate()
                const baseTokenMUT = await fix.factory.baseTokenMUT(baseToken)
                const collateralMUT = await fix.factory.collateralMUT(collateral)
                const basePrice = await fix.pricefeed.getLowestPrice(baseToken, quoteToken)
                const baseValue = baseAmount.mul(basePrice).div(prec)
                const minCollateralValue = baseValue.mul(minQuoteRate.sub(baseTokenMUT)).div(collateralMUT)
                const collateralPrice = await fix.pricefeed.getLowestPrice(collateral, quoteToken)
                const minCollateralAmount = minCollateralValue.mul(prec).div(collateralPrice)

                const collateralAmount = minCollateralAmount.add(1)
                const collateralValue = collateralAmount.mul(collateralPrice).div(prec)

                const failedParams = {
                    owner: fix.deployer.address,
                    baseToken,
                    quoteToken,
                    collateral,
                    baseAmount,
                    quoteAmount: "0",
                    collateralAmount: minCollateralAmount.sub(1),
                    deadline,
                    stoplossPrice: "0"
                }
                const failedResults = await fix.positionStorage.getQuoteAmountRange(failedParams)
                expect(failedResults[0]).equals(BigNumber.from("0"))
                expect(failedResults[1]).equals(BigNumber.from("0"))

                const minQuoteAmount = baseValue.mul(minQuoteRate).div(10000)
                const mutb = baseValue.mul(baseTokenMUT).div(10000)
                const mutc = collateralValue.mul(collateralMUT).div(10000)
                const maxQuoteAmount = mutb.add(mutc)

                const params = {
                    owner: fix.deployer.address,
                    baseToken,
                    quoteToken,
                    collateral,
                    baseAmount,
                    quoteAmount: "0",
                    collateralAmount,
                    deadline,
                    stoplossPrice: "0"
                }
                const results = await fix.positionStorage.getQuoteAmountRange(params)
                expect(results[0]).equals(minQuoteAmount)
                expect(results[1]).equals(maxQuoteAmount)
            });

            it("previewTradePosition", async () => {
                const baseToken = tokens.weth
                const quoteToken = tokens.usdt
                const collateral = tokens.usdce
                const baseAmount = BigNumber.from("1000000000000000") // 0.001 WETH
                const timestamp = await fix.time.timestamp()
                const deadline = timestamp.add(15 * 60) // 15 minutes

                const prec = precision(30)
                const baseTokenMUT = await fix.factory.baseTokenMUT(baseToken)
                const collateralMUT = await fix.factory.collateralMUT(collateral)
                const basePrice = await fix.pricefeed.getLowestPrice(baseToken, quoteToken)
                const baseValue = baseAmount.mul(basePrice).div(prec)
                const mutb = baseValue.mul(baseTokenMUT).div(10000)
                const collateralPrice = await fix.pricefeed.getLowestPrice(collateral, quoteToken)
                const minCollateralAmount = await fix.positionStorage.getMinCollateralAmount({
                    owner: fix.deployer.address,
                    baseToken,
                    quoteToken,
                    collateral,
                    baseAmount,
                    quoteAmount: "0",
                    collateralAmount: "0",
                    deadline,
                    stoplossPrice: "0"
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
                    stoplossPrice: "0"
                })
                const quoteAmount = quoteAmountRange['minQuoteAmount'].eq(quoteAmountRange['maxQuoteAmount']) ? quoteAmountRange['minQuoteAmount'] : quoteAmountRange['minQuoteAmount'].add(1)

                const failedParams1 = {
                    owner: fix.deployer.address,
                    baseToken,
                    quoteToken,
                    collateral,
                    baseAmount,
                    quoteAmount: quoteAmount,
                    collateralAmount: minCollateralAmount.sub(1),
                    deadline,
                    stoplossPrice: "0"
                }
                const failedResults1 = await fix.positionStorage.previewTradePosition(failedParams1)
                expect(failedResults1.pool).equals("0x0000000000000000000000000000000000000000")

                const failedParams2 = {
                    owner: fix.deployer.address,
                    baseToken,
                    quoteToken,
                    collateral,
                    baseAmount,
                    quoteAmount: quoteAmountRange['minQuoteAmount'].sub(1),
                    collateralAmount,
                    deadline,
                    stoplossPrice: "0"
                }
                const failedResults2 = await fix.positionStorage.previewTradePosition(failedParams2)
                expect(failedResults2.pool).equals("0x0000000000000000000000000000000000000000")

                const failedParams3 = {
                    owner: fix.deployer.address,
                    baseToken,
                    quoteToken,
                    collateral,
                    baseAmount,
                    quoteAmount: quoteAmountRange['maxQuoteAmount'].add(1),
                    collateralAmount,
                    deadline,
                    stoplossPrice: "0"
                }
                const failedResults3 = await fix.positionStorage.previewTradePosition(failedParams3)
                expect(failedResults3.pool).equals("0x0000000000000000000000000000000000000000")

                const baseTokenLT = await fix.factory.baseTokenLT(baseToken)
                const collateralLT = await fix.factory.collateralLT(collateral)
                const baseLiqPrice = mutb.mul(baseTokenLT).mul(prec).div(baseAmount).div(baseTokenMUT)
                const collateralLiqValue = quoteAmount.sub(mutb).mul(collateralLT).div(collateralMUT)
                const collateralLiqPrice = collateralLiqValue.mul(prec).div(collateralAmount)

                const interest = await fix.factory.interest(quoteToken)
                const protocolFeeRate = await fix.factory.protocolFeeRate()
                const fee = quoteAmount.mul(interest).mul(BigNumber.from(deadline).sub(timestamp)).div(365 * 24 * 60 * 60 * 10000)
                const protocolFee = fee.mul(protocolFeeRate).div(10000)

                const params = {
                    owner: fix.deployer.address,
                    baseToken,
                    quoteToken,
                    collateral,
                    baseAmount,
                    quoteAmount,
                    collateralAmount,
                    deadline,
                    stoplossPrice: basePrice.mul(9).div(10) // decrease 10%
                }
                const results = await fix.positionStorage.previewTradePosition(params)
                expect(results.pool).equals(fix.usdtPool.address)
                expect(results.owner).equals(fix.deployer.address)
                expect(results.baseToken.id).equals(baseToken)
                expect(results.baseToken.amount).equals(baseAmount)
                expect(results.baseToken.entryPrice).equals(basePrice)
                expect(results.baseToken.liqPrice).equals(baseLiqPrice)
                expect(results.baseToken.closePrice).equals(BigNumber.from("0"))
                expect(results.collateral.id).equals(collateral)
                expect(results.collateral.amount).equals(collateralAmount)
                expect(results.collateral.entryPrice).equals(collateralPrice)
                expect(results.collateral.liqPrice).equals(collateralLiqPrice)
                expect(results.collateral.closePrice).equals(BigNumber.from("0"))
                expect(results.quoteToken.id).equals(quoteToken)
                expect(results.quoteToken.amount).equals(quoteAmount)
                expect(results.deadline).equals(deadline)
                expect(results.stoplossPrice).equals(params.stoplossPrice)
                expect(results.fee).equals(fee)
                expect(results.protocolFee).equals(protocolFee)
                expect(results.status.isClosed).equals(false)
                expect(results.status.isExpired).equals(false)
                expect(results.status.isStoploss).equals(false)
                expect(results.status.isBaseLiquidated).equals(false)
                expect(results.status.isCollateralLiquidated).equals(false)
                expect(results.status.isRollbacked).equals(false)
                expect(results.status.isClosedManuallyStep1).equals(false)
                expect(results.status.isClosedManuallyStep2).equals(false)
                expect(results.closer).equals("0x0000000000000000000000000000000000000000")
                expect(results.liquidationMarkTime).equals(BigNumber.from("0"))
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
                    stoplossPrice: "0"
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
                    stoplossPrice: "0"
                })
                const quoteAmount = quoteAmountRange['minQuoteAmount'].eq(quoteAmountRange['maxQuoteAmount']) ? quoteAmountRange['minQuoteAmount'] : quoteAmountRange['minQuoteAmount'].add(1)

                const params = {
                    owner: fix.deployer.address,
                    baseToken,
                    quoteToken,
                    collateral,
                    baseAmount,
                    quoteAmount,
                    collateralAmount,
                    deadline,
                    stoplossPrice: basePrice.mul(9).div(10) // decrease 10%
                }
                await expect(fix.wethPool.open(params)).to.be.revertedWith('WrongPool')
                await expect(fix.usdtPool.open({
                    ...params,
                    baseToken: quoteToken
                })).to.be.revertedWith('InvalidParameters')
                await expect(fix.usdtPool.open(params)).to.be.revertedWith('UntradeableBaseToken')
                // setup tradeable tokens
                await fix.factory.setPoolBaseTokens(tokens.usdt, [tokens.weth], [true])
                await expect(fix.usdtPool.open(params)).to.be.revertedWith('InsufficientInput')

                await fix.weth.transfer(fix.usdtPool.address, baseAmount)
                await fix.usdce.transfer(fix.usdtPool.address, collateralAmount)
                // await expect(fix.usdtPool.open(params)).to.be.revertedWith('ExceedMaxOpenInterest')
                await fix.factory.setPoolMaxOpenInterest(tokens.usdt, quoteAmount)

                await fix.usdtPool.open(params)
                expect(await fix.positionStorage.positionLength()).equals(BigNumber.from("1"))
                const positionKey = (await fix.positionStorage.position(0)).positionKey
                expect((await fix.positionStorage.positionByKey(positionKey)).positionKey).equals(positionKey)
                expect(await fix.positionStorage.positionIndex(positionKey)).equals(BigNumber.from("1"))
                expect(await fix.positionStorage.openingPositionLength()).equals(BigNumber.from("1"))
                expect(await fix.positionStorage.openingPositionKeys(0)).equals(positionKey)
                expect(await fix.positionStorage.openingPositionIndex(positionKey)).equals(BigNumber.from("1"))
                expect(await fix.positionStorage.userPositionLength(fix.deployer.address)).equals(BigNumber.from("1"))
                expect(await fix.positionStorage.positionKeyByUser(fix.deployer.address, 0)).equals(positionKey)
            });
        });
    });
});