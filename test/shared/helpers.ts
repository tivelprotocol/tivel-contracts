import { config, ethers, network } from "hardhat";
import { BigNumber, BytesLike, Contract, Overrides, Signer } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { FeeAmount, POOL_INIT_CODE_HASH } from "@uniswap/v3-sdk";
import { getCreate2Address } from "@ethersproject/address";
import { keccak256 } from "@ethersproject/solidity";
import { defaultAbiCoder } from "@ethersproject/abi";
import { abi as ERC20_ABI } from "../../artifacts/contracts/test/MockERC20.sol/MockERC20.json";
import { abi as UNIV3_POOL_ABI } from "@uniswap/v3-core/artifacts/contracts/UniswapV3Pool.sol/UniswapV3Pool.json";

export const setHardhatNetwork = async (
    { forkBlockNumber, chainId, rpcUrl }:
        { forkBlockNumber: number, chainId: number, rpcUrl: string }
) => {
    return network.provider.request({
        method: "hardhat_reset",
        params: [
            {
                chainId: chainId,
                forking: {
                    blockNumber: forkBlockNumber,
                    jsonRpcUrl: rpcUrl,
                },
            },
        ],
    });
}

export type ThenArgRecursive<T> = T extends PromiseLike<infer U>
    ? ThenArgRecursive<U>
    : T;

export async function forkNetwork(networkName: string, blockNumber: number) {
    const networkConfig = config.networks[networkName];
    await setHardhatNetwork({
        rpcUrl: (networkConfig as any).url,
        forkBlockNumber: blockNumber,
        chainId: (networkConfig as any).chainId,
    })
}

export async function deployContract(
    deployer: SignerWithAddress,
    contract: string,
    args?: any[],
) {
    return ethers.getContractFactory(contract)
        .then(f => f.connect(deployer).deploy(...(args || [])))
}

export function computePoolAddress(poolDeployerAddress: string, quoteToken: string): string {
    return getCreate2Address(
        poolDeployerAddress,
        keccak256(
            ['bytes'],
            [defaultAbiCoder.encode(['address'], [quoteToken])]
        ),
        "0x6c6a3125043137214ba9fce2fbc49163378d28fdd84e53dba5c0af27a794e0bf"
    )
}

export function computeUniV3PoolAddress(factoryAddress: string, tokenA: string, tokenB: string, fee: FeeAmount, initCodeHashManualOverride?: string): string {
    return getCreate2Address(
        factoryAddress,
        keccak256(
            ['bytes'],
            [defaultAbiCoder.encode(['address', 'address', 'uint24'], [tokenA, tokenB, fee])]
        ),
        initCodeHashManualOverride ?? POOL_INIT_CODE_HASH
    )
}

export async function uniswapV3PoolInfo(tokenA: Contract, tokenB: Contract, poolAddress: string, prec: BigNumber): Promise<{ address: string, price: BigNumber, liquidity: BigNumber }> {
    const pool = await ethers.getContractAt(UNIV3_POOL_ABI, poolAddress)
    const balanceA = await tokenA.balanceOf(poolAddress)
    const balanceB = await tokenB.balanceOf(poolAddress)
    const slot0 = await pool.slot0()
    const two_pow_192 = BigNumber.from("6277101735386680763835789423207666416102355444464034512896")
    const price = BigNumber.from(slot0['sqrtPriceX96'].toString()).pow(2).mul(prec).div(two_pow_192)
    const liquidity = balanceA.mul(price).add(balanceB)
    return {
        address: poolAddress,
        price,
        liquidity
    }
}

export function precision(decimals: number): BigNumber {
    let result = BigNumber.from("1")
    for (let i = 0; i < decimals; i++) {
        result = result.mul(10)
    }

    return result
}

