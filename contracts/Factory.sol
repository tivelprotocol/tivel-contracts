// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "./interfaces/IFactory.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IPoolDeployer.sol";

contract Factory is IFactory {
    address public immutable override poolDeployer;
    address public immutable override positionStorage;
    address public immutable override withdrawalMonitor;
    address public override manager;
    address public override userStorage;
    address public override priceFeed;
    address public override dexAggregator;
    address public override protocolFeeTo;
    uint256 public override protocolFeeRate; // 10000 = 100%
    address public override liquidationFeeTo;
    uint256 public override liquidationFeeRate; // 10000 = 100%
    address public override serviceToken;
    address public override serviceFeeTo;
    uint256 public override rollbackFee;
    uint256 public override updateTPnSLFee;
    uint256 public override updateCollateralAmountFee;
    uint256 public override updateDeadlineFee;
    uint256 public override minQuoteRate; // 10000 = 100%
    uint256 public override manualExpiration;
    address[] public override pools;
    mapping(address => bool) public override operator; // only operators (router & monitor) can close trade position
    mapping(address => uint256) public override poolIndex; // poolIndex == 0 => not exist
    mapping(address => address) public override poolByQuoteToken; // poolByQuoteToken == address(0) => not exist
    mapping(address => uint256) public override baseTokenMUT; // max utilization threshold of base tokens // 10000 = 100%
    mapping(address => uint256) public override collateralMUT; // max utilization threshold of collaterals // 10000 = 100%
    mapping(address => uint256) public override baseTokenLT; // liquidation threshold of base tokens // 10000 = 100%
    mapping(address => uint256) public override collateralLT; // liquidation threshold of collaterals // 10000 = 100%
    uint256 constant MIN_MANUAL_EXPIRATION = 24 * 60 * 60; // 24 hours

    error Forbidden(address sender);
    error ZeroAddress();
    error BadLengths(uint256 length0, uint256 length1);
    error TooHighValue(uint256 value, uint256 max);
    error TooLowValue(uint256 value, uint256 min);
    error PoolNotExists(address quoteToken);
    error PoolExistsAlready(address quoteToken, address pool);

    event SetManager(address newManager);
    event SetOperator(address addr, bool isOperator);
    event SetUserStorage(address newUserStorage);
    event SetPriceFeed(address newPriceFeed);
    event SetDEXAggregator(address newDexAggregator);
    event SetProtocolFeeTo(address newProtocolFeeTo);
    event SetProtocolFeeRate(uint256 newProtocolFeeRate);
    event SetLiquidationFeeTo(address newLiquidationFeeTo);
    event SetLiquidationFeeRate(uint256 newLiquidationFeeRate);
    event SetServiceToken(address newServiceToken);
    event SetServiceFeeTo(address newServiceFeeTo);
    event SetRollbackFee(uint256 newRollbackFee);
    event SetUpdateTPnSLFee(uint256 newUpdateTPnSLFee);
    event SetUpdateCollateralAmountFee(uint256 newUpdateCollateralAmountFee);
    event SetUpdateDeadlineFee(uint256 newUpdateDeadlineFee);
    event SetMinQuoteRate(uint256 newMinQuoteRate);
    event SetManualExpiration(uint256 newManualExpiration);
    event SetBaseTokenMUT(address baseToken, uint256 mut);
    event SetCollateralMUT(address baseToken, uint256 mut);
    event SetBaseTokenLT(address baseToken, uint256 lt);
    event SetCollateralLT(address collateral, uint256 lt);
    event CreatePool(
        address indexed quoteToken,
        address indexed pool,
        uint256 interest,
        uint256 index
    );

    constructor(
        address _poolDeployer,
        address _positionStorage,
        address _withdrawalMonitor,
        address _userStorage,
        address _priceFeed,
        address _dexAggregator
    ) {
        poolDeployer = _poolDeployer;
        positionStorage = _positionStorage;
        withdrawalMonitor = _withdrawalMonitor;
        userStorage = _userStorage;
        priceFeed = _priceFeed;
        dexAggregator = _dexAggregator;
        manager = msg.sender;
        minQuoteRate = 10000;
        manualExpiration = MIN_MANUAL_EXPIRATION;
    }

    modifier onlyManager() {
        if (msg.sender != manager) revert Forbidden(msg.sender);
        _;
    }

    function poolLength() external view override returns (uint256) {
        return pools.length;
    }

    function interest(
        address _quoteToken
    ) external view override returns (uint256) {
        address pool = poolByQuoteToken[_quoteToken];
        if (pool == address(0)) return 0;
        return IPool(pool).interest();
    }

    function setManager(address _manager) external onlyManager {
        if (_manager == address(0)) revert ZeroAddress();
        manager = _manager;

        emit SetManager(_manager);
    }

    function setOperator(address _addr, bool _isOperator) external onlyManager {
        operator[_addr] = _isOperator;

        emit SetOperator(_addr, _isOperator);
    }

    function setUserStorage(address _userStorage) external onlyManager {
        if (_userStorage == address(0)) revert ZeroAddress();
        userStorage = _userStorage;

        emit SetUserStorage(_userStorage);
    }

    function setPriceFeed(address _priceFeed) external onlyManager {
        if (_priceFeed == address(0)) revert ZeroAddress();
        priceFeed = _priceFeed;

        emit SetPriceFeed(_priceFeed);
    }

    function setDEXAggregator(address _dexAggregator) external onlyManager {
        if (_dexAggregator == address(0)) revert ZeroAddress();
        dexAggregator = _dexAggregator;

        emit SetDEXAggregator(_dexAggregator);
    }

    function setProtocolFeeTo(address _protocolFeeTo) external onlyManager {
        if (_protocolFeeTo == address(0)) revert ZeroAddress();
        protocolFeeTo = _protocolFeeTo;

        emit SetProtocolFeeTo(_protocolFeeTo);
    }

    function setProtocolFeeRate(uint256 _protocolFeeRate) external onlyManager {
        if (_protocolFeeRate > 10000)
            revert TooHighValue(_protocolFeeRate, 10000);
        protocolFeeRate = _protocolFeeRate;

        emit SetProtocolFeeRate(_protocolFeeRate);
    }

    function setLiquidationFeeTo(
        address _liquidationFeeTo
    ) external onlyManager {
        if (_liquidationFeeTo == address(0)) revert ZeroAddress();
        liquidationFeeTo = _liquidationFeeTo;

        emit SetLiquidationFeeTo(_liquidationFeeTo);
    }

    function setLiquidationFeeRate(
        uint256 _liquidationFeeRate
    ) external onlyManager {
        liquidationFeeRate = _liquidationFeeRate;

        emit SetLiquidationFeeRate(_liquidationFeeRate);
    }

    function setServiceToken(address _serviceToken) external onlyManager {
        serviceToken = _serviceToken;

        emit SetServiceToken(_serviceToken);
    }

    function setServiceFeeTo(address _serviceFeeTo) external onlyManager {
        serviceFeeTo = _serviceFeeTo;

        emit SetServiceFeeTo(_serviceFeeTo);
    }

    function setRollbackFee(uint256 _rollbackFee) external onlyManager {
        rollbackFee = _rollbackFee;

        emit SetRollbackFee(_rollbackFee);
    }

    function setUpdateTPnSLFee(uint256 _updateTPnSLFee) external onlyManager {
        updateTPnSLFee = _updateTPnSLFee;

        emit SetUpdateTPnSLFee(_updateTPnSLFee);
    }

    function setUpdateCollateralAmountFee(
        uint256 _updateCollateralAmountFee
    ) external onlyManager {
        updateCollateralAmountFee = _updateCollateralAmountFee;

        emit SetUpdateCollateralAmountFee(_updateCollateralAmountFee);
    }

    function setUpdateDeadlineFee(
        uint256 _updateDeadlineFee
    ) external onlyManager {
        updateDeadlineFee = _updateDeadlineFee;

        emit SetUpdateDeadlineFee(_updateDeadlineFee);
    }

    function setMinQuoteRate(uint256 _minQuoteRate) external onlyManager {
        if (_minQuoteRate < 10000) revert TooLowValue(_minQuoteRate, 10000);
        minQuoteRate = _minQuoteRate;

        emit SetMinQuoteRate(_minQuoteRate);
    }

    function setManualExpiration(
        uint256 _manualExpiration
    ) external onlyManager {
        if (_manualExpiration < MIN_MANUAL_EXPIRATION)
            revert TooLowValue(_manualExpiration, MIN_MANUAL_EXPIRATION);
        manualExpiration = _manualExpiration;

        emit SetManualExpiration(_manualExpiration);
    }

    function setBaseTokenMUT(
        address[] memory _baseTokens,
        uint256[] memory _muts
    ) external onlyManager {
        if (_baseTokens.length != _muts.length)
            revert BadLengths(_baseTokens.length, _muts.length);
        for (uint256 i = 0; i < _baseTokens.length; i++) {
            if (_muts[i] > 10000) revert TooHighValue(_muts[i], 10000);
            baseTokenMUT[_baseTokens[i]] = _muts[i];

            emit SetBaseTokenMUT(_baseTokens[i], _muts[i]);
        }
    }

    function setCollateralMUT(
        address[] memory _collaterals,
        uint256[] memory _muts
    ) external onlyManager {
        if (_collaterals.length != _muts.length)
            revert BadLengths(_collaterals.length, _muts.length);
        for (uint256 i = 0; i < _collaterals.length; i++) {
            if (_muts[i] > 10000) revert TooHighValue(_muts[i], 10000);
            collateralMUT[_collaterals[i]] = _muts[i];

            emit SetCollateralMUT(_collaterals[i], _muts[i]);
        }
    }

    function setBaseTokenLT(
        address[] memory _baseTokens,
        uint256[] memory _lts
    ) external onlyManager {
        if (_baseTokens.length != _lts.length)
            revert BadLengths(_baseTokens.length, _lts.length);
        for (uint256 i = 0; i < _baseTokens.length; i++) {
            if (_lts[i] > 10000) revert TooHighValue(_lts[i], 10000);
            baseTokenLT[_baseTokens[i]] = _lts[i];

            emit SetBaseTokenLT(_baseTokens[i], _lts[i]);
        }
    }

    function setCollateralLT(
        address[] memory _collaterals,
        uint256[] memory _lts
    ) external onlyManager {
        if (_collaterals.length != _lts.length)
            revert BadLengths(_collaterals.length, _lts.length);
        for (uint256 i = 0; i < _collaterals.length; i++) {
            if (_lts[i] > 10000) revert TooHighValue(_lts[i], 10000);
            collateralLT[_collaterals[i]] = _lts[i];

            emit SetCollateralLT(_collaterals[i], _lts[i]);
        }
    }

    function setPoolInterest(
        address _quoteToken,
        uint256 _interest
    ) external onlyManager {
        address pool = poolByQuoteToken[_quoteToken];
        if (pool == address(0)) revert PoolNotExists(_quoteToken);
        IPool(pool).setInterest(_interest);
    }

    function setPoolMaxBaseReserve(
        address _quoteToken,
        address _baseToken,
        uint256 _maxBaseReserve
    ) external onlyManager {
        address pool = poolByQuoteToken[_quoteToken];
        if (pool == address(0)) revert PoolNotExists(_quoteToken);
        IPool(pool).setMaxBaseReserve(_baseToken, _maxBaseReserve);
    }

    function setPoolMaxCollateralReserve(
        address _quoteToken,
        address _collateral,
        uint256 _maxCollateralReserve
    ) external onlyManager {
        address pool = poolByQuoteToken[_quoteToken];
        if (pool == address(0)) revert PoolNotExists(_quoteToken);
        IPool(pool).setMaxCollateralReserve(_collateral, _maxCollateralReserve);
    }

    function setPoolBaseTokens(
        address _quoteToken,
        address[] memory _baseTokens,
        bool[] memory _tradeables
    ) external onlyManager {
        address pool = poolByQuoteToken[_quoteToken];
        if (pool == address(0)) revert PoolNotExists(_quoteToken);
        IPool(pool).setBaseTokens(_baseTokens, _tradeables);
    }

    function createPool(
        address _quoteToken,
        uint256 _interest
    ) external onlyManager returns (address payable pool) {
        pool = payable(poolByQuoteToken[_quoteToken]);
        if (pool != address(0)) revert PoolExistsAlready(_quoteToken, pool);
        // create pool contract
        pool = IPoolDeployer(poolDeployer).deployPool(_quoteToken, _interest);
        pools.push(pool);
        poolIndex[pool] = pools.length;
        poolByQuoteToken[_quoteToken] = pool;

        emit CreatePool(_quoteToken, pool, _interest, pools.length);
    }
}
