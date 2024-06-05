// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface IWithdrawalMonitor {
    struct WithdrawalRequest {
        uint256 index;
        address owner;
        address quoteToken;
        uint256 liquidity;
        address to;
        bytes data;
    }

    function factory() external view returns (address);

    function requestLength(address) external view returns (uint256);

    function currentIndex(address) external view returns (uint256);

    function request(
        address _pool,
        uint256 _index
    )
        external
        view
        returns (
            uint256 index,
            address owner,
            address quoteToken,
            uint256 liquidity,
            address to,
            bytes calldata data
        );

    function addRequest(
        address _owner,
        address _quoteToken,
        uint256 _liquidity,
        address _to,
        bytes calldata _data
    ) external returns (uint256);

    function updateCallbackResult(
        uint256 _index,
        string memory _result
    ) external;

    function execute(address) external;
}
