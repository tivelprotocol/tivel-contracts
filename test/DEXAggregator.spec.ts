import { abi as UNIV3ROUTER_ABI } from "@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol/SwapRouter.json"
import { abi as UNIV3QUOTER_ABI } from "@uniswap/v3-periphery/artifacts/contracts/lens/QuoterV2.sol/QuoterV2.json"
import { abi as WETH_ABI } from "../artifacts/contracts/test/WETH.sol/WETH.json"
import { abi as ERC20_ABI } from "../artifacts/contracts/test/MockERC20.sol/MockERC20.json"
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { expect } from "chai";

import { forkNetwork, deployContract, ThenArgRecursive, bestUniswapV3AmountOut, bestUniswapV3AmountIn } from "./shared/helpers";
import addresses from "./shared/addresses.json";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

const { uniswapv3 } = addresses.arbitrum.dexes;
const { tokens } = addresses.arbitrum;

async function fixture() {
    const [deployer, user1] = await ethers.getSigners();
    const weth = await getWETH();
    const univ3Quoter = await getUniV3Quoter();
    const univ3Router = await getUniV3Router();
    const univ3Integration = await deployContract(deployer, "UniswapV3DEXIntegration", [uniswapv3.factory, uniswapv3.staticQuoter, uniswapv3.router]);
    const aggregator = await deployAggregator(deployer, []);
    // console.log("Aggregator:", aggregator.address);
    return {
        deployer,
        user1,
        weth,
        univ3Quoter,
        univ3Router,
        univ3Integration,
        aggregator
    };
}

async function getWETH() {
    return ethers.getContractAt(WETH_ABI, tokens.weth);
}

async function getUniV3Quoter() {
    return ethers.getContractAt(UNIV3QUOTER_ABI, uniswapv3.quoter);
}

async function getUniV3Router() {
    return ethers.getContractAt(UNIV3ROUTER_ABI, uniswapv3.router);
}

