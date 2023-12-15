// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

// helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true/false
library TransferHelper {
    function safeApprove(address _token, address _to, uint256 _value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = _token.call(
            abi.encodeWithSelector(0x095ea7b3, _to, _value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper::safeApprove: approve failed"
        );
    }

    function safeTransfer(
        address _token,
        address _to,
        uint256 _value
    ) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = _token.call(
            abi.encodeWithSelector(0xa9059cbb, _to, _value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper::safeTransfer: transfer failed"
        );
    }

    function safeTransferFrom(
        address _token,
        address _from,
        address _to,
        uint256 _value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = _token.call(
            abi.encodeWithSelector(0x23b872dd, _from, _to, _value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper::transferFrom: transferFrom failed"
        );
    }

    function safeTransferETH(address _to, uint256 _value) internal {
        (bool success, ) = _to.call{value: _value}(new bytes(0));
        require(
            success,
            "TransferHelper::safeTransferETH: ETH transfer failed"
        );
    }
}
