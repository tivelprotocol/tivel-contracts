import CHAINLINK_INTERFACE_ABI from "./shared/abis/ChainlinkInterface.json";
import PYTH_INTERFACE_ABI from "./shared/abis/PythInterface.json";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { expect } from "chai";

import { forkNetwork, deployContract, ThenArgRecursive, bestUniswapV3Price, precision, bestUniswapV2Price } from "./shared/helpers";
import addresses from "./shared/addresses.json";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

const chainlink = addresses.arbitrum.chainlink;
const pyth = addresses.arbitrum.pyth;
const { uniswapv2, uniswapv3 } = addresses.arbitrum.dexes;
const { tokens } = addresses.arbitrum;

async function fixture() {
    const [deployer, user1] = await ethers.getSigners();
    const eth_usd = await getChainlink(chainlink["eth/usd"]);
    const btc_usd = await getChainlink(chainlink["btc/usd"]);
    const usdt_usd = await getChainlink(chainlink["usdt/usd"]);
    const usdc_usd = await getChainlink(chainlink["usdc/usd"]);
    const pythContract = await getPyth();
    const chainlinkIntegration = await deployContract(deployer, "ChainlinkPriceFeedIntegration", []);
    const pythIntegration = await deployContract(deployer, "PythPriceFeedIntegration", [pyth.address]);
    const univ2Integration = await deployContract(deployer, "UniswapV2PriceFeedIntegration", [uniswapv2.factory]);
    const univ3Integration = await deployContract(deployer, "UniswapV3PriceFeedIntegration", [uniswapv3.factory]);

    return {
        deployer,
        user1,
        eth_usd,
        btc_usd,
        usdt_usd,
        usdc_usd,
        pythContract,
        chainlinkIntegration,
        pythIntegration,
        univ2Integration,
        univ3Integration,
    };
}

async function getChainlink(pair: string) {
    return ethers.getContractAt(CHAINLINK_INTERFACE_ABI, pair);
}

async function getPyth() {
    return ethers.getContractAt(PYTH_INTERFACE_ABI, pyth.address);
}

// async function ethereumFixture(blockNumber: number) {
//     await forkNetwork("mainnet", blockNumber);
//     return fixture();
// }

async function arbitrumFixture(blockNumber: number) {
    await forkNetwork("arbitrum", blockNumber);
    return fixture();
}

describe("PriceFeedIntegration", async () => {
    context("arbitrum", () => {

        context("207259510", async () => {
            let fix: ThenArgRecursive<ReturnType<typeof arbitrumFixture>>;

            beforeEach(async () => {
                fix = await arbitrumFixture(207259510);
                await fix.chainlinkIntegration.setPriceFeed(tokens.weth, chainlink["eth/usd"])
                await fix.chainlinkIntegration.setPriceFeed(tokens.wbtc, chainlink["btc/usd"])
                await fix.chainlinkIntegration.setPriceFeed(tokens.usdt, chainlink["usdt/usd"])
                await fix.chainlinkIntegration.setPriceFeed(tokens.usdc, chainlink["usdc/usd"])

                await fix.pythIntegration.setPriceFeed(tokens.weth, pyth.ids["eth/usd"])
                await fix.pythIntegration.setPriceFeed(tokens.wbtc, pyth.ids["btc/usd"])
                await fix.pythIntegration.setPriceFeed(tokens.usdt, pyth.ids["usdt/usd"])
                await fix.pythIntegration.setPriceFeed(tokens.usdc, pyth.ids["usdc/usd"])
            });

            it("getPrice: USDT/USDT", async () => {
                const baseToken = tokens.usdt
                const quoteToken = tokens.usdt

                const prec = precision(30)

                const price0 = await fix.chainlinkIntegration.getPrice(baseToken, quoteToken)
                expect(price0.mul(precision(22))).equals(prec)
                const price1 = await fix.pythIntegration.getPrice(baseToken, quoteToken)
                expect(price1.mul(precision(12))).equals(prec)
                const price2 = await fix.univ2Integration.getPrice(baseToken, quoteToken)
                expect(price2).equals(prec)
                const price3 = await fix.univ3Integration.getPrice(baseToken, quoteToken)
                expect(price3).equals(prec)
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
                const pyth_eth_usd = await fix.pythContract.getPriceUnsafe(pyth.ids["eth/usd"])
                const pyth_usdt_usd = await fix.pythContract.getPriceUnsafe(pyth.ids["usdt/usd"])
                const i1Result = await fix.pythIntegration.getPrice(baseToken, quoteToken)
                expect(pyth_eth_usd.price.mul(precision(18 - pyth_eth_usd.expo)).mul(precision(18)).div(pyth_usdt_usd.price.mul(precision(18 - pyth_usdt_usd.expo)))).equals(i1Result)
                const univ2PoolResult = await bestUniswapV2Price(uniswapv2.factory, baseToken, quoteToken, prec)
                const i2Result = await fix.univ2Integration.getPrice(baseToken, quoteToken)
                expect(univ2PoolResult.price).equals(i2Result)
                const univ3PoolResult = await bestUniswapV3Price(uniswapv3.factory, baseToken, quoteToken, prec)
                const i3Result = await fix.univ3Integration.getPrice(baseToken, quoteToken)
                expect(univ3PoolResult.price).equals(i3Result)

            });
        });
    });
});