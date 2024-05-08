import CHAINLINK_INTERFACE_ABI from "./shared/abis/ChainlinkInterface.json";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { expect } from "chai";

import { forkNetwork, deployContract, ThenArgRecursive, bestUniswapV3Price, precision } from "./shared/helpers";
import addresses from "./shared/addresses.json";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

const chainlink = addresses.arbitrum.chainlink;
const { uniswapv3 } = addresses.arbitrum.dexes;
const { tokens } = addresses.arbitrum;

async function fixture() {
    const [deployer, user1] = await ethers.getSigners();
    const eth_usd = await getChainlink(chainlink["eth/usd"]);
    const btc_usd = await getChainlink(chainlink["btc/usd"]);
    const usdt_usd = await getChainlink(chainlink["usdt/usd"]);
    const usdc_usd = await getChainlink(chainlink["usdc/usd"]);
    const chainlinkIntegration = await deployContract(deployer, "ChainlinkPriceFeedIntegration", []);
    const univ3Integration = await deployContract(deployer, "UniswapV3PriceFeedIntegration", [uniswapv3.factory]);
    const pricefeed = await deployPriceFeed(deployer, []);
    // console.log("PriceFeed:", pricefeed.address);
    return {
        deployer,
        user1,
        eth_usd,
        btc_usd,
        usdt_usd,
        usdc_usd,
        chainlinkIntegration,
        univ3Integration,
        pricefeed
    };
}

async function getChainlink(pair: string) {
    return ethers.getContractAt(CHAINLINK_INTERFACE_ABI, pair);
}

