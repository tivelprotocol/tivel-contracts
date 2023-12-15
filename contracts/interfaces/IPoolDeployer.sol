// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface IPoolDeployer {
    function factory() external view returns (address);

    function deployPool(
        address _quoteToken,
        uint256 _interest
    ) external returns (address payable pool);
}
