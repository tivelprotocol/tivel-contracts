// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "./interfaces/IPriceFeedIntegration.sol";
import "./interfaces/IERC20.sol";

contract UniswapV3PriceFeedIntegration is IPriceFeedIntegration {
    uint256 public constant override PRECISION = 1e30;
    address public immutable factory;
    uint24[] public feeTiers = [100, 500, 3000, 10000];

    constructor(address _factory) {
        factory = _factory;
    }

    function getPrice(
        address _baseToken,
        address _quoteToken
    ) external view override returns (uint256 price) {
        uint256 length = feeTiers.length;
        IUniswapV3Factory _factory = IUniswapV3Factory(factory);
        uint256 bestLiquidity;
        (address token0, address token1) = _baseToken < _quoteToken
            ? (_baseToken, _quoteToken)
            : (_quoteToken, _baseToken);
        for (uint256 i = 0; i < length; i++) {
            address poolAddress = _factory.getPool(token0, token1, feeTiers[i]);
            if (poolAddress != address(0)) {
                IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
                uint256 balance0 = IERC20(token0).balanceOf(poolAddress);
                uint256 balance1 = IERC20(token1).balanceOf(poolAddress);
                (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
                uint256 price0 = (uint256(sqrtPriceX96) ** 2 * PRECISION) /
                    (FixedPoint96.Q96 ** 2);
                uint256 liquidity = (balance0 * price0) / PRECISION + balance1;
                if (liquidity > bestLiquidity) {
                    bestLiquidity = liquidity;
                    price = price0;
                }
            }
        }

        if (price != 0 && _baseToken != token0) {
            price = PRECISION ** 2 / price;
        }
    }
}
