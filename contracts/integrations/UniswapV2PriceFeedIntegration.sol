// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "../interfaces/IPriceFeedIntegration.sol";
import "../interfaces/IERC20.sol";

contract UniswapV2PriceFeedIntegration is IPriceFeedIntegration {
    uint256 public constant override PRECISION = 1e30;
    address public immutable factory;

    constructor(address _factory) {
        factory = _factory;
    }

    function getPrice(
        address _baseToken,
        address _quoteToken
    ) external view override returns (uint256 price) {
        if (_baseToken == _quoteToken) {
            return PRECISION;
        }

        address pair = IUniswapV2Factory(factory).getPair(
            _baseToken,
            _quoteToken
        );
        if (pair != address(0)) {
            address token0 = IUniswapV2Pair(pair).token0();
            (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pair)
                .getReserves();
            (uint256 baseReserve, uint256 quoteReserve) = _baseToken == token0
                ? (reserve0, reserve1)
                : (reserve1, reserve0);
            if (baseReserve > 0)
                price = (quoteReserve * PRECISION) / baseReserve;
        }

        uint256 baseDecimals = IERC20(_baseToken).decimals();
        uint256 quoteDecimals = IERC20(_quoteToken).decimals();
        uint256 basePrec = 10 ** baseDecimals;
        uint256 quotePrec = 10 ** quoteDecimals;
        price = (price * basePrec) / quotePrec;
    }
}