export async function bestUniswapV3Price(factoryAddress: string, baseToken: string, quoteToken: string, prec: BigNumber): Promise<{ address: string, baseDecimals: number, quoteDecimals: number, price: BigNumber, liquidity: BigNumber }> {
    const tokenAAddress = baseToken < quoteToken ? baseToken : quoteToken
    const tokenBAddress = baseToken < quoteToken ? quoteToken : baseToken

    const tokenA = await ethers.getContractAt(ERC20_ABI, tokenAAddress)
    const tokenB = await ethers.getContractAt(ERC20_ABI, tokenBAddress)
    const decimalsA = Number((await tokenA.decimals()).toString())
    const decimalsB = Number((await tokenB.decimals()).toString())

    const highFeePoolAddress = computeUniV3PoolAddress(factoryAddress, tokenAAddress, tokenBAddress, FeeAmount.HIGH)
    const highFeeInfo = await uniswapV3PoolInfo(tokenA, tokenB, highFeePoolAddress, prec)
    const mediumFeePoolAddress = computeUniV3PoolAddress(factoryAddress, tokenAAddress, tokenBAddress, FeeAmount.MEDIUM)
    const mediumFeeInfo = await uniswapV3PoolInfo(tokenA, tokenB, mediumFeePoolAddress, prec)
    const lowFeePoolAddress = computeUniV3PoolAddress(factoryAddress, tokenAAddress, tokenBAddress, FeeAmount.LOW)
    const lowFeeInfo = await uniswapV3PoolInfo(tokenA, tokenB, lowFeePoolAddress, prec)
    const lowestFeePoolAddress = computeUniV3PoolAddress(factoryAddress, tokenAAddress, tokenBAddress, FeeAmount.LOWEST)
    const lowestFeeInfo = await uniswapV3PoolInfo(tokenA, tokenB, lowestFeePoolAddress, prec)

    const bestInfo = [highFeeInfo, mediumFeeInfo, lowFeeInfo, lowestFeeInfo].sort((a, b) => {
        return a.liquidity.gt(b.liquidity) ? -1 : 1
    })[0]
    const price = baseToken === tokenAAddress
        ? bestInfo.price.mul(precision(decimalsA)).div(precision(decimalsB))
        : prec.pow(2).div(bestInfo.price).mul(precision(decimalsB)).div(precision(decimalsA))

    return {
        address: bestInfo.address,
        baseDecimals: baseToken < quoteToken ? decimalsA : decimalsB,
        quoteDecimals: baseToken < quoteToken ? decimalsB : decimalsA,
        price,
        liquidity: bestInfo.liquidity
    }
}

async function tryCall(call: any) {
    try {
        return await call
    }
    catch (e) {
        console.log(e)
        return undefined
    }
}

export async function bestUniswapV3AmountOut(quoter: Contract, tokenIn: string, tokenOut: string, amountIn: BigNumber): Promise<BigNumber> {
    const params = {
        tokenIn,
        tokenOut,
        amountIn,
        sqrtPriceLimitX96: tokenIn.toLowerCase() < tokenOut.toLowerCase()
            ? BigNumber.from('4295128740')
            : BigNumber.from('1461446703485210103287273052203988822378723970341')
    }
    const highFeeAmountOut = await tryCall(quoter.callStatic.quoteExactInputSingle({
        ...params,
        fee: FeeAmount.HIGH
    }))
    const mediumFeeAmountOut = await tryCall(quoter.callStatic.quoteExactInputSingle({
        ...params,
        fee: FeeAmount.MEDIUM,
    }))
    const lowFeeAmountOut = await tryCall(quoter.callStatic.quoteExactInputSingle({
        ...params,
        fee: FeeAmount.LOW,
    }))
    const lowestFeeAmountOut = await tryCall(quoter.callStatic.quoteExactInputSingle({
        ...params,
        fee: FeeAmount.LOWEST,
    }))

    const bestAmountOut = [highFeeAmountOut, mediumFeeAmountOut, lowFeeAmountOut, lowestFeeAmountOut].sort((a, b) => {
        a = a ? a['amountOut'] : BigNumber.from("0")
        b = b ? b['amountOut'] : BigNumber.from("0")
        return a.gt(b) ? -1 : 1
    })[0]

    return bestAmountOut ? bestAmountOut['amountOut'] : BigNumber.from("0")
}

export async function bestUniswapV3AmountIn(quoter: Contract, tokenIn: string, tokenOut: string, amountOut: BigNumber): Promise<BigNumber> {
    const params = {
        tokenIn,
        tokenOut,
        amount: amountOut,
        sqrtPriceLimitX96: tokenIn.toLowerCase() < tokenOut.toLowerCase()
            ? BigNumber.from('4295128740')
            : BigNumber.from('1461446703485210103287273052203988822378723970341')
    }
    const highFeeAmountIn = await tryCall(quoter.callStatic.quoteExactOutputSingle({
        ...params,
        fee: FeeAmount.HIGH
    }))
    const mediumFeeAmountIn = await tryCall(quoter.callStatic.quoteExactOutputSingle({
        ...params,
        fee: FeeAmount.MEDIUM,
    }))
    const lowFeeAmountIn = await tryCall(quoter.callStatic.quoteExactOutputSingle({
        ...params,
        fee: FeeAmount.LOW,
    }))
    const lowestFeeAmountIn = await tryCall(quoter.callStatic.quoteExactOutputSingle({
        ...params,
        fee: FeeAmount.LOWEST,
    }))

    const bestAmountIn = [highFeeAmountIn, mediumFeeAmountIn, lowFeeAmountIn, lowestFeeAmountIn].sort((a, b) => {
        a = a ? a['amountIn'] : BigNumber.from("0")
        b = b ? b['amountIn'] : BigNumber.from("0")
        return a.lt(b) ? -1 : 1
    })[0]

    return bestAmountIn ? bestAmountIn['amountIn'] : BigNumber.from("0")
}