// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "../libraries/TransferHelper.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IDEXIntegration.sol";
import "../interfaces/IUniswapV3StaticQuoter.sol";
import "../base/Lockable.sol";

contract UniswapV3DEXIntegration is IDEXIntegration, Lockable {
    address public immutable factory;
    address public immutable quoter; // https://github.com/ultimexfi/uniswap-v3-static-quoter
    address public immutable router;
    uint24[] public feeTiers;

    constructor(address _factory, address _quoter, address _router) {
        factory = _factory;
        quoter = _quoter;
        router = _router;
        feeTiers.push(100);
        feeTiers.push(500);
        feeTiers.push(3000);
        feeTiers.push(10000);
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
        uint24[] memory _feeTiers = feeTiers;
        address _factory = factory;
        for (uint8 i = 0; i < _feeTiers.length; i++) {
            address pool = IUniswapV3Factory(_factory).getPool(
                _tokenIn,
                _tokenOut,
                _feeTiers[i]
            );
            if (pool != address(0)) {
                return true;
            }
        }
        return false;
    }

    function _getAmountOut(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) internal view returns (uint256 amountOut, uint24 fee) {
        uint24[] memory _feeTiers = feeTiers;
        address _quoter = quoter;
        for (uint8 i = 0; i < _feeTiers.length; i++) {
            uint256 tempAmountOut;
            try
                IUniswapV3StaticQuoter(_quoter).quoteExactInputSingle(
                    IUniswapV3StaticQuoter.QuoteExactInputSingleParams({
                        tokenIn: _tokenIn,
                        tokenOut: _tokenOut,
                        amountIn: _amountIn,
                        fee: _feeTiers[i],
                        sqrtPriceLimitX96: 0
                    })
                )
            returns (uint256 t) {
                tempAmountOut = t;
            } catch (bytes memory /*lowLevelData*/) {
                tempAmountOut = 0;
            }
            if (tempAmountOut > amountOut) {
                amountOut = tempAmountOut;
                fee = _feeTiers[i];
            }
        }
    }

    function _getAmountIn(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountOut
    ) internal view returns (uint256 amountIn, uint24 fee) {
        uint24[] memory _feeTiers = feeTiers;
        address _quoter = quoter;
        for (uint8 i = 0; i < _feeTiers.length; i++) {
            uint256 tempAmountIn;
            try
                IUniswapV3StaticQuoter(_quoter).quoteExactOutputSingle(
                    IUniswapV3StaticQuoter.QuoteExactOutputSingleParams({
                        tokenIn: _tokenIn,
                        tokenOut: _tokenOut,
                        amount: _amountOut,
                        fee: _feeTiers[i],
                        sqrtPriceLimitX96: 0
                    })
                )
            returns (uint256 t) {
                tempAmountIn = t;
            } catch (bytes memory /*lowLevelData*/) {
                tempAmountIn = 0;
            }
            if (tempAmountIn > 0 && tempAmountIn < amountIn) {
                amountIn = tempAmountIn;
                fee = _feeTiers[i];
            }
        }
    }

    function getAmountOut(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external view override returns (uint256 amountOut) {
        (amountOut, ) = _getAmountOut(_tokenIn, _tokenOut, _amountIn);
    }

    function getAmountIn(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountOut
    ) external view override returns (uint256 amountIn) {
        (amountIn, ) = _getAmountIn(_tokenIn, _tokenOut, _amountOut);
    }

    function swap(
        address _tokenIn,
        address _tokenOut,
        address _to
    ) external override lock returns (uint256 amountOut) {
        uint256 amountIn = IERC20(_tokenIn).balanceOf(address(this));
        uint24 fee;
        (amountOut, fee) = _getAmountOut(_tokenIn, _tokenOut, amountIn);
        require(
            amountOut > 0 && fee > 0,
            "UniswapV3Integration: INSUFFICIENT_OUTPUT_AMOUNT"
        );

        address _router = router;
        if (IERC20(_tokenIn).allowance(address(this), _router) == 0) {
            TransferHelper.safeApprove(_tokenIn, _router, type(uint256).max);
        }

        uint256 initialBalance = IERC20(_tokenOut).balanceOf(_to);
        ISwapRouter(_router).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: fee,
                recipient: _to,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        uint256 balance = IERC20(_tokenOut).balanceOf(_to);
        amountOut = balance - initialBalance;
    }
}