async function deployAggregator(deployer: SignerWithAddress, agrs: any[]) {
    return deployContract(
        deployer,
        "DEXAggregator",
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

describe("DEXAggregator", async () => {
    context("arbitrum", () => {

        context("207259510", async () => {
            let fix: ThenArgRecursive<ReturnType<typeof arbitrumFixture>>;

            beforeEach(async () => {
                fix = await arbitrumFixture(207259510);
                await fix.aggregator.addDEX(fix.univ3Integration.address, "UniswapV3")
                expect(await fix.aggregator.dexLength()).equals(BigNumber.from("1"))
                expect(await fix.aggregator.dexes(0)).equals(fix.univ3Integration.address)
                expect(await fix.aggregator.dexNames(0)).equals("UniswapV3")
                expect(await fix.aggregator.dexIndex(fix.univ3Integration.address)).equals(BigNumber.from("1"))
            });

            it("setManager", async () => {
                expect(await fix.aggregator.manager()).equals(fix.deployer.address)
                await expect(fix.aggregator.connect(fix.user1).setManager(fix.user1.address)).to.be.revertedWith('Forbidden')
                await fix.aggregator.setManager(fix.user1.address)
                expect(await fix.aggregator.manager()).equals(fix.user1.address)
                await expect(fix.aggregator.setManager(fix.user1.address)).to.be.revertedWith('Forbidden')
            });

            it("removeDEX then addDEX", async () => {
                await expect(fix.aggregator.connect(fix.user1).removeDEX(fix.univ3Integration.address)).to.be.revertedWith('Forbidden')
                await fix.aggregator.removeDEX(fix.univ3Integration.address)
                expect(await fix.aggregator.dexLength()).equals(BigNumber.from("0"))
                await expect(fix.aggregator.dexes(0)).to.be.reverted
                await expect(fix.aggregator.dexNames(0)).to.be.reverted
                expect(await fix.aggregator.dexIndex(fix.univ3Integration.address)).equals(BigNumber.from("0"))

                await expect(fix.aggregator.connect(fix.user1).addDEX(fix.univ3Integration.address, "UniswapV3")).to.be.revertedWith('Forbidden')
                await fix.aggregator.addDEX(fix.univ3Integration.address, "UniswapV3")
                expect(await fix.aggregator.dexLength()).equals(BigNumber.from("1"))
                expect(await fix.aggregator.dexes(0)).equals(fix.univ3Integration.address)
                expect(await fix.aggregator.dexNames(0)).equals("UniswapV3")
                expect(await fix.aggregator.dexIndex(fix.univ3Integration.address)).equals(BigNumber.from("1"))

                await expect(fix.aggregator.addDEX(fix.univ3Integration.address, "UniswapV3_2")).to.be.revertedWith('DEXExistsAlready')
                
                await fix.aggregator.addDEX("0x0000000000000000000000000000000000000000", "Test DEX")
                expect(await fix.aggregator.dexLength()).equals(BigNumber.from("2"))
                expect(await fix.aggregator.dexes(0)).equals(fix.univ3Integration.address)
                expect(await fix.aggregator.dexNames(0)).equals("UniswapV3")
                expect(await fix.aggregator.dexIndex(fix.univ3Integration.address)).equals(BigNumber.from("1"))
                expect(await fix.aggregator.dexes(1)).equals("0x0000000000000000000000000000000000000000")
                expect(await fix.aggregator.dexNames(1)).equals("Test DEX")
                expect(await fix.aggregator.dexIndex("0x0000000000000000000000000000000000000000")).equals(BigNumber.from("2"))

                await fix.aggregator.removeDEX("0x0000000000000000000000000000000000000000")
                expect(await fix.aggregator.dexLength()).equals(BigNumber.from("1"))
                expect(await fix.aggregator.dexes(0)).equals(fix.univ3Integration.address)
                expect(await fix.aggregator.dexNames(0)).equals("UniswapV3")
                expect(await fix.aggregator.dexIndex(fix.univ3Integration.address)).equals(BigNumber.from("1"))
                await expect(fix.aggregator.dexes(1)).to.be.reverted
                await expect(fix.aggregator.dexNames(1)).to.be.reverted
                expect(await fix.aggregator.dexIndex("0x0000000000000000000000000000000000000000")).equals(BigNumber.from("0"))

            });

            it("getAmountOut: 0.01 WETH => USDT", async () => {
                const tokenIn = tokens.weth
                const tokenOut = tokens.usdt
                const amountIn = BigNumber.from("10000000000000000")

                const reference = await bestUniswapV3AmountOut(fix.univ3Quoter, tokenIn, tokenOut, amountIn)
                const amountOut = (await fix.aggregator.getAmountOut("0x0000000000000000000000000000000000000000", tokenIn, tokenOut, amountIn))['amountOut']
                expect(amountOut).equals(reference)
            });

            it("getAmountOut: 1 USDT => WETH", async () => {
                const tokenIn = tokens.usdt
                const tokenOut = tokens.weth
                const amountIn = BigNumber.from("1000000")

                const reference = await bestUniswapV3AmountOut(fix.univ3Quoter, tokenIn, tokenOut, amountIn)
                const amountOut = (await fix.aggregator.getAmountOut("0x0000000000000000000000000000000000000000", tokenIn, tokenOut, amountIn))['amountOut']
                expect(amountOut).equals(reference)
            });

            it("getAmountIn: WETH => 1 USDT", async () => {
                const tokenIn = tokens.weth
                const tokenOut = tokens.usdt
                const amountOut = BigNumber.from("1000000")

                const reference = await bestUniswapV3AmountIn(fix.univ3Quoter, tokenIn, tokenOut, amountOut)
                const amountIn = (await fix.aggregator.getAmountIn("0x0000000000000000000000000000000000000000", tokenIn, tokenOut, amountOut))['amountIn']
                expect(amountIn).equals(reference)
            });

            it("getAmountIn: USDT => 0.01 WETH", async () => {
                const tokenIn = tokens.usdt
                const tokenOut = tokens.weth
                const amountOut = BigNumber.from("10000000000000000")

                const reference = await bestUniswapV3AmountIn(fix.univ3Quoter, tokenIn, tokenOut, amountOut)
                const amountIn = (await fix.aggregator.getAmountIn("0x0000000000000000000000000000000000000000", tokenIn, tokenOut, amountOut))['amountIn']
                expect(amountIn).equals(reference)
            });

            it("swap: 0.01 WETH => USDT then 1 USDT => WETH", async () => {
                const usdt = await ethers.getContractAt(ERC20_ABI, tokens.usdt)
                const amountIn1 = BigNumber.from("10000000000000000")
                const reference1 = await bestUniswapV3AmountOut(fix.univ3Quoter, tokens.weth, tokens.usdt, amountIn1)

                await fix.weth.deposit({value: amountIn1})
                await fix.weth.transfer(fix.aggregator.address, amountIn1)
                await fix.aggregator.swap("0x0000000000000000000000000000000000000000", tokens.weth, tokens.usdt, "0", fix.deployer.address)
                const wethBalance1 = await fix.weth.balanceOf(fix.deployer.address)
                const usdtBalance1 = await usdt.balanceOf(fix.deployer.address)
                expect(wethBalance1).equals(BigNumber.from("0"))
                expect(usdtBalance1).equals(reference1)

                const amountIn2 = BigNumber.from("1000000")
                const reference2 = await bestUniswapV3AmountOut(fix.univ3Quoter, tokens.usdt, tokens.weth, amountIn2)
                
                await usdt.transfer(fix.aggregator.address, amountIn2)
                await fix.aggregator.swap("0x0000000000000000000000000000000000000000", tokens.usdt, tokens.weth, "0", fix.deployer.address)
                const wethBalance2 = await fix.weth.balanceOf(fix.deployer.address)
                const usdtBalance2 = await usdt.balanceOf(fix.deployer.address)
                expect(usdtBalance2).equals(usdtBalance1.sub(amountIn2))
                expect(wethBalance2).equals(reference2)
            });
        });
    });
});