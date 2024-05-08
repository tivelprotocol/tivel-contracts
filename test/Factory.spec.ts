import { abi as POOL_ABI } from "../artifacts/contracts/Pool.sol/Pool.json";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { expect } from "chai";

import { forkNetwork, deployContract, ThenArgRecursive, computePoolAddress } from "./shared/helpers";
import addresses from "./shared/addresses.json";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

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
    // console.log("UserStorage:", userStorage.address);
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
        factory
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

describe("Factory", async () => {
    context("arbitrum", () => {

        context("207259510", async () => {
            let fix: ThenArgRecursive<ReturnType<typeof arbitrumFixture>>;

            beforeEach(async () => {
                fix = await arbitrumFixture(207259510);
            });

            it("setManager", async () => {
                expect(await fix.factory.manager()).equals(fix.deployer.address)
                await expect(fix.factory.connect(fix.user1).setManager(fix.user1.address)).to.be.revertedWith('Forbidden')
                await fix.factory.setManager(fix.user1.address)
                expect(await fix.factory.manager()).equals(fix.user1.address)
                await expect(fix.factory.setManager(fix.user1.address)).to.be.revertedWith('Forbidden')
            });

            it("setOperator", async () => {
                await expect(fix.factory.connect(fix.user1).setOperator(fix.user1.address, true)).to.be.revertedWith('Forbidden')
                await fix.factory.setOperator(fix.user1.address, true)
                expect(await fix.factory.operator(fix.user1.address)).equals(true)

                await fix.factory.setOperator(fix.user2.address, true)
                expect(await fix.factory.operator(fix.user1.address)).equals(true)
                expect(await fix.factory.operator(fix.user2.address)).equals(true)

                await fix.factory.setOperator(fix.user1.address, false)
                expect(await fix.factory.operator(fix.user1.address)).equals(false)
                expect(await fix.factory.operator(fix.user2.address)).equals(true)
            });

            it("setUserStorage", async () => {
                expect(await fix.factory.userStorage()).equals(fix.userStorage.address)
                await expect(fix.factory.connect(fix.user1).setUserStorage(fix.user1.address)).to.be.revertedWith('Forbidden')
                await fix.factory.setUserStorage(fix.user1.address)
                expect(await fix.factory.userStorage()).equals(fix.user1.address)
            });

            it("setPriceFeed", async () => {
                expect(await fix.factory.priceFeed()).equals(fix.pricefeed.address)
                await expect(fix.factory.connect(fix.user1).setPriceFeed(fix.user1.address)).to.be.revertedWith('Forbidden')
                await fix.factory.setPriceFeed(fix.user1.address)
                expect(await fix.factory.priceFeed()).equals(fix.user1.address)
            });

            it("setDEXAggregator", async () => {
                expect(await fix.factory.dexAggregator()).equals(fix.aggregator.address)
                await expect(fix.factory.connect(fix.user1).setDEXAggregator(fix.user1.address)).to.be.revertedWith('Forbidden')
                await fix.factory.setDEXAggregator(fix.user1.address)
                expect(await fix.factory.dexAggregator()).equals(fix.user1.address)
            });

            it("setProtocolFeeTo", async () => {
                expect(await fix.factory.protocolFeeTo()).equals("0x0000000000000000000000000000000000000000")
                await expect(fix.factory.connect(fix.user1).setProtocolFeeTo(fix.user1.address)).to.be.revertedWith('Forbidden')
                await fix.factory.setProtocolFeeTo(fix.user1.address)
                expect(await fix.factory.protocolFeeTo()).equals(fix.user1.address)
            });

            it("setProtocolFeeRate", async () => {
                expect(await fix.factory.protocolFeeRate()).equals(BigNumber.from("0"))
                await expect(fix.factory.connect(fix.user1).setProtocolFeeRate(BigNumber.from("10"))).to.be.revertedWith('Forbidden')
                await expect(fix.factory.setProtocolFeeRate(BigNumber.from("10001"))).to.be.revertedWith('TooHighValue')
                await fix.factory.setProtocolFeeRate(BigNumber.from("10"))
                expect(await fix.factory.protocolFeeRate()).equals(BigNumber.from("10"))
            });

            it("setLiquidationFeeTo", async () => {
                expect(await fix.factory.liquidationFeeTo()).equals("0x0000000000000000000000000000000000000000")
                await expect(fix.factory.connect(fix.user1).setLiquidationFeeTo(fix.user1.address)).to.be.revertedWith('Forbidden')
                await expect(fix.factory.setLiquidationFeeTo("0x0000000000000000000000000000000000000000")).to.be.revertedWith('ZeroAddress')
                await fix.factory.setLiquidationFeeTo(fix.user1.address)
                expect(await fix.factory.liquidationFeeTo()).equals(fix.user1.address)
            });

            it("setLiquidationFeeRate", async () => {
                expect(await fix.factory.liquidationFeeRate()).equals(BigNumber.from("0"))
                await expect(fix.factory.connect(fix.user1).setLiquidationFeeRate(BigNumber.from("10"))).to.be.revertedWith('Forbidden')
                await fix.factory.setLiquidationFeeRate(BigNumber.from("10"))
                expect(await fix.factory.liquidationFeeRate()).equals(BigNumber.from("10"))
            });

            it("setServiceToken", async () => {
                expect(await fix.factory.serviceToken()).equals("0x0000000000000000000000000000000000000000")
                await expect(fix.factory.connect(fix.user1).setServiceToken(fix.user1.address)).to.be.revertedWith('Forbidden')
                await fix.factory.setServiceToken(fix.user1.address)
                expect(await fix.factory.serviceToken()).equals(fix.user1.address)
            });

            it("setServiceFeeTo", async () => {
                expect(await fix.factory.serviceFeeTo()).equals("0x0000000000000000000000000000000000000000")
                await expect(fix.factory.connect(fix.user1).setServiceFeeTo(fix.user1.address)).to.be.revertedWith('Forbidden')
                await fix.factory.setServiceFeeTo(fix.user1.address)
                expect(await fix.factory.serviceFeeTo()).equals(fix.user1.address)
            });

            it("setRollbackFee", async () => {
                expect(await fix.factory.rollbackFee()).equals(BigNumber.from("0"))
                await expect(fix.factory.connect(fix.user1).setRollbackFee(BigNumber.from("10"))).to.be.revertedWith('Forbidden')
                await fix.factory.setRollbackFee(BigNumber.from("10"))
                expect(await fix.factory.rollbackFee()).equals(BigNumber.from("10"))
            });

            it("setUpdateStoplossPriceFee", async () => {
                expect(await fix.factory.updateStoplossPriceFee()).equals(BigNumber.from("0"))
                await expect(fix.factory.connect(fix.user1).setUpdateStoplossPriceFee(BigNumber.from("10"))).to.be.revertedWith('Forbidden')
                await fix.factory.setUpdateStoplossPriceFee(BigNumber.from("10"))
                expect(await fix.factory.updateStoplossPriceFee()).equals(BigNumber.from("10"))
            });

            it("setUpdateCollateralAmountFee", async () => {
                expect(await fix.factory.updateCollateralAmountFee()).equals(BigNumber.from("0"))
                await expect(fix.factory.connect(fix.user1).setUpdateCollateralAmountFee(BigNumber.from("10"))).to.be.revertedWith('Forbidden')
                await fix.factory.setUpdateCollateralAmountFee(BigNumber.from("10"))
                expect(await fix.factory.updateCollateralAmountFee()).equals(BigNumber.from("10"))
            });

            it("setUpdateDeadlineFee", async () => {
                expect(await fix.factory.updateDeadlineFee()).equals(BigNumber.from("0"))
                await expect(fix.factory.connect(fix.user1).setUpdateDeadlineFee(BigNumber.from("10"))).to.be.revertedWith('Forbidden')
                await fix.factory.setUpdateDeadlineFee(BigNumber.from("10"))
                expect(await fix.factory.updateDeadlineFee()).equals(BigNumber.from("10"))
            });

            it("setMinQuoteRate", async () => {
                expect(await fix.factory.minQuoteRate()).equals(BigNumber.from("10000"))
                await expect(fix.factory.connect(fix.user1).setMinQuoteRate(BigNumber.from("10002"))).to.be.revertedWith('Forbidden')
                await expect(fix.factory.setMinQuoteRate(BigNumber.from("9999"))).to.be.revertedWith('TooLowValue')
                await fix.factory.setMinQuoteRate(BigNumber.from("10002"))
                expect(await fix.factory.minQuoteRate()).equals(BigNumber.from("10002"))
            });

            it("setManualExpiration", async () => {
                expect(await fix.factory.manualExpiration()).equals(BigNumber.from("86400"))
                await expect(fix.factory.connect(fix.user1).setManualExpiration(BigNumber.from("86401"))).to.be.revertedWith('Forbidden')
                await expect(fix.factory.setManualExpiration(BigNumber.from("86399"))).to.be.revertedWith('TooLowValue')
                await fix.factory.setManualExpiration(BigNumber.from("86401"))
                expect(await fix.factory.manualExpiration()).equals(BigNumber.from("86401"))
            });

            it("setBaseTokenMUT", async () => {
                expect(await fix.factory.baseTokenMUT(tokens.weth)).equals(BigNumber.from("0"))
                expect(await fix.factory.baseTokenMUT(tokens.usdt)).equals(BigNumber.from("0"))
                await expect(fix.factory.connect(fix.user1).setBaseTokenMUT([tokens.weth, tokens.usdt], ["7000", "8000"])).to.be.revertedWith('Forbidden')
                await expect(fix.factory.setBaseTokenMUT([tokens.weth, tokens.usdt], ["7000"])).to.be.revertedWith('BadLengths')
                await expect(fix.factory.setBaseTokenMUT([tokens.weth], ["7000", "7000"])).to.be.revertedWith('BadLengths')
                await expect(fix.factory.setBaseTokenMUT([tokens.weth, tokens.usdt], ["7000", "10001"])).to.be.revertedWith('TooHighValue')
                await fix.factory.setBaseTokenMUT([tokens.weth, tokens.usdt], ["7000", "8000"])
                expect(await fix.factory.baseTokenMUT(tokens.weth)).equals(BigNumber.from("7000"))
                expect(await fix.factory.baseTokenMUT(tokens.usdt)).equals(BigNumber.from("8000"))
            });

            it("setCollateralMUT", async () => {
                expect(await fix.factory.collateralMUT(tokens.weth)).equals(BigNumber.from("0"))
                expect(await fix.factory.collateralMUT(tokens.usdt)).equals(BigNumber.from("0"))
                await expect(fix.factory.connect(fix.user1).setCollateralMUT([tokens.weth, tokens.usdt], ["7000", "8000"])).to.be.revertedWith('Forbidden')
                await expect(fix.factory.setCollateralMUT([tokens.weth, tokens.usdt], ["7000"])).to.be.revertedWith('BadLengths')
                await expect(fix.factory.setCollateralMUT([tokens.weth], ["7000", "7000"])).to.be.revertedWith('BadLengths')
                await expect(fix.factory.setCollateralMUT([tokens.weth, tokens.usdt], ["7000", "10001"])).to.be.revertedWith('TooHighValue')
                await fix.factory.setCollateralMUT([tokens.weth, tokens.usdt], ["7000", "8000"])
                expect(await fix.factory.collateralMUT(tokens.weth)).equals(BigNumber.from("7000"))
                expect(await fix.factory.collateralMUT(tokens.usdt)).equals(BigNumber.from("8000"))
            });

            it("setBaseTokenLT", async () => {
                expect(await fix.factory.baseTokenLT(tokens.weth)).equals(BigNumber.from("0"))
                expect(await fix.factory.baseTokenLT(tokens.usdt)).equals(BigNumber.from("0"))
                await expect(fix.factory.connect(fix.user1).setBaseTokenLT([tokens.weth, tokens.usdt], ["7000", "8000"])).to.be.revertedWith('Forbidden')
                await expect(fix.factory.setBaseTokenLT([tokens.weth, tokens.usdt], ["7000"])).to.be.revertedWith('BadLengths')
                await expect(fix.factory.setBaseTokenLT([tokens.weth], ["7000", "7000"])).to.be.revertedWith('BadLengths')
                await expect(fix.factory.setBaseTokenLT([tokens.weth, tokens.usdt], ["7000", "10001"])).to.be.revertedWith('TooHighValue')
                await fix.factory.setBaseTokenLT([tokens.weth, tokens.usdt], ["7000", "8000"])
                expect(await fix.factory.baseTokenLT(tokens.weth)).equals(BigNumber.from("7000"))
                expect(await fix.factory.baseTokenLT(tokens.usdt)).equals(BigNumber.from("8000"))
            });

            it("setCollateralLT", async () => {
                expect(await fix.factory.collateralLT(tokens.weth)).equals(BigNumber.from("0"))
                expect(await fix.factory.collateralLT(tokens.usdt)).equals(BigNumber.from("0"))
                await expect(fix.factory.connect(fix.user1).setCollateralLT([tokens.weth, tokens.usdt], ["7000", "8000"])).to.be.revertedWith('Forbidden')
                await expect(fix.factory.setCollateralLT([tokens.weth, tokens.usdt], ["7000"])).to.be.revertedWith('BadLengths')
                await expect(fix.factory.setCollateralLT([tokens.weth], ["7000", "7000"])).to.be.revertedWith('BadLengths')
                await expect(fix.factory.setCollateralLT([tokens.weth, tokens.usdt], ["7000", "10001"])).to.be.revertedWith('TooHighValue')
                await fix.factory.setCollateralLT([tokens.weth, tokens.usdt], ["7000", "8000"])
                expect(await fix.factory.collateralLT(tokens.weth)).equals(BigNumber.from("7000"))
                expect(await fix.factory.collateralLT(tokens.usdt)).equals(BigNumber.from("8000"))
            });

            it("createPool", async () => {
                const wethPoolAddress = computePoolAddress(fix.poolDeployer.address, tokens.weth)
                const usdtPoolAddress = computePoolAddress(fix.poolDeployer.address, tokens.usdt)

                expect(await fix.factory.poolLength()).equals(BigNumber.from("0"))
                expect(await fix.factory.poolIndex(wethPoolAddress)).equals(BigNumber.from("0"))
                expect(await fix.factory.poolByQuoteToken(tokens.weth)).equals("0x0000000000000000000000000000000000000000")

                await expect(fix.factory.connect(fix.user1).createPool(tokens.weth, BigNumber.from("500"))).to.be.revertedWith('Forbidden')
                await fix.factory.createPool(tokens.weth, BigNumber.from("500"))
                expect(await fix.factory.poolLength()).equals(BigNumber.from("1"))
                expect(await fix.factory.poolIndex(wethPoolAddress)).equals(BigNumber.from("1"))
                expect(await fix.factory.poolByQuoteToken(tokens.weth)).equals(wethPoolAddress)
                expect(await fix.factory.interest(tokens.weth)).equals(BigNumber.from("500"))
                expect(await fix.factory.poolIndex(usdtPoolAddress)).equals(BigNumber.from("0"))
                expect(await fix.factory.poolByQuoteToken(tokens.usdt)).equals("0x0000000000000000000000000000000000000000")
                
                await fix.factory.createPool(tokens.usdt, BigNumber.from("600"))
                expect(await fix.factory.poolLength()).equals(BigNumber.from("2"))
                expect(await fix.factory.poolIndex(wethPoolAddress)).equals(BigNumber.from("1"))
                expect(await fix.factory.poolByQuoteToken(tokens.weth)).equals(wethPoolAddress)
                expect(await fix.factory.interest(tokens.weth)).equals(BigNumber.from("500"))
                expect(await fix.factory.poolIndex(usdtPoolAddress)).equals(BigNumber.from("2"))
                expect(await fix.factory.poolByQuoteToken(tokens.usdt)).equals(usdtPoolAddress)
                expect(await fix.factory.interest(tokens.usdt)).equals(BigNumber.from("600"))
            });

            it("setPoolInterest", async () => {
                const wethPoolAddress = computePoolAddress(fix.poolDeployer.address, tokens.weth)
                const usdtPoolAddress = computePoolAddress(fix.poolDeployer.address, tokens.usdt)

                await expect(fix.factory.setPoolInterest(tokens.weth, BigNumber.from("100"))).to.be.revertedWith('PoolNotExists')

                await fix.factory.createPool(tokens.weth, BigNumber.from("500"))
                await fix.factory.createPool(tokens.usdt, BigNumber.from("600"))

                const wethPool = await ethers.getContractAt(POOL_ABI, wethPoolAddress)
                const usdtPool = await ethers.getContractAt(POOL_ABI, usdtPoolAddress)

                expect(await fix.factory.interest(tokens.weth)).equals(BigNumber.from("500"))
                expect(await wethPool.interest()).equals(BigNumber.from("500"))
                expect(await fix.factory.interest(tokens.usdt)).equals(BigNumber.from("600"))
                expect(await usdtPool.interest()).equals(BigNumber.from("600"))

                await expect(fix.factory.connect(fix.user1).setPoolInterest(tokens.weth, BigNumber.from("700"))).to.be.revertedWith('Forbidden')
                await fix.factory.setPoolInterest(tokens.weth, BigNumber.from("700"))
                expect(await fix.factory.interest(tokens.weth)).equals(BigNumber.from("700"))
                expect(await wethPool.interest()).equals(BigNumber.from("700"))
                expect(await fix.factory.interest(tokens.usdt)).equals(BigNumber.from("600"))
                expect(await usdtPool.interest()).equals(BigNumber.from("600"))

                await fix.factory.setPoolInterest(tokens.usdt, BigNumber.from("800"))
                expect(await fix.factory.interest(tokens.weth)).equals(BigNumber.from("700"))
                expect(await wethPool.interest()).equals(BigNumber.from("700"))
                expect(await fix.factory.interest(tokens.usdt)).equals(BigNumber.from("800"))
                expect(await usdtPool.interest()).equals(BigNumber.from("800"))
            });

            it("setPoolMaxOpenInterest", async () => {
                const wethPoolAddress = computePoolAddress(fix.poolDeployer.address, tokens.weth)
                const usdtPoolAddress = computePoolAddress(fix.poolDeployer.address, tokens.usdt)

                await expect(fix.factory.setPoolMaxOpenInterest(tokens.weth, BigNumber.from("100"))).to.be.revertedWith('PoolNotExists')

                await fix.factory.createPool(tokens.weth, BigNumber.from("500"))
                await fix.factory.createPool(tokens.usdt, BigNumber.from("600"))
                
                const wethPool = await ethers.getContractAt(POOL_ABI, wethPoolAddress)
                const usdtPool = await ethers.getContractAt(POOL_ABI, usdtPoolAddress)

                expect(await wethPool.maxOpenInterest()).equals(BigNumber.from("0"))
                expect(await usdtPool.maxOpenInterest()).equals(BigNumber.from("0"))

                await expect(fix.factory.connect(fix.user1).setPoolMaxOpenInterest(tokens.weth, BigNumber.from("700"))).to.be.revertedWith('Forbidden')
                await fix.factory.setPoolMaxOpenInterest(tokens.weth, BigNumber.from("700"))
                expect(await wethPool.maxOpenInterest()).equals(BigNumber.from("700"))
                expect(await usdtPool.maxOpenInterest()).equals(BigNumber.from("0"))

                await fix.factory.setPoolMaxOpenInterest(tokens.usdt, BigNumber.from("800"))
                expect(await wethPool.maxOpenInterest()).equals(BigNumber.from("700"))
                expect(await usdtPool.maxOpenInterest()).equals(BigNumber.from("800"))
            });

            it("setPoolBaseTokens", async () => {
                const wethPoolAddress = computePoolAddress(fix.poolDeployer.address, tokens.weth)
                const usdtPoolAddress = computePoolAddress(fix.poolDeployer.address, tokens.usdt)

                await expect(fix.factory.setPoolBaseTokens(tokens.weth, [tokens.usdt, tokens.usdce], [true, true])).to.be.revertedWith('PoolNotExists')

                await fix.factory.createPool(tokens.weth, BigNumber.from("500"))
                await fix.factory.createPool(tokens.usdt, BigNumber.from("600"))
                
                const wethPool = await ethers.getContractAt(POOL_ABI, wethPoolAddress)
                const usdtPool = await ethers.getContractAt(POOL_ABI, usdtPoolAddress)

                expect(await wethPool.tradeableBaseToken(tokens.usdt)).equals(false)
                expect(await wethPool.tradeableBaseToken(tokens.usdce)).equals(false)
                expect(await usdtPool.tradeableBaseToken(tokens.weth)).equals(false)
                expect(await usdtPool.tradeableBaseToken(tokens.usdce)).equals(false)

                await expect(fix.factory.connect(fix.user1).setPoolBaseTokens(tokens.weth, [tokens.usdt, tokens.usdce], [true, true])).to.be.revertedWith('Forbidden')
                await expect(fix.factory.setPoolBaseTokens(tokens.weth, [tokens.usdt, tokens.usdce], [true])).to.be.revertedWith('BadLengths')
                await expect(fix.factory.setPoolBaseTokens(tokens.weth, [tokens.usdt], [true, true])).to.be.revertedWith('BadLengths')
                await fix.factory.setPoolBaseTokens(tokens.weth, [tokens.usdt, tokens.usdce], [true, true])
                expect(await wethPool.tradeableBaseToken(tokens.usdt)).equals(true)
                expect(await wethPool.tradeableBaseToken(tokens.usdce)).equals(true)
                expect(await usdtPool.tradeableBaseToken(tokens.weth)).equals(false)
                expect(await usdtPool.tradeableBaseToken(tokens.usdce)).equals(false)

                await fix.factory.setPoolBaseTokens(tokens.usdt, [tokens.weth, tokens.usdce], [true, false])
                expect(await wethPool.tradeableBaseToken(tokens.usdt)).equals(true)
                expect(await wethPool.tradeableBaseToken(tokens.usdce)).equals(true)
                expect(await usdtPool.tradeableBaseToken(tokens.weth)).equals(true)
                expect(await usdtPool.tradeableBaseToken(tokens.usdce)).equals(false)
            });
        });
    });
});