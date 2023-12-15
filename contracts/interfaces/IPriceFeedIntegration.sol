// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface IPriceFeedIntegration {
    function PRECISION() external view returns (uint256);
    
    function getPrice(
        address _baseToken,
        address _quoteToken
    ) external view returns (uint256);
}
