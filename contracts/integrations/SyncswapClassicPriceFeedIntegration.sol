// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "../interfaces/IPriceFeedIntegration.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/external/ISyncswapFactory.sol";
import "../interfaces/external/ISyncswapPool.sol";

contract SyncswapClassicPriceFeedIntegration is IPriceFeedIntegration {
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

        address pool = ISyncswapFactory(factory).getPool(
            _baseToken,
            _quoteToken
        );
        if (pool != address(0)) {
            address token0 = ISyncswapPool(pool).token0();
            (uint256 reserve0, uint256 reserve1) = ISyncswapPool(pool)
                .getReserves();
            (uint256 baseReserve, uint256 quoteReserve) = _baseToken == token0
                ? (reserve0, reserve1)
                : (reserve1, reserve0);
            if (baseReserve > 0) price = (quoteReserve * PRECISION) / baseReserve;
        }

        uint256 baseDecimals = IERC20(_baseToken).decimals();
        uint256 quoteDecimals = IERC20(_quoteToken).decimals();
        uint256 basePrec = 10 ** baseDecimals;
        uint256 quotePrec = 10 ** quoteDecimals;
        price = (price * basePrec) / quotePrec;
    }
}
