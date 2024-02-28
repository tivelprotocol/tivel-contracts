// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "../libraries/TransferHelper.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IDEXIntegration.sol";
import "../interfaces/external/ISyncswapFactory.sol";
import "../interfaces/external/ISyncswapPool.sol";
import "../base/Lockable.sol";

contract SyncswapStableDEXIntegration is IDEXIntegration, Lockable {
    address public immutable factory;

    constructor(address _factory) {
        factory = _factory;
    }

    function _getPair(
        address _tokenIn,
        address _tokenOut
    ) internal view returns (address) {
        return ISyncswapFactory(factory).getPool(_tokenIn, _tokenOut);
    }

    function validatePair(
        address _tokenIn,
        address _tokenOut
    ) external view override returns (bool) {
        if (_tokenIn == _tokenOut) {
            return false;
        }
        address pool = _getPair(_tokenIn, _tokenOut);
        if (pool != address(0)) {
            return true;
        }
        return false;
    }

    function _getAmountOut(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) internal view returns (uint256 amountOut) {
        address pool = _getPair(_tokenIn, _tokenOut);
        if (pool != address(0)) {
            amountOut = ISyncswapPool(pool).getAmountOut(
                _tokenIn,
                _amountIn,
                address(this)
            );
        }
    }

    function _getAmountIn(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountOut
    ) internal view returns (uint256 amountIn) {
        address pool = _getPair(_tokenIn, _tokenOut);
        if (pool != address(0)) {
            amountIn = ISyncswapPool(pool).getAmountIn(
                _tokenOut,
                _amountOut,
                address(this)
            );
        }
    }

    function getAmountOut(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external view override returns (uint256 amountOut) {
        amountOut = _getAmountOut(_tokenIn, _tokenOut, _amountIn);
    }

    function getAmountIn(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountOut
    ) external view override returns (uint256 amountIn) {
        amountIn = _getAmountIn(_tokenIn, _tokenOut, _amountOut);
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
            "SyncswapStableIntegration: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        address pair = _getPair(_tokenIn, _tokenOut);
        require(pair != address(0), "SyncswapStableIntegration: INVALID_PAIR");
        TransferHelper.safeTransfer(_tokenIn, pair, amountIn);

        uint256 initialBalance = IERC20(_tokenOut).balanceOf(_to);
        bytes memory data = abi.encode(_tokenIn, _to, 2);
        ISyncswapPool(pair).swap(data, msg.sender, address(0), "");

        uint256 balance = IERC20(_tokenOut).balanceOf(_to);
        amountOut = balance - initialBalance;
    }
}
