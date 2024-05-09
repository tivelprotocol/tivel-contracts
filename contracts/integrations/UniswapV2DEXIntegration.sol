// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "../libraries/TransferHelper.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IDEXIntegration.sol";
import "../base/Lockable.sol";

contract UniswapV2DEXIntegration is IDEXIntegration, Lockable {
    address public immutable factory;
    address public immutable router;

    constructor(address _factory, address _router) {
        factory = _factory;
        router = _router;
    }

    function _sortTokens(
        address _tokenA,
        address _tokenB
    ) internal pure returns (address token0, address token1) {
        if (
            _tokenA != _tokenB && _tokenA != address(0) && _tokenB != address(0)
        ) {
            (token0, token1) = _tokenA < _tokenB
                ? (_tokenA, _tokenB)
                : (_tokenB, _tokenA);
        }
    }

    function validatePair(
        address _tokenIn,
        address _tokenOut
    ) external view override returns (bool) {
        if (_tokenIn == _tokenOut) {
            return false;
        }
        address pair = IUniswapV2Factory(factory).getPair(_tokenIn, _tokenOut);
        if (pair != address(0)) {
            return true;
        }
        return false;
    }

    function _getAmountOut(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) internal view returns (uint256 amountOut) {
        address pair = IUniswapV2Factory(factory).getPair(_tokenIn, _tokenOut);
        if (pair == address(0)) {
            return 0;
        }

        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pair)
            .getReserves();
        (uint256 reserveIn, uint256 reserveOut) = _tokenIn ==
            IUniswapV2Pair(pair).token0()
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
        try
            IUniswapV2Router02(router).getAmountOut(
                _amountIn,
                reserveIn,
                reserveOut
            )
        returns (uint256 t) {
            amountOut = t;
        } catch (bytes memory /*lowLevelData*/) {
            amountOut = 0;
        }
    }

    function _getAmountIn(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountOut
    ) internal view returns (uint256 amountIn) {
        address pair = IUniswapV2Factory(factory).getPair(_tokenIn, _tokenOut);
        if (pair == address(0)) {
            return 0;
        }

        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pair)
            .getReserves();
        (uint256 reserveIn, uint256 reserveOut) = _tokenIn ==
            IUniswapV2Pair(pair).token0()
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
        try
            IUniswapV2Router02(router).getAmountIn(
                _amountOut,
                reserveIn,
                reserveOut
            )
        returns (uint256 t) {
            amountIn = t;
        } catch (bytes memory /*lowLevelData*/) {
            amountIn = 0;
        }
    }

    function getAmountOut(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external view override returns (uint256 amountOut) {
        return _getAmountOut(_tokenIn, _tokenOut, _amountIn);
    }

    function getAmountIn(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountOut
    ) external view override returns (uint256 amountIn) {
        return _getAmountIn(_tokenIn, _tokenOut, _amountOut);
    }

    function swap(
        address _tokenIn,
        address _tokenOut,
        address _to
    ) external override lock returns (uint256 amountOut) {
        uint256 amountIn = IERC20(_tokenIn).balanceOf(address(this));
        amountOut = _getAmountOut(_tokenIn, _tokenOut, amountIn);
        require(
            amountOut > 0,
            "UniswapV2Integration: INSUFFICIENT_OUTPUT_AMOUNT"
        );

        address _router = router;
        if (IERC20(_tokenIn).allowance(address(this), _router) == 0) {
            TransferHelper.safeApprove(_tokenIn, _router, type(uint256).max);
        }

        uint256 initialBalance = IERC20(_tokenOut).balanceOf(_to);
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        IUniswapV2Router02(_router).swapExactTokensForTokens(
            amountIn,
            amountOut,
            path,
            _to,
            block.timestamp
        );

        uint256 balance = IERC20(_tokenOut).balanceOf(_to);
        amountOut = balance - initialBalance;
    }
}
