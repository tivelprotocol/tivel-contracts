// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "../libraries/TransferHelper.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IDEXIntegration.sol";
import "../interfaces/external/IMuteRouter.sol";
import "../base/Lockable.sol";

contract MuteDEXIntegration is IDEXIntegration, Lockable {
    address public immutable router;

    constructor(address _router) {
        router = _router;
    }

    function validatePair(
        address _tokenIn,
        address _tokenOut
    ) external view override returns (bool) {
        address _router = router;
        address pair = IMuteRouter(_router).pairFor(_tokenIn, _tokenOut, false);
        if (pair != address(0)) {
            return true;
        }
        address pairStable = IMuteRouter(_router).pairFor(
            _tokenIn,
            _tokenOut,
            true
        );
        if (pairStable != address(0)) {
            return true;
        }

        return false;
    }

    function _getAmountOut(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) internal view returns (uint256 amountOut, bool stable) {
        (amountOut, stable, ) = IMuteRouter(router).getAmountOut(
            _amountIn,
            _tokenIn,
            _tokenOut
        );
    }

    // function _getAmountIn(
    //     address _tokenIn,
    //     address _tokenOut,
    //     uint256 _amountOut
    // ) internal view returns (uint256 amountIn, bool stable) {
    //     (amountIn, stable,) = IMuteRouter(router).getAmountIn(_amountOut, _tokenIn, _tokenOut);
    // }

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
        // (amountIn,) = _getAmountIn(_tokenIn, _tokenOut, _amountOut);
    }

    function swap(
        address _tokenIn,
        address _tokenOut,
        address _to
    ) external override lock returns (uint256 amountOut) {
        uint256 amountIn = IERC20(_tokenIn).balanceOf(address(this));
        bool stable;
        (amountOut, stable) = _getAmountOut(_tokenIn, _tokenOut, amountIn);
        require(amountOut > 0, "MuteIntegration: INSUFFICIENT_OUTPUT_AMOUNT");

        address _router = router;
        if (IERC20(_tokenIn).allowance(address(this), _router) == 0) {
            TransferHelper.safeApprove(_tokenIn, _router, type(uint256).max);
        }

        uint256 initialBalance = IERC20(_tokenOut).balanceOf(_to);
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        bool[] memory stables = new bool[](1);
        stables[0] = stable;
        IMuteRouter(_router).swapExactTokensForTokens(
            amountIn,
            0,
            path,
            _to,
            block.timestamp,
            stables
        );

        uint256 balance = IERC20(_tokenOut).balanceOf(_to);
        amountOut = balance - initialBalance;
    }
}
