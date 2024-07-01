// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "./libraries/TransferHelper.sol";
import "./interfaces/IDEXIntegration.sol";
import "./interfaces/IDEXAggregator.sol";
import "./interfaces/IERC20.sol";
import "./base/Lockable.sol";

contract DEXAggregatorV2 is Lockable, IDEXAggregator {
    address public manager;
    address[] public override dexes;
    string[] public override dexNames;
    mapping(address => uint256) public override dexIndex;
    mapping(address => mapping(address => address)) public bridgeToken;

    error Forbidden(address sender);
    error ZeroAddress();
    error DEXNotExists(address dex);
    error DEXExistsAlready(address dex);
    error BadLength();
    error InsufficientOutput();

    event SetManager(address manager);
    event AddDEX(address indexed user, address indexed dex, string dexName);
    event RemoveDEX(address indexed user, address indexed dex, string dexName);
    event SetBridgeToken(
        address indexed tokenIn,
        address indexed tokenOut,
        address bridgeToken
    );
    event Swap(
        address indexed user,
        address indexed to,
        address indexed dex,
        address _tokenIn,
        address _tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor() {
        manager = msg.sender;
    }

    modifier onlyManager() {
        if (msg.sender != manager) revert Forbidden(msg.sender);
        _;
    }

    function _validateDEX(address _dex) internal view returns (uint256 idx) {
        idx = dexIndex[_dex];
        if (idx == 0) revert DEXNotExists(_dex);
    }

    function dexLength() external view override returns (uint256) {
        return dexes.length;
    }

    function setManager(address _newManager) external onlyManager {
        if (msg.sender == address(0)) revert ZeroAddress();
        manager = _newManager;

        emit SetManager(_newManager);
    }

    function setBridgeToken(
        address _tokenIn,
        address _tokenOut,
        address _bridgeToken
    ) external onlyManager {
        bridgeToken[_tokenIn][_tokenOut] = _bridgeToken;

        emit SetBridgeToken(_tokenIn, _tokenOut, _bridgeToken);
    }

    function addDEX(address _dex, string memory _dexName) external onlyManager {
        if (dexIndex[_dex] != 0) revert DEXExistsAlready(_dex);
        dexes.push(_dex);
        dexNames.push(_dexName);
        dexIndex[_dex] = dexes.length;

        emit AddDEX(msg.sender, _dex, _dexName);
    }

    function removeDEX(address _dex) external onlyManager {
        uint256 idx = _validateDEX(_dex);
        uint256 length = dexes.length;
        string memory dexName = dexNames[idx - 1];
        if (idx < length) {
            dexIndex[dexes[length - 1]] = idx;
            dexes[idx - 1] = dexes[length - 1];
            dexNames[idx - 1] = dexNames[length - 1];
        }
        dexes.pop();
        dexNames.pop();
        dexIndex[_dex] = 0;

        emit RemoveDEX(msg.sender, _dex, dexName);
    }

    function _getAmountOut(
        address _dex,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) internal view returns (uint256 amountOut, address dex) {
        if (_tokenIn == _tokenOut) {
            amountOut = _amountIn;
            dex = _dex;
        } else {
            if (_dex == address(0)) {
                uint256 length = dexes.length;
                for (uint256 i = 0; i < length; i++) {
                    {
                        uint256 _amountOut = IDEXIntegration(dexes[i])
                            .getAmountOut(_tokenIn, _tokenOut, _amountIn);
                        if (_amountOut > amountOut) {
                            amountOut = _amountOut; // choose the better
                            dex = dexes[i];
                        }
                    }
                }
            } else {
                amountOut = IDEXIntegration(_dex).getAmountOut(
                    _tokenIn,
                    _tokenOut,
                    _amountIn
                );
                dex = _dex;
            }
        }
    }

    function _getAmountIn(
        address _dex,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountOut
    ) internal view returns (uint256 amountIn, address dex) {
        if (_tokenIn == _tokenOut) {
            amountIn = _amountOut;
            dex = _dex;
        } else {
            if (_dex == address(0)) {
                uint256 length = dexes.length;
                for (uint256 i = 0; i < length; i++) {
                    {
                        uint256 _amountIn = IDEXIntegration(dexes[i])
                            .getAmountIn(_tokenIn, _tokenOut, _amountOut);
                        if (
                            amountIn == 0 ||
                            (_amountIn > 0 && _amountIn < amountIn)
                        ) {
                            amountIn = _amountIn; // choose the better
                            dex = dexes[i];
                        }
                    }
                }
            } else {
                amountIn = IDEXIntegration(_dex).getAmountIn(
                    _tokenIn,
                    _tokenOut,
                    _amountOut
                );
                dex = _dex;
            }
        }
    }

    function validatePair(
        address _dex,
        address _tokenIn,
        address _tokenOut
    ) external view override returns (bool) {
        if (_dex == address(0)) {
            uint256 length = dexes.length;
            for (uint256 i = 0; i < length; i++) {
                if (
                    IDEXIntegration(dexes[i]).validatePair(_tokenIn, _tokenOut)
                ) {
                    return true;
                }
            }
        } else {
            return IDEXIntegration(_dex).validatePair(_tokenIn, _tokenOut);
        }
        return false;
    }

    function getAmountOut(
        address /* _dex */,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external view override returns (uint256 amountOut, address dex) {
        dex = address(0);
        address[] memory path;
        address bridge = bridgeToken[_tokenIn][_tokenOut];
        if (bridge == address(0)) {
            path = new address[](2);
            path[0] = _tokenIn;
            path[1] = _tokenOut;
        } else {
            path = new address[](3);
            path[0] = _tokenIn;
            path[1] = bridge;
            path[2] = _tokenOut;
        }
        (uint256[] memory amounts, ) = _getAmountOuts(path, _amountIn);
        amountOut = amounts[amounts.length - 1];
    }

    function getAmountIn(
        address /* _dex */,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountOut
    ) external view override returns (uint256 amountIn, address dex) {
        dex = address(0);
        address[] memory path;
        address bridge = bridgeToken[_tokenIn][_tokenOut];
        if (bridge == address(0)) {
            path = new address[](2);
            path[0] = _tokenIn;
            path[1] = _tokenOut;
        } else {
            path = new address[](3);
            path[0] = _tokenIn;
            path[1] = bridge;
            path[2] = _tokenOut;
        }
        (uint256[] memory amounts, ) = _getAmountIns(path, _amountOut);
        amountIn = amounts[0];
    }

    function _getAmountOuts(
        address[] memory _path,
        uint256 _amountIn
    )
        internal
        view
        returns (uint256[] memory amounts, address[] memory dexes_)
    {
        if (_path.length < 2) revert BadLength();
        amounts = new uint256[](_path.length);
        dexes_ = new address[](_path.length - 1);
        amounts[0] = _amountIn;
        for (uint256 i; i < _path.length - 1; i++) {
            (amounts[i + 1], dexes_[i]) = _getAmountOut(
                address(0),
                _path[i],
                _path[i + 1],
                amounts[i]
            );
        }
    }

    function _getAmountIns(
        address[] memory _path,
        uint256 _amountOut
    )
        internal
        view
        returns (uint256[] memory amounts, address[] memory dexes_)
    {
        if (_path.length < 2) revert BadLength();
        amounts = new uint256[](_path.length);
        dexes_ = new address[](_path.length - 1);
        amounts[amounts.length - 1] = _amountOut;
        for (uint256 i = _path.length - 1; i > 0; i--) {
            (amounts[i - 1], dexes_[i - 1]) = _getAmountIn(
                address(0),
                _path[i - 1],
                _path[i],
                amounts[i]
            );
        }
    }

    function _swap(
        address[] memory _dexes,
        address[] memory _path,
        uint256 _amountIn,
        address _to
    ) internal returns (uint256 amountOut) {
        TransferHelper.safeTransfer(_path[0], _dexes[0], _amountIn);
        for (uint256 i; i < _path.length - 1; i++) {
            address to = i == _path.length - 2 ? _to : _dexes[i + 1];
            amountOut = IDEXIntegration(_dexes[i]).swap(
                _path[i],
                _path[i + 1],
                to
            );
        }
    }

    function swap(
        address /* _dex */,
        address _tokenIn,
        address _tokenOut,
        uint256 _minAmountOut,
        address _to
    ) external override lock returns (uint256 amountOut, address dex) {
        dex = address(0);
        // receive input token
        uint256 amountIn = IERC20(_tokenIn).balanceOf(address(this));
        if (_tokenIn == _tokenOut) {
            amountOut = amountIn;
            // send output token
            TransferHelper.safeTransfer(_tokenOut, _to, amountOut);
        } else {
            address[] memory path;
            address bridge = bridgeToken[_tokenIn][_tokenOut];
            if (bridge == address(0)) {
                path = new address[](2);
                path[0] = _tokenIn;
                path[1] = _tokenOut;
            } else {
                path = new address[](3);
                path[0] = _tokenIn;
                path[1] = bridge;
                path[2] = _tokenOut;
            }
            // swap
            (, address[] memory _dexes) = _getAmountOuts(path, amountIn);
            amountOut = _swap(_dexes, path, amountIn, address(this));
            if (amountOut < _minAmountOut) revert InsufficientOutput();

            // send output token
            TransferHelper.safeTransfer(_tokenOut, _to, amountOut);

            emit Swap(
                msg.sender,
                _to,
                address(0),
                _tokenIn,
                _tokenOut,
                amountIn,
                amountOut
            );
        }
    }

    function rescueFunds(
        address _token,
        address _to
    ) external lock onlyManager {
        TransferHelper.safeTransfer(
            _token,
            _to,
            IERC20(_token).balanceOf(address(this))
        );
    }
}
