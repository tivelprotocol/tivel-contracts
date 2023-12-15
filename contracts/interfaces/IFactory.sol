// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

interface IFactory {
    function manager() external view returns (address);

    function poolDeployer() external view returns (address);

    function positionStorage() external view returns (address);

    function withdrawalMonitor() external view returns (address);

    function userStorage() external view returns (address);

    function priceFeed() external view returns (address);

    function dexAggregator() external view returns (address);

    function protocolFeeRate() external view returns (uint256);

    function protocolFeeTo() external view returns (address);

    function liquidationFeeRate() external view returns (uint256);

    function liquidationFeeTo() external view returns (address);

    function serviceToken() external view returns (address);

    function serviceFeeTo() external view returns (address);

    function rollbackFee() external view returns (uint256);

    function updateStoplossPriceFee() external view returns (uint256);

    function updateCollateralAmountFee() external view returns (uint256);

    function updateDeadlineFee() external view returns (uint256);

    function minQuoteRate() external view returns (uint256);

    function manualExpiration() external view returns (uint256);

    function operator(address) external view returns (bool);

    function pools(uint256) external view returns (address);

    function poolLength() external view returns (uint256);

    function poolIndex(address) external view returns (uint256);

    function poolByQuoteToken(address) external view returns (address);

    function baseTokenMUT(address) external view returns (uint256);

    function collateralMUT(address) external view returns (uint256);

    function baseTokenLT(address) external view returns (uint256);

    function collateralLT(address) external view returns (uint256);

    function interest(address _quoteToken) external view returns (uint256);
}