async function deployPriceFeed(deployer: SignerWithAddress, agrs: any[]) {
    return deployContract(
        deployer,
        "PriceFeed",
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

describe("PriceFeed", async () => {
    context("arbitrum", () => {

        context("207259510", async () => {
            let fix: ThenArgRecursive<ReturnType<typeof arbitrumFixture>>;

            beforeEach(async () => {
                fix = await arbitrumFixture(207259510);
                await fix.chainlinkIntegration.setPriceFeed(tokens.weth, chainlink["eth/usd"])
                await fix.chainlinkIntegration.setPriceFeed(tokens.wbtc, chainlink["btc/usd"])
                await fix.chainlinkIntegration.setPriceFeed(tokens.usdt, chainlink["usdt/usd"])
                await fix.chainlinkIntegration.setPriceFeed(tokens.usdc, chainlink["usdc/usd"])
                await fix.pricefeed.setIntegrations([fix.chainlinkIntegration.address, fix.univ3Integration.address])
                const i0 = await fix.pricefeed.integrations(0)
                const i1 = await fix.pricefeed.integrations(1)
                expect(i0).equals(fix.chainlinkIntegration.address)
                expect(i1).equals(fix.univ3Integration.address)
            });

            it("setManager", async () => {
                expect(await fix.pricefeed.manager()).equals(fix.deployer.address)
                await expect(fix.pricefeed.connect(fix.user1).setManager(fix.user1.address)).to.be.revertedWith('Forbidden')
                await fix.pricefeed.setManager(fix.user1.address)
                expect(await fix.pricefeed.manager()).equals(fix.user1.address)
                await expect(fix.pricefeed.setManager(fix.user1.address)).to.be.revertedWith('Forbidden')
            });

            it("setIntegrations", async () => {
                await expect(fix.pricefeed.connect(fix.user1).setIntegrations([fix.chainlinkIntegration.address])).to.be.revertedWith('Forbidden')
                await fix.pricefeed.setIntegrations([fix.chainlinkIntegration.address])
                const i0 = await fix.pricefeed.integrations(0)
                expect(i0).equals(fix.chainlinkIntegration.address)

                await fix.pricefeed.setIntegrations([fix.univ3Integration.address])
                const i1 = await fix.pricefeed.integrations(0)
                expect(i1).equals(fix.univ3Integration.address)
            });

            it("getHighestPrice: USDT/USDT", async () => {
                const baseToken = tokens.usdt
                const quoteToken = tokens.usdt

                const prec = precision(30)
                
                const price = await fix.pricefeed.getHighestPrice(baseToken, quoteToken)
                expect(price).equals(prec)
            });

            it("getHighestPrice: WETH/USDT", async () => {
                const baseToken = tokens.weth
                const quoteToken = tokens.usdt

                const eth_usd = BigNumber.from((await fix.eth_usd.latestAnswer()).toString())
                const usdt_usd = BigNumber.from((await fix.usdt_usd.latestAnswer()).toString())
                const prec = precision(30)
                const chainlinkResult = eth_usd.mul(precision(8)).div(usdt_usd).mul(precision(22))
                const i0Result = await fix.chainlinkIntegration.getPrice(baseToken, quoteToken)
                expect(chainlinkResult).equals(i0Result.mul(precision(22)))
                const univ3PoolResult = await bestUniswapV3Price(uniswapv3.factory, baseToken, quoteToken, prec)
                const i1Result = await fix.univ3Integration.getPrice(baseToken, quoteToken)
                expect(univ3PoolResult.price).equals(i1Result)
                
                const reference = chainlinkResult.gt(univ3PoolResult.price) ? chainlinkResult : univ3PoolResult.price
                const price = await fix.pricefeed.getHighestPrice(baseToken, quoteToken)
                expect(price).equals(reference.mul(precision(univ3PoolResult.quoteDecimals)).div(precision(univ3PoolResult.baseDecimals)))
            });

            it("getHighestPrice: USDT/WETH", async () => {
                const baseToken = tokens.usdt
                const quoteToken = tokens.weth

                const eth_usd = BigNumber.from((await fix.eth_usd.latestAnswer()).toString())
                const usdt_usd = BigNumber.from((await fix.usdt_usd.latestAnswer()).toString())
                const prec = precision(30)
                const chainlinkResult = usdt_usd.mul(precision(8)).div(eth_usd).mul(precision(22))
                const i0Result = await fix.chainlinkIntegration.getPrice(baseToken, quoteToken)
                expect(chainlinkResult).equals(i0Result.mul(precision(22)))
                const univ3PoolResult = await bestUniswapV3Price(uniswapv3.factory, baseToken, quoteToken, prec)
                const i1Result = await fix.univ3Integration.getPrice(baseToken, quoteToken)
                expect(univ3PoolResult.price).equals(i1Result)
                
                const reference = chainlinkResult.gt(univ3PoolResult.price) ? chainlinkResult : univ3PoolResult.price
                const price = await fix.pricefeed.getHighestPrice(baseToken, quoteToken)
                expect(price).equals(reference.mul(precision(univ3PoolResult.quoteDecimals)).div(precision(univ3PoolResult.baseDecimals)))
            });

            it("getLowestPrice: USDT/USDT", async () => {
                const baseToken = tokens.usdt
                const quoteToken = tokens.usdt

                const prec = precision(30)
                
                const price = await fix.pricefeed.getLowestPrice(baseToken, quoteToken)
                expect(price).equals(prec)
            });

            it("getLowestPrice: WETH/USDT", async () => {
                const baseToken = tokens.weth
                const quoteToken = tokens.usdt

                const eth_usd = BigNumber.from((await fix.eth_usd.latestAnswer()).toString())
                const usdt_usd = BigNumber.from((await fix.usdt_usd.latestAnswer()).toString())
                const prec = precision(30)
                const chainlinkResult = eth_usd.mul(precision(8)).div(usdt_usd).mul(precision(22))
                const i0Result = await fix.chainlinkIntegration.getPrice(baseToken, quoteToken)
                expect(chainlinkResult).equals(i0Result.mul(precision(22)))
                const univ3PoolResult = await bestUniswapV3Price(uniswapv3.factory, baseToken, quoteToken, prec)
                const i1Result = await fix.univ3Integration.getPrice(baseToken, quoteToken)
                expect(univ3PoolResult.price).equals(i1Result)

                const reference = chainlinkResult.lt(univ3PoolResult.price) ? chainlinkResult : univ3PoolResult.price
                const price = await fix.pricefeed.getLowestPrice(baseToken, quoteToken)
                expect(price).equals(reference.mul(precision(univ3PoolResult.quoteDecimals)).div(precision(univ3PoolResult.baseDecimals)))
            });

            it("getLowestPrice: USDT/WETH", async () => {
                const baseToken = tokens.usdt
                const quoteToken = tokens.weth

                const eth_usd = BigNumber.from((await fix.eth_usd.latestAnswer()).toString())
                const usdt_usd = BigNumber.from((await fix.usdt_usd.latestAnswer()).toString())
                const prec = precision(30)
                const chainlinkResult = usdt_usd.mul(precision(8)).div(eth_usd).mul(precision(22))
                const i0Result = await fix.chainlinkIntegration.getPrice(baseToken, quoteToken)
                expect(chainlinkResult).equals(i0Result.mul(precision(22)))
                const univ3PoolResult = await bestUniswapV3Price(uniswapv3.factory, baseToken, quoteToken, prec)
                const i1Result = await fix.univ3Integration.getPrice(baseToken, quoteToken)
                expect(univ3PoolResult.price).equals(i1Result)

                const reference = chainlinkResult.lt(univ3PoolResult.price) ? chainlinkResult : univ3PoolResult.price
                const price = await fix.pricefeed.getLowestPrice(baseToken, quoteToken)
                expect(price).equals(reference.mul(precision(univ3PoolResult.quoteDecimals)).div(precision(univ3PoolResult.baseDecimals)))
            });

            it("getPrice: USDT/USDT", async () => {
                const baseToken = tokens.usdt
                const quoteToken = tokens.usdt

                const prec = precision(30)
                
                const prices = await fix.pricefeed.getPrice(baseToken, quoteToken)
                expect(prices['lowest']).equals(prec)
                expect(prices['highest']).equals(prec)
            });

            it("getPrice: WETH/USDT", async () => {
                const baseToken = tokens.weth
                const quoteToken = tokens.usdt

                const eth_usd = BigNumber.from((await fix.eth_usd.latestAnswer()).toString())
                const usdt_usd = BigNumber.from((await fix.usdt_usd.latestAnswer()).toString())
                const prec = precision(30)
                const chainlinkResult = eth_usd.mul(precision(8)).div(usdt_usd).mul(precision(22))
                const i0Result = await fix.chainlinkIntegration.getPrice(baseToken, quoteToken)
                expect(chainlinkResult).equals(i0Result.mul(precision(22)))
                const univ3PoolResult = await bestUniswapV3Price(uniswapv3.factory, baseToken, quoteToken, prec)
                const i1Result = await fix.univ3Integration.getPrice(baseToken, quoteToken)
                expect(univ3PoolResult.price).equals(i1Result)

                const lowestRef = chainlinkResult.lt(univ3PoolResult.price) ? chainlinkResult : univ3PoolResult.price
                const highestRef = chainlinkResult.gt(univ3PoolResult.price) ? chainlinkResult : univ3PoolResult.price
                const prices = await fix.pricefeed.getPrice(baseToken, quoteToken)
                expect(prices['lowest']).equals(lowestRef.mul(precision(univ3PoolResult.quoteDecimals)).div(precision(univ3PoolResult.baseDecimals)))
                expect(prices['highest']).equals(highestRef.mul(precision(univ3PoolResult.quoteDecimals)).div(precision(univ3PoolResult.baseDecimals)))
            });

            it("getPrice: USDT/WETH", async () => {
                const baseToken = tokens.usdt
                const quoteToken = tokens.weth

                const eth_usd = BigNumber.from((await fix.eth_usd.latestAnswer()).toString())
                const usdt_usd = BigNumber.from((await fix.usdt_usd.latestAnswer()).toString())
                const prec = precision(30)
                const chainlinkResult = usdt_usd.mul(precision(8)).div(eth_usd).mul(precision(22))
                const i0Result = await fix.chainlinkIntegration.getPrice(baseToken, quoteToken)
                expect(chainlinkResult).equals(i0Result.mul(precision(22)))
                const univ3PoolResult = await bestUniswapV3Price(uniswapv3.factory, baseToken, quoteToken, prec)
                const i1Result = await fix.univ3Integration.getPrice(baseToken, quoteToken)
                expect(univ3PoolResult.price).equals(i1Result)

                const lowestRef = chainlinkResult.lt(univ3PoolResult.price) ? chainlinkResult : univ3PoolResult.price
                const highestRef = chainlinkResult.gt(univ3PoolResult.price) ? chainlinkResult : univ3PoolResult.price
                const prices = await fix.pricefeed.getPrice(baseToken, quoteToken)
                expect(prices['lowest']).equals(lowestRef.mul(precision(univ3PoolResult.quoteDecimals)).div(precision(univ3PoolResult.baseDecimals)))
                expect(prices['highest']).equals(highestRef.mul(precision(univ3PoolResult.quoteDecimals)).div(precision(univ3PoolResult.baseDecimals)))
            });
        });
    });
});