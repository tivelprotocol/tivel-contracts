// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "./libraries/PoolAddress.sol";
import "./libraries/TransferHelper.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IPositionStorage.sol";
import "./interfaces/IPriceFeed.sol";
import "./interfaces/IUserStorage.sol";

contract PositionStorage is IPositionStorage {
    uint256 private constant PRICE_PRECISION = 1e30; // should be the same with PriceFeed PRECISION
    uint256 private constant SECONDS_PER_YEAR = 365 * 24 * 60 * 60;
    address public override factory;
    address public poolDeployer;

    uint256 private positionCounter;
    uint256 public override positionLength;
    mapping(uint256 => bytes32) public override positionKeys;
    mapping(bytes32 => uint256) public override positionKeyToIndex;
    mapping(bytes32 => TradePosition) private positions;

    error InitializedAlready();
    error Forbidden(address sender);
    error TradePositionNotExists(bytes32 positionKey);
    error TradePositionClosedAlready(bytes32 positionKey);
    error LiquidationMarkedAlready(bytes32 positionKey);
    error NotManualExpired(bytes32 positionKey);
    error TradePositionNotClosed(bytes32 positionKey);
    error NotOwner(address owner, address updater);
    error Step1NotDone(bytes32 positionKey);
    error NotAllowed(address user);
    error InvalidParameter();
    error BadStoplossPrice(uint256 currentPrice, uint256 stoplossPrice);
    error BadTakeProfitPrice(uint256 currentPrice, uint256 takeProfitPrice);
    error InsufficientServiceFee();

    event OpenTradePosition(bytes32 indexed positionKey);
    event CloseTradePosition(bytes32 indexed positionKey, address updater);
    event LiquidationMark(bytes32 indexed positionKey, uint256 time);
    event CloseManuallyStep1TradePosition(bytes32 indexed positionKey);
    event UpdateTPnSLPrice(
        bytes32 indexed positionKey,
        uint256 newTakeProfitPrice,
        uint256 newStoplossPrice,
        address updater,
        address serviceToken,
        uint256 serviceFee
    );
    event UpdateCollateralAmount(
        bytes32 indexed positionKey,
        uint256 amount,
        uint256 collateralLiqPrice,
        address updater
    );
    event UpdateDeadline(
        bytes32 indexed positionKey,
        uint256 newDeadline,
        address updater
    );

    function setFactory(address _factory) external {
        if (factory != address(0)) revert InitializedAlready();
        factory = _factory;
        poolDeployer = IFactory(_factory).poolDeployer();
    }

    function position(
        bytes32 _positionKey
    ) external view override returns (TradePosition memory) {
        return positions[_positionKey];
    }

    function getMinCollateralAmount(
        OpenTradePositionParams memory _params
    ) external view override returns (uint256) {
        IFactory _factory = IFactory(factory);
        IPriceFeed priceFeed = IPriceFeed(_factory.priceFeed());
        uint256 pricePrecision = PRICE_PRECISION;

        uint256 baseValue;
        {
            uint256 basePrice = priceFeed.getLowestPrice(
                _params.baseToken,
                _params.quoteToken
            );
            baseValue = (_params.baseAmount * basePrice) / pricePrecision;
        }

        uint256 minQuoteRate = _factory.minQuoteRate();
        uint256 baseTokenMUT = _factory.baseTokenMUT(_params.baseToken);
        uint256 collateralMUT = _params.collateral == _params.quoteToken
            ? 10000
            : _factory.collateralMUT(_params.collateral);
        uint256 minCollateralValue = (baseValue *
            (minQuoteRate - baseTokenMUT)) / collateralMUT;

        uint256 collateralPrice = priceFeed.getLowestPrice(
            _params.collateral,
            _params.quoteToken
        );

        return (minCollateralValue * pricePrecision) / collateralPrice;
    }

    function getQuoteAmountRange(
        OpenTradePositionParams memory _params
    )
        external
        view
        override
        returns (uint256 minQuoteAmount, uint256 maxQuoteAmount)
    {
        IFactory _factory = IFactory(factory);
        IPriceFeed priceFeed = IPriceFeed(_factory.priceFeed());
        uint256 pricePrecision = PRICE_PRECISION;

        uint256 baseValue;
        uint256 collateralValue;
        {
            uint256 basePrice = priceFeed.getLowestPrice(
                _params.baseToken,
                _params.quoteToken
            );
            baseValue = (_params.baseAmount * basePrice) / pricePrecision;
            uint256 collateralPrice = priceFeed.getLowestPrice(
                _params.collateral,
                _params.quoteToken
            );
            collateralValue =
                (_params.collateralAmount * collateralPrice) /
                pricePrecision;
        }

        uint256 minQuoteRate = _factory.minQuoteRate();
        uint256 baseTokenMUT = _factory.baseTokenMUT(_params.baseToken);
        uint256 collateralMUT = _params.collateral == _params.quoteToken
            ? 10000
            : _factory.collateralMUT(_params.collateral);

        {
            uint256 minCollateralValue = (baseValue *
                (minQuoteRate - baseTokenMUT)) / collateralMUT;
            if (collateralValue < minCollateralValue) return (0, 0);
        }

        uint256 mutb = (baseValue * baseTokenMUT) / 10000;
        uint256 mutc = (collateralValue * collateralMUT) / 10000;
        minQuoteAmount = (baseValue * minQuoteRate) / 10000;
        maxQuoteAmount = mutb + mutc;
    }

    function _initTradePosition(
        OpenTradePositionParams memory _params
    ) internal pure returns (TradePosition memory) {
        return
            TradePosition({
                positionKey: "",
                owner: _params.owner,
                pool: address(0),
                baseToken: BaseToken({
                    id: _params.baseToken,
                    amount: _params.baseAmount,
                    entryPrice: 0,
                    liqPrice: 0,
                    closePrice: 0
                }),
                quoteToken: QuoteToken({
                    id: _params.quoteToken,
                    amount: _params.quoteAmount
                }),
                collateral: Collateral({
                    id: _params.collateral,
                    amount: _params.collateralAmount,
                    entryPrice: 0,
                    liqPrice: 0,
                    closePrice: 0
                }),
                deadline: _params.deadline,
                stoplossPrice: _params.stoplossPrice,
                takeProfitPrice: _params.takeProfitPrice,
                fee: 0,
                protocolFee: 0,
                status: Status({
                    isClosed: false,
                    isRollbacked: false,
                    isClosedManuallyStep1: false,
                    isClosedManuallyStep2: false
                }),
                closer: address(0),
                liquidationMarkTime: 0
            });
    }

    function _previewTradePosition(
        OpenTradePositionParams memory _params
    ) internal view returns (TradePosition memory pos) {
        if (
            block.timestamp < _params.deadline &&
            _params.baseToken != _params.quoteToken
        ) {
            IFactory _factory = IFactory(factory);
            IPriceFeed priceFeed = IPriceFeed(_factory.priceFeed());
            uint256 pricePrecision = PRICE_PRECISION;

            uint256 baseValue;
            uint256 collateralValue;
            {
                uint256 basePrice = priceFeed.getLowestPrice(
                    _params.baseToken,
                    _params.quoteToken
                );
                if (
                    _params.stoplossPrice >= basePrice ||
                    (_params.takeProfitPrice > 0 &&
                        _params.takeProfitPrice <= basePrice)
                ) return pos;
                baseValue = (_params.baseAmount * basePrice) / pricePrecision;
                uint256 collateralPrice = priceFeed.getLowestPrice(
                    _params.collateral,
                    _params.quoteToken
                );
                collateralValue =
                    (_params.collateralAmount * collateralPrice) /
                    pricePrecision;

                pos = _initTradePosition(_params);
                pos.baseToken.entryPrice = basePrice;
                pos.collateral.entryPrice = collateralPrice;
            }

            uint256 minQuoteRate = _factory.minQuoteRate();
            uint256 baseTokenMUT = _factory.baseTokenMUT(_params.baseToken);
            uint256 collateralMUT = _params.collateral == _params.quoteToken
                ? 10000
                : _factory.collateralMUT(_params.collateral);

            {
                // avoid too deep stack
                // check min collateral value
                uint256 minCollateralValue = (baseValue *
                    (minQuoteRate - baseTokenMUT)) / collateralMUT;
                if (collateralValue < minCollateralValue) return pos;
            }

            uint256 mutb = (baseValue * baseTokenMUT) / 10000;
            {
                // avoid too deep stack
                // check quote amount range
                uint256 minQuoteAmount = (baseValue * minQuoteRate) / 10000;
                uint256 mutc = (collateralValue * collateralMUT) / 10000;
                uint256 maxQuoteAmount = mutb + mutc;
                if (
                    _params.quoteAmount > maxQuoteAmount ||
                    _params.quoteAmount < minQuoteAmount
                ) return pos;
            }

            {
                // avoid too deep stack
                // calculate base token liquidation price
                uint256 baseTokenLT = _factory.baseTokenLT(_params.baseToken);
                pos.baseToken.liqPrice =
                    (mutb * baseTokenLT * pricePrecision) /
                    (_params.baseAmount * baseTokenMUT);
            }

            {
                // avoid too deep stack
                // calculate collateral liquidation price
                uint256 collateralLT = _factory.collateralLT(
                    _params.collateral
                );
                uint256 collateralLiqValue = ((_params.quoteAmount - mutb) *
                    collateralLT) / collateralMUT;
                if (collateralValue < collateralLiqValue) return pos;
                pos.collateral.liqPrice =
                    (collateralLiqValue * pricePrecision) /
                    _params.collateralAmount;
            }

            {
                // avoid too deep stack
                // calculate fees
                uint256 interest = _factory.interest(_params.quoteToken);
                uint256 fee = (_params.quoteAmount *
                    interest *
                    (_params.deadline - block.timestamp)) /
                    (SECONDS_PER_YEAR * 10000);
                IUserStorage userStorage = IUserStorage(_factory.userStorage());
                fee = userStorage.discountedFee(_params.owner, fee);
                uint256 protocolFeeRate = _factory.protocolFeeRate();
                pos.fee = fee;
                pos.protocolFee = (fee * protocolFeeRate) / 10000;
            }

            pos.pool = PoolAddress.computeAddress(
                poolDeployer,
                _params.quoteToken
            ); // a position will be invalid if pool address == address(0)
        }
    }

    function previewTradePosition(
        OpenTradePositionParams memory _params
    ) external view override returns (TradePosition memory) {
        return _previewTradePosition(_params);
    }

    function previewUpdateCollateralAmount(
        UpdateCollateralAmountParams memory _params
    ) external view override returns (uint256 collateralLiqPrice) {
        TradePosition memory pos = positions[_params.positionKey];
        IFactory _factory = IFactory(factory);
        uint256 pricePrecision = PRICE_PRECISION;
        uint256 baseTokenMUT = _factory.baseTokenMUT(pos.baseToken.id);
        uint256 collateralMUT = pos.collateral.id == pos.quoteToken.id
            ? 10000
            : _factory.collateralMUT(pos.collateral.id);
        uint256 newCollateralAmount = pos.collateral.amount + _params.amount;

        uint256 mutb = (pos.baseToken.amount *
            pos.baseToken.entryPrice *
            baseTokenMUT) / (pricePrecision * 10000);

        {
            // avoid too deep stack
            // calculate collateral liquidation price
            uint256 collateralLT = _factory.collateralLT(pos.collateral.id);
            uint256 collateralLiqValue = ((pos.quoteToken.amount - mutb) *
                collateralLT) / collateralMUT;
            collateralLiqPrice =
                (collateralLiqValue * pricePrecision) /
                newCollateralAmount;
        }
    }

    function previewUpdateDeadline(
        UpdateDeadlineParams memory _params
    ) external view override returns (uint256 fee, uint256 protocolFee) {
        TradePosition memory pos = positions[_params.positionKey];

        IFactory _factory = IFactory(factory);
        IUserStorage userStorage = IUserStorage(_factory.userStorage());
        if (_params.deadline >= pos.deadline) {
            uint256 interest = _factory.interest(pos.quoteToken.id);
            fee =
                (pos.quoteToken.amount *
                    interest *
                    (_params.deadline - pos.deadline)) /
                (SECONDS_PER_YEAR * 10000);
            fee = userStorage.discountedFee(pos.owner, fee);
            uint256 protocolFeeRate = _factory.protocolFeeRate();
            protocolFee = (fee * protocolFeeRate) / 10000;
        }
    }

    function _canLiquidate(bytes32 _positionKey) internal view returns (bool) {
        TradePosition memory pos = positions[_positionKey];
        if (pos.status.isClosed) return false;
        if (pos.deadline <= block.timestamp) return true;
        IFactory _factory = IFactory(factory);
        IPriceFeed priceFeed = IPriceFeed(_factory.priceFeed());
        uint256 collateralPrice = priceFeed.getLowestPrice(
            pos.collateral.id,
            pos.quoteToken.id
        );
        if (collateralPrice <= pos.collateral.liqPrice) return true;
        uint256 basePrice = priceFeed.getLowestPrice(
            pos.baseToken.id,
            pos.quoteToken.id
        );
        if (
            (pos.stoplossPrice > 0 && basePrice <= pos.stoplossPrice) ||
            (pos.takeProfitPrice > 0 && basePrice >= pos.takeProfitPrice) ||
            basePrice <= pos.baseToken.liqPrice
        ) return true;

        return false;
    }

    function canLiquidate(
        bytes32 _positionKey
    ) external view override returns (bool) {
        return _canLiquidate(_positionKey);
    }

    function canLiquidationMark(
        bytes32 _positionKey
    ) external view override returns (bool) {
        return
            _canLiquidate(_positionKey) &&
            positions[_positionKey].liquidationMarkTime == 0;
    }

    function openTradePosition(
        TradePosition memory _pos
    ) external override returns (bytes32 positionKey) {
        if (
            msg.sender !=
            PoolAddress.computeAddress(poolDeployer, _pos.quoteToken.id)
        ) revert Forbidden(msg.sender);

        positionKey = keccak256(abi.encodePacked(this, positionCounter++));
        _pos.positionKey = positionKey;
        positions[positionKey] = _pos;
        positionLength++;
        positionKeys[positionLength] = positionKey;
        positionKeyToIndex[positionKey] = positionLength;

        emit OpenTradePosition(_pos.positionKey);
    }

    function _popOpeningPosition(bytes32 _positionKey) internal {
        uint256 index = positionKeyToIndex[_positionKey];
        uint256 lastIndex = positionLength;
        if (index != lastIndex) {
            bytes32 lastPositionKey = positionKeys[lastIndex];
            positionKeys[index] = lastPositionKey;
            positionKeyToIndex[lastPositionKey] = index;
        }
        positionLength--;
        delete positionKeys[lastIndex];
        delete positionKeyToIndex[_positionKey];
    }

    function updateStatus(
        bytes32 _positionKey,
        address _updater
    ) external override returns (bool needLiquidate) {
        TradePosition storage pos = positions[_positionKey];

        if (
            msg.sender !=
            PoolAddress.computeAddress(poolDeployer, pos.quoteToken.id)
        ) revert Forbidden(msg.sender);

        if (pos.status.isClosed)
            revert TradePositionClosedAlready(_positionKey);

        needLiquidate = _canLiquidate(_positionKey);

        if (_updater != pos.owner && !needLiquidate)
            revert NotOwner(pos.owner, _updater);
        pos.status.isClosed = true;
        pos.closer = _updater;

        // remove position from opening list
        _popOpeningPosition(pos.positionKey);

        emit CloseTradePosition(_positionKey, _updater);
    }

    function liquidationMark(bytes32 _positionKey) external override {
        TradePosition storage pos = positions[_positionKey];

        if (pos.status.isClosed)
            revert TradePositionClosedAlready(_positionKey);
        if (pos.liquidationMarkTime > 0)
            revert LiquidationMarkedAlready(_positionKey);

        uint256 time = block.timestamp;
        if (_canLiquidate(_positionKey)) {
            pos.liquidationMarkTime = time;
            emit LiquidationMark(_positionKey, time);
        }
    }

    function rollback(
        bytes32 _positionKey,
        address _updater
    ) external override {
        TradePosition storage pos = positions[_positionKey];

        if (
            msg.sender !=
            PoolAddress.computeAddress(poolDeployer, pos.quoteToken.id)
        ) revert Forbidden(msg.sender);

        if (pos.status.isClosed)
            revert TradePositionClosedAlready(_positionKey);

        if (_updater != pos.owner) revert NotOwner(pos.owner, _updater);
        pos.status.isClosed = true;
        pos.status.isRollbacked = true;
        pos.closer = _updater;

        // remove position from opening list
        _popOpeningPosition(pos.positionKey);

        emit CloseTradePosition(_positionKey, _updater);
    }

    function closeManuallyStep1(bytes32 _positionKey) external override {
        TradePosition storage pos = positions[_positionKey];

        if (
            msg.sender !=
            PoolAddress.computeAddress(poolDeployer, pos.quoteToken.id)
        ) revert Forbidden(msg.sender);

        if (pos.status.isClosed)
            revert TradePositionClosedAlready(_positionKey);

        IFactory _factory = IFactory(factory);
        if (
            block.timestamp <
            pos.liquidationMarkTime + _factory.manualExpiration()
        ) revert NotManualExpired(_positionKey);

        pos.status.isClosedManuallyStep1 = true;

        emit CloseManuallyStep1TradePosition(_positionKey);
    }

    function closeManuallyStep2(bytes32 _positionKey) external override {
        TradePosition storage pos = positions[_positionKey];

        if (
            msg.sender !=
            PoolAddress.computeAddress(poolDeployer, pos.quoteToken.id)
        ) revert Forbidden(msg.sender);

        if (pos.status.isClosed)
            revert TradePositionClosedAlready(_positionKey);

        if (!pos.status.isClosedManuallyStep1)
            revert Step1NotDone(_positionKey);

        pos.status.isClosed = true;
        pos.status.isClosedManuallyStep2 = true;

        // remove position from opening list
        _popOpeningPosition(pos.positionKey);

        emit CloseTradePosition(_positionKey, address(0));
    }

    function updateCloseValues(
        bytes32 _positionKey,
        uint256 _baseValue,
        uint256 _loss,
        uint256 _remainingCollateralAmount
    ) external override {
        TradePosition storage pos = positions[_positionKey];

        if (
            msg.sender !=
            PoolAddress.computeAddress(poolDeployer, pos.quoteToken.id)
        ) revert Forbidden(msg.sender);

        if (!pos.status.isClosed) revert TradePositionNotClosed(_positionKey);
        uint256 pricePrecision = PRICE_PRECISION;

        pos.baseToken.closePrice =
            (_baseValue * pricePrecision) /
            pos.baseToken.amount;

        if (_loss > 0) {
            uint256 liquidatedCollateralAmount = pos.collateral.amount -
                _remainingCollateralAmount;
            pos.collateral.closePrice =
                (_loss * pricePrecision) /
                liquidatedCollateralAmount;
        }
    }

    function updateTPnSL(UpdateTPnSLParams memory _params) external override {
        IFactory _factory = IFactory(factory);
        if (!_factory.operator(msg.sender)) revert Forbidden(msg.sender);

        TradePosition storage pos = positions[_params.positionKey];

        if (pos.status.isClosed)
            revert TradePositionClosedAlready(_params.positionKey);

        if (_params.updater != pos.owner)
            revert NotOwner(pos.owner, _params.updater);

        IPriceFeed priceFeed = IPriceFeed(_factory.priceFeed());
        uint256 basePrice = priceFeed.getLowestPrice(
            pos.baseToken.id,
            pos.quoteToken.id
        );

        if (_params.takeProfitPrice > 0 && _params.takeProfitPrice <= basePrice)
            revert BadTakeProfitPrice(basePrice, _params.takeProfitPrice);
        if (_params.stoplossPrice >= basePrice)
            revert BadStoplossPrice(basePrice, _params.stoplossPrice);

        pos.takeProfitPrice = _params.takeProfitPrice;
        pos.stoplossPrice = _params.stoplossPrice;

        emit UpdateTPnSLPrice(
            _params.positionKey,
            _params.takeProfitPrice,
            _params.stoplossPrice,
            _params.updater,
            _params.serviceToken,
            _params.serviceFee
        );
    }

    function updateCollateralAmount(
        UpdateCollateralAmountParams memory _params
    ) external override returns (uint256 collateralLiqPrice) {
        TradePosition storage pos = positions[_params.positionKey];

        if (
            msg.sender !=
            PoolAddress.computeAddress(poolDeployer, pos.quoteToken.id)
        ) revert Forbidden(msg.sender);

        if (pos.status.isClosed)
            revert TradePositionClosedAlready(_params.positionKey);

        if (_params.updater != pos.owner)
            revert NotOwner(pos.owner, _params.updater);
        IFactory _factory = IFactory(factory);
        uint256 pricePrecision = PRICE_PRECISION;
        uint256 baseTokenMUT = _factory.baseTokenMUT(pos.baseToken.id);
        uint256 collateralMUT = _factory.collateralMUT(pos.collateral.id);
        uint256 newCollateralAmount = pos.collateral.amount + _params.amount;

        uint256 mutb = (pos.baseToken.amount *
            pos.baseToken.entryPrice *
            baseTokenMUT) / (pricePrecision * 10000);

        {
            // avoid too deep stack
            // calculate collateral liquidation price
            uint256 collateralLT = _factory.collateralLT(pos.collateral.id);
            uint256 collateralLiqValue = ((pos.quoteToken.amount - mutb) *
                collateralLT) / collateralMUT;
            collateralLiqPrice =
                (collateralLiqValue * pricePrecision) /
                newCollateralAmount;
            pos.collateral.amount = newCollateralAmount;
            pos.collateral.liqPrice = collateralLiqPrice;
        }

        emit UpdateCollateralAmount(
            _params.positionKey,
            _params.amount,
            collateralLiqPrice,
            _params.updater
        );
    }

    function updateDeadline(
        UpdateDeadlineParams memory _params
    ) external override returns (uint256 fee, uint256 protocolFee) {
        TradePosition storage pos = positions[_params.positionKey];

        if (
            msg.sender !=
            PoolAddress.computeAddress(poolDeployer, pos.quoteToken.id)
        ) revert Forbidden(msg.sender);

        if (pos.status.isClosed)
            revert TradePositionClosedAlready(_params.positionKey);

        if (_params.updater != pos.owner)
            revert NotOwner(pos.owner, _params.updater);
        IFactory _factory = IFactory(factory);
        IUserStorage userStorage = IUserStorage(_factory.userStorage());
        bool canUpdateDeadline = userStorage.canUpdateDeadline(_params.updater);
        if (!canUpdateDeadline) revert NotAllowed(_params.updater);
        if (_params.deadline <= pos.deadline) revert InvalidParameter();

        uint256 interest = _factory.interest(pos.quoteToken.id);
        fee =
            (pos.quoteToken.amount *
                interest *
                (_params.deadline - pos.deadline)) /
            (SECONDS_PER_YEAR * 10000);
        fee = userStorage.discountedFee(pos.owner, fee);
        uint256 protocolFeeRate = _factory.protocolFeeRate();
        protocolFee = (fee * protocolFeeRate) / 10000;

        pos.quoteToken.amount += fee;
        pos.fee += fee;
        pos.protocolFee += protocolFee;
        pos.deadline = _params.deadline;

        emit UpdateDeadline(
            _params.positionKey,
            _params.deadline,
            _params.updater
        );
    }
}
