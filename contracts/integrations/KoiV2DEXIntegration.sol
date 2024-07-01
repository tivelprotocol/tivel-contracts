// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "../libraries/TransferHelper.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IDEXIntegration.sol";
import "../interfaces/external/IKoiV2Factory.sol";
import "../interfaces/external/IKoiV2Pair.sol";
import "../interfaces/external/IKoiV2Router.sol";
import "../base/Lockable.sol";

contract KoiV2DEXIntegration is IDEXIntegration, Lockable {
    address public immutable factory;
    address public immutable router;

    constructor(address _factory, address _router) {
        factory = _factory;
        router = _router;
    }

    function validatePair(
        address _tokenIn,
        address _tokenOut
    ) external view override returns (bool) {
        if (_tokenIn == _tokenOut) {
            return false;
        }
        address pair = IKoiV2Factory(factory).getPair(
            _tokenIn,
            _tokenOut,
            false
        ); // only volatile pairs now
        if (pair != address(0)) {
            return true;
        }
        return false;
    }

    function _getAmountOutByReserves(
        uint256 _amountIn,
        uint256 _reserveIn,
        uint256 _reserveOut
    ) internal pure returns (uint256 amountOut) {
        amountOut = (_amountIn * _reserveOut) / (_reserveIn + _amountIn);
    }

    function _getAmountInByReserves(
        uint256 _amountOut,
        uint256 _reserveIn,
        uint256 _reserveOut
    ) internal pure returns (uint256 amountIn) {
        amountIn = (_amountOut * _reserveIn) / (_reserveOut - _amountOut);
    }

    function _getAmountOut(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) internal view returns (uint256 amountOut) {
        address pair = IKoiV2Factory(factory).getPair(
            _tokenIn,
            _tokenOut,
            false
        );
        if (pair == address(0)) {
            return 0;
        }

        (uint256 reserve0, uint256 reserve1, ) = IKoiV2Pair(pair).getReserves();
        uint256 pairFee = IKoiV2Pair(pair).pairFee();
        (uint256 reserveIn, uint256 reserveOut) = _tokenIn ==
            IKoiV2Pair(pair).token0()
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
        _amountIn = (_amountIn * (10000 - pairFee)) / 10000;
        amountOut = _getAmountOutByReserves(_amountIn, reserveIn, reserveOut);
    }

    function _getAmountIn(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountOut
    ) internal view returns (uint256 amountIn) {
        address pair = IKoiV2Factory(factory).getPair(
            _tokenIn,
            _tokenOut,
            false
        );
        if (pair == address(0)) {
            return 0;
        }

        (uint256 reserve0, uint256 reserve1, ) = IKoiV2Pair(pair).getReserves();
        uint256 pairFee = IKoiV2Pair(pair).pairFee();
        (uint256 reserveIn, uint256 reserveOut) = _tokenIn ==
            IKoiV2Pair(pair).token0()
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
        amountIn = _getAmountInByReserves(_amountOut, reserveIn, reserveOut);
        amountIn = (amountIn * 10000) / (10000 - pairFee);
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
        require(amountOut > 0, "KoiV2Integration: INSUFFICIENT_OUTPUT_AMOUNT");

        address _router = router;
        if (IERC20(_tokenIn).allowance(address(this), _router) == 0) {
            TransferHelper.safeApprove(_tokenIn, _router, type(uint256).max);
        }

        uint256 initialBalance = IERC20(_tokenOut).balanceOf(_to);
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        bool[] memory stables = new bool[](1);
        stables[0] = false; // only volatile pairs now
        IKoiV2Router(_router).swapExactTokensForTokens(
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
