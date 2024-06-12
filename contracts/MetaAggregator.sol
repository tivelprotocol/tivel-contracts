// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "./base/Lockable.sol";
import "./libraries/TransferHelper.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IMetaAggregator.sol";

contract MetaAggregator is IMetaAggregator, Lockable {
    address public manager;
    mapping(address => address) approvalAddress; // default: adapter

    error Forbidden(address sender);
    error ZeroAddress();
    error BadLength();

    event SetManager(address manager);
    event SetApprovalAddress(address adapter, address approvalAddress);
    event Swap(
        address indexed user,
        address indexed adapter,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor(
        address _manager,
        address[] memory _adapters,
        address[] memory _approvalAddresses
    ) {
        if (_adapters.length != _approvalAddresses.length) revert BadLength();
        manager = _manager;
        for (uint256 i = 0; i < _adapters.length; i++) {
            approvalAddress[_adapters[i]] = _approvalAddresses[i];
        }
    }

    modifier onlyManager() {
        if (msg.sender != manager) revert Forbidden(msg.sender);
        _;
    }

    function setManager(address _newManager) external onlyManager {
        if (_newManager == address(0)) revert ZeroAddress();
        manager = _newManager;

        emit SetManager(_newManager);
    }

    function setApprovalAddress(
        address _adapter,
        address _approvalAddress
    ) external onlyManager {
        approvalAddress[_adapter] = _approvalAddress;

        emit SetApprovalAddress(_adapter, _approvalAddress);
    }

    function swap(
        address _tokenIn,
        address _tokenOut,
        uint256 _minAmountOut,
        address _to,
        bytes calldata _data
    ) external override lock returns (uint256 amountOut) {
        (address adapter, bytes memory swapData) = abi.decode(
            _data,
            (address, bytes)
        );
        uint256 amountIn = IERC20(_tokenIn).balanceOf(address(this));

        {
            bool success;
            bytes memory result;
            address approval = approvalAddress[adapter];
            approval = approval != address(0) ? approval : adapter;

            TransferHelper.safeApprove(_tokenIn, approval, amountIn);
            (success, result) = adapter.call(swapData);
            TransferHelper.safeApprove(_tokenIn, approval, 0);

            string memory message;
            if (!success) {
                // Next 8 lines from https://ethereum.stackexchange.com/a/83577
                if (result.length < 68) {
                    message = "MetaAggregator: SWAP_FAILED_SILENTLY";
                } else {
                    assembly {
                        result := add(result, 0x04)
                    }
                    message = abi.decode(result, (string));
                }
            }
            require(success, message);
            amountOut = IERC20(_tokenOut).balanceOf(address(this));
            if (amountOut > 0 && amountOut > _minAmountOut) {
                TransferHelper.safeTransfer(_tokenOut, _to, amountOut);
            }
        }

        emit Swap(
            msg.sender,
            adapter,
            _tokenIn,
            _tokenOut,
            amountIn,
            amountOut
        );
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
