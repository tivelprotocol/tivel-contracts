// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "./interfaces/IERC20.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IPositionStorage.sol";
import "./interfaces/IPriceFeed.sol";
import "./interfaces/IUserStorage.sol";

contract PositionStorage is IPositionStorage {
    address public override factory;

    TradePosition[] public positions;
    bytes32[] public openingPositionKeys;
    mapping(bytes32 => uint256) public override positionIndex;
    mapping(address => bytes32[]) private positionKeysByUser;

    error InitializedAlready();
    error Forbidden(address sender);
    error TradePositionNotExists(bytes32 positionKey);
    error TradePositionClosedAlready(bytes32 positionKey);
    error TradePositionNotClosed(bytes32 positionKey);
    error NotOwner(address owner, address updater);
    error Step1NotDone(bytes32 positionKey);
    error NotAllowed(address user);
    error InvalidParameter();

    event OpenTradePosition(bytes32 indexed positionKey);
    event CloseTradePosition(bytes32 indexed positionKey, address updater);
    event CloseManuallyStep1TradePosition(bytes32 indexed positionKey);
    event UpdateStoplossPrice(
        bytes32 indexed positionKey,
        uint256 newStoplossPrice,
        address updater
    );
    event UpdateCollateralAmount(
        bytes32 indexed positionKey,
        uint256 amount,
        uint256 collateralLiqPrice,
        uint256 baseLiqPrice,
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
    }

    function position(
        uint256 _index
    ) external view override returns (TradePosition memory) {
        return positions[_index];
    }

    function positionByKey(
        bytes32 _positionKey
    ) external view override returns (TradePosition memory pos) {
        uint256 idx = positionIndex[_positionKey];
        if (idx > 0) {
            pos = positions[idx];
        }
    }

    function openingPositionKey(
        uint256 _index
    ) external view override returns (bytes32) {
        return openingPositionKeys[_index];
    }

    function positionLength() external view override returns (uint256) {
        return positions.length;
    }

    function openingPositionLength() external view override returns (uint256) {
        return openingPositionKeys.length;
    }

    function userPositionLength(
        address _user
    ) external view override returns (uint256) {
        return positionKeysByUser[_user].length;
    }

    function positionKeyByUser(
        address _user,
        uint256 _index
    ) external view override returns (bytes32) {
        return positionKeysByUser[_user][_index];
    }

    function getMinCollateralAmount(
        OpenTradePositionParams memory _params
    ) external view override returns (uint256) {
        IFactory _factory = IFactory(factory);
        IPriceFeed priceFeed = IPriceFeed(_factory.priceFeed());
        uint256 pricePrecision = priceFeed.PRECISION();

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
        uint256 collateralMUT = _factory.collateralMUT(_params.collateral);
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
        uint256 pricePrecision = priceFeed.PRECISION();

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
        uint256 collateralMUT = _factory.collateralMUT(_params.collateral);
        uint256 collateralPrice = priceFeed.getLowestPrice(
            _params.collateral,
            _params.quoteToken
        );

        {
            uint256 minCollateralValue = (baseValue *
                (minQuoteRate - baseTokenMUT)) / collateralMUT;
            uint256 minCollateralAmount = (minCollateralValue *
                pricePrecision) / collateralPrice;
            if (_params.collateralAmount < minCollateralAmount) return (0, 0);
        }

        uint256 mutc = (_params.collateralAmount *
            collateralPrice *
            collateralMUT) / (pricePrecision * 10000);
        minQuoteAmount = (baseValue * minQuoteRate) / 10000;
        maxQuoteAmount = mutc + (baseValue * baseTokenMUT) / 10000;
    }

    function _initTradePosition(
        OpenTradePositionParams memory _params,
        uint256 _basePrice
    ) internal pure returns (TradePosition memory) {
        return
            TradePosition({
                positionKey: "",
                owner: _params.owner,
                pool: address(0),
                baseToken: BaseToken({
                    id: _params.baseToken,
                    amount: _params.baseAmount,
                    entryPrice: _basePrice,
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
                fee: 0,
                protocolFee: 0,
                status: Status({
                    isClosed: false,
                    isExpired: false,
                    isStoploss: false,
                    isBaseLiquidated: false,
                    isCollateralLiquidated: false,
                    isRollbacked: false,
                    isClosedManuallyStep1: false,
                    isClosedManuallyStep2: false
                }),
                closer: address(0)
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
            uint256 pricePrecision = priceFeed.PRECISION();

            uint256 baseValue;
            {
                uint256 basePrice = priceFeed.getLowestPrice(
                    _params.baseToken,
                    _params.quoteToken
                );
                pos = _initTradePosition(_params, basePrice);
                baseValue = (_params.baseAmount * basePrice) / pricePrecision;
            }

            uint256 minQuoteRate = _factory.minQuoteRate();
            uint256 baseTokenMUT = _factory.baseTokenMUT(_params.baseToken);
            uint256 collateralMUT = _factory.collateralMUT(_params.collateral);
            uint256 collateralPrice = priceFeed.getLowestPrice(
                _params.collateral,
                _params.quoteToken
            );

            {
                // avoid too deep stack
                // check min collateral amount
                uint256 minCollateralValue = (baseValue *
                    (minQuoteRate - baseTokenMUT)) / collateralMUT;
                uint256 minCollateralAmount = (minCollateralValue *
                    pricePrecision) / collateralPrice;
                if (_params.collateralAmount < minCollateralAmount) return pos;
            }

            uint256 mutc = (_params.collateralAmount *
                collateralPrice *
                collateralMUT) / (pricePrecision * 10000);
            {
                // avoid too deep stack
                // check quote amount range
                uint256 minQuoteAmount = (baseValue * minQuoteRate) / 10000;
                uint256 maxQuoteAmount = mutc +
                    (baseValue * baseTokenMUT) /
                    10000;
                if (
                    _params.quoteAmount > maxQuoteAmount ||
                    _params.quoteAmount < minQuoteAmount
                ) return pos;
            }

            pos.collateral.entryPrice = collateralPrice;
            {
                // avoid too deep stack
                // calculate collateral liquidation price
                uint256 collateralLT = _factory.collateralLT(
                    _params.collateral
                );
                pos.collateral.liqPrice =
                    (mutc * collateralLT * pricePrecision) /
                    (_params.collateralAmount * collateralMUT);
            }

            {
                // avoid too deep stack
                // calculate base token liquidation price
                uint256 baseTokenLT = _factory.baseTokenLT(_params.baseToken);
                if (_params.quoteAmount > mutc) {
                    uint256 baseLiqValue = ((_params.quoteAmount - mutc) *
                        baseTokenLT) / baseTokenMUT;
                    if (baseValue < baseLiqValue) return pos;
                    pos.baseToken.liqPrice =
                        (baseLiqValue * pricePrecision) /
                        _params.baseAmount;
                }
            }

            {
                // avoid too deep stack
                // calculate fees
                uint256 interest = _factory.interest(_params.quoteToken);
                uint256 fee = (_params.quoteAmount *
                    interest *
                    (_params.deadline - block.timestamp)) /
                    (365 * 24 * 60 * 60);
                IUserStorage userStorage = IUserStorage(_factory.userStorage());
                fee = userStorage.discountedFee(_params.owner, fee);
                uint256 protocolFeeRate = _factory.protocolFeeRate();
                pos.fee = fee;
                pos.protocolFee = (fee * protocolFeeRate) / 10000;
            }

            pos.pool = _factory.poolByQuoteToken(_params.quoteToken); // a position will be invalid if pool address == address(0)
        }
    }

    function previewTradePosition(
        OpenTradePositionParams memory _params
    ) external view override returns (TradePosition memory) {
        return _previewTradePosition(_params);
    }

    function previewUpdateCollateralAmount(
        UpdateCollateralAmountParams memory _params
    )
        external
        view
        override
        returns (uint256 collateralLiqPrice, uint256 baseLiqPrice)
    {
        uint256 idx = positionIndex[_params.positionKey];
        if (idx > 0) {
            TradePosition memory pos = positions[idx];

            IFactory _factory = IFactory(factory);
            IPriceFeed priceFeed = IPriceFeed(_factory.priceFeed());
            uint256 pricePrecision = priceFeed.PRECISION();
            uint256 collateralMUT = _factory.collateralMUT(pos.collateral.id);
            uint256 newCollateralAmount = pos.collateral.amount +
                _params.amount;

            uint256 mutc;
            {
                // avoid too deep stack
                uint256 collateralPrice = priceFeed.getLowestPrice(
                    pos.collateral.id,
                    pos.quoteToken.id
                );
                mutc =
                    (newCollateralAmount * collateralPrice * collateralMUT) /
                    (pricePrecision * 10000);
            }

            {
                // avoid too deep stack
                // calculate collateral liquidation price
                uint256 collateralLT = _factory.collateralLT(pos.collateral.id);
                collateralLiqPrice =
                    (mutc * collateralLT * pricePrecision) /
                    (newCollateralAmount * collateralMUT);
            }

            {
                // avoid too deep stack
                // calculate base token liquidation price
                uint256 baseTokenMUT = _factory.baseTokenMUT(pos.baseToken.id);
                uint256 baseTokenLT = _factory.baseTokenLT(pos.baseToken.id);
                if (pos.quoteToken.amount > mutc) {
                    uint256 baseLiqValue = ((pos.quoteToken.amount - mutc) *
                        baseTokenLT) / baseTokenMUT;
                    baseLiqPrice =
                        (baseLiqValue * pricePrecision) /
                        pos.baseToken.amount;
                }
            }
        }
    }

    function previewUpdateDeadline(
        UpdateDeadlineParams memory _params
    ) external view override returns (uint256 fee, uint256 protocolFee) {
        uint256 idx = positionIndex[_params.positionKey];
        if (idx > 0) {
            TradePosition memory pos = positions[idx];

            IFactory _factory = IFactory(factory);
            IUserStorage userStorage = IUserStorage(_factory.userStorage());
            if (_params.deadline <= pos.deadline) {
                uint256 interest = _factory.interest(pos.quoteToken.id);
                fee =
                    (pos.quoteToken.amount *
                        interest *
                        (_params.deadline - pos.deadline)) /
                    (365 * 24 * 60 * 60 * 10000);
                fee = userStorage.discountedFee(pos.owner, fee);
                uint256 protocolFeeRate = _factory.protocolFeeRate();
                protocolFee = (fee * protocolFeeRate) / 10000;
            }
        }
    }

    function canLiquidate(
        bytes32 _positionKey
    ) external view override returns (bool) {
        uint256 idx = positionIndex[_positionKey];
        if (idx == 0) return false;
        TradePosition memory pos = positions[idx];
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
            basePrice <= pos.baseToken.liqPrice
        ) return true;

        return false;
    }

    function openTradePosition(
        TradePosition memory _pos
    ) external override returns (bytes32 positionKey) {
        IFactory _factory = IFactory(factory);
        if (msg.sender != _factory.poolByQuoteToken(_pos.quoteToken.id))
            revert Forbidden(msg.sender);

        positionKey = keccak256(
            abi.encodePacked(this, positions.length, block.timestamp)
        );
        _pos.positionKey = positionKey;
        positions.push(_pos);
        positionIndex[_pos.positionKey] = positions.length;
        openingPositionKeys.push(_pos.positionKey);
        positionKeysByUser[_pos.owner].push(_pos.positionKey);

        emit OpenTradePosition(_pos.positionKey);
    }

    function updateStatus(
        bytes32 _positionKey,
        address _updater
    ) external override returns (bool needLiquidate) {
        uint256 idx = positionIndex[_positionKey];
        if (idx == 0) revert TradePositionNotExists(_positionKey);

        TradePosition storage pos = positions[idx];

        IFactory _factory = IFactory(factory);
        if (msg.sender != _factory.poolByQuoteToken(pos.quoteToken.id))
            revert Forbidden(msg.sender);

        if (pos.status.isClosed)
            revert TradePositionClosedAlready(_positionKey);

        if (pos.deadline <= block.timestamp) {
            pos.status.isExpired = true;
            needLiquidate = true;
        }
        IPriceFeed priceFeed = IPriceFeed(_factory.priceFeed());
        uint256 collateralPrice = priceFeed.getLowestPrice(
            pos.collateral.id,
            pos.quoteToken.id
        );
        if (collateralPrice <= pos.collateral.liqPrice) {
            pos.status.isCollateralLiquidated = true;
            needLiquidate = true;
        }
        uint256 basePrice = priceFeed.getLowestPrice(
            pos.baseToken.id,
            pos.quoteToken.id
        );
        if (pos.stoplossPrice > 0 && basePrice <= pos.stoplossPrice) {
            pos.status.isStoploss = true;
            needLiquidate = true;
        }
        if (basePrice <= pos.baseToken.liqPrice) {
            pos.status.isBaseLiquidated = true;
            needLiquidate = true;
        }

        if (_updater != pos.owner && !needLiquidate)
            revert NotOwner(pos.owner, _updater);
        pos.status.isClosed = true;
        pos.closer = _updater;

        emit CloseTradePosition(_positionKey, _updater);
    }

    function rollback(
        bytes32 _positionKey,
        address _updater
    ) external override {
        uint256 idx = positionIndex[_positionKey];
        if (idx == 0) revert TradePositionNotExists(_positionKey);

        TradePosition storage pos = positions[idx];

        IFactory _factory = IFactory(factory);
        if (msg.sender != _factory.poolByQuoteToken(pos.quoteToken.id))
            revert Forbidden(msg.sender);

        if (pos.status.isClosed)
            revert TradePositionClosedAlready(_positionKey);

        if (_updater != pos.owner) revert NotOwner(pos.owner, _updater);
        pos.status.isClosed = true;
        pos.status.isRollbacked = true;
        pos.closer = _updater;

        emit CloseTradePosition(_positionKey, _updater);
    }

    function closeManuallyStep1(bytes32 _positionKey) external override {
        uint256 idx = positionIndex[_positionKey];
        if (idx == 0) revert TradePositionNotExists(_positionKey);

        TradePosition storage pos = positions[idx];

        IFactory _factory = IFactory(factory);
        if (msg.sender != _factory.poolByQuoteToken(pos.quoteToken.id))
            revert Forbidden(msg.sender);

        if (pos.status.isClosed)
            revert TradePositionClosedAlready(_positionKey);

        pos.status.isClosedManuallyStep1 = true;

        emit CloseManuallyStep1TradePosition(_positionKey);
    }

    function closeManuallyStep2(bytes32 _positionKey) external override {
        uint256 idx = positionIndex[_positionKey];
        if (idx == 0) revert TradePositionNotExists(_positionKey);

        TradePosition storage pos = positions[idx];

        IFactory _factory = IFactory(factory);
        if (msg.sender != _factory.poolByQuoteToken(pos.quoteToken.id))
            revert Forbidden(msg.sender);

        if (pos.status.isClosed)
            revert TradePositionClosedAlready(_positionKey);

        if (!pos.status.isClosedManuallyStep1)
            revert Step1NotDone(_positionKey);

        pos.status.isClosed = true;
        pos.status.isClosedManuallyStep2 = true;

        emit CloseTradePosition(_positionKey, address(0));
    }

    function updateCloseValues(
        bytes32 _positionKey,
        uint256 _baseValue,
        uint256 _loss,
        uint256 _remainingCollateralAmount
    ) external override {
        uint256 idx = positionIndex[_positionKey];
        if (idx == 0) revert TradePositionNotExists(_positionKey);

        TradePosition storage pos = positions[idx];

        IFactory _factory = IFactory(factory);
        if (msg.sender != _factory.poolByQuoteToken(pos.quoteToken.id))
            revert Forbidden(msg.sender);

        if (!pos.status.isClosed) revert TradePositionNotClosed(_positionKey);
        IPriceFeed priceFeed = IPriceFeed(_factory.priceFeed());
        uint256 pricePrecision = priceFeed.PRECISION();

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

    function updateStoplossPrice(
        UpdateStoplossPriceParams memory _params
    ) external override {
        uint256 idx = positionIndex[_params.positionKey];
        if (idx == 0) revert TradePositionNotExists(_params.positionKey);

        TradePosition storage pos = positions[idx];

        IFactory _factory = IFactory(factory);
        if (msg.sender != _factory.poolByQuoteToken(pos.quoteToken.id))
            revert Forbidden(msg.sender);

        if (pos.status.isClosed)
            revert TradePositionClosedAlready(_params.positionKey);

        if (_params.updater != pos.owner)
            revert NotOwner(pos.owner, _params.updater);
        pos.stoplossPrice = _params.stoplossPrice;

        emit UpdateStoplossPrice(
            _params.positionKey,
            _params.stoplossPrice,
            _params.updater
        );
    }

    function updateCollateralAmount(
        UpdateCollateralAmountParams memory _params
    )
        external
        override
        returns (uint256 collateralLiqPrice, uint256 baseLiqPrice)
    {
        uint256 idx = positionIndex[_params.positionKey];
        if (idx == 0) revert TradePositionNotExists(_params.positionKey);

        TradePosition storage pos = positions[idx];

        IFactory _factory = IFactory(factory);
        if (msg.sender != _factory.poolByQuoteToken(pos.quoteToken.id))
            revert Forbidden(msg.sender);

        if (pos.status.isClosed)
            revert TradePositionClosedAlready(_params.positionKey);

        if (_params.updater != pos.owner)
            revert NotOwner(pos.owner, _params.updater);
        IPriceFeed priceFeed = IPriceFeed(_factory.priceFeed());
        uint256 pricePrecision = priceFeed.PRECISION();
        uint256 collateralMUT = _factory.collateralMUT(pos.collateral.id);
        uint256 newCollateralAmount = pos.collateral.amount + _params.amount;

        uint256 mutc;
        {
            // avoid too deep stack
            uint256 collateralPrice = priceFeed.getLowestPrice(
                pos.collateral.id,
                pos.quoteToken.id
            );
            mutc =
                (newCollateralAmount * collateralPrice * collateralMUT) /
                (pricePrecision * 10000);
        }

        {
            // avoid too deep stack
            // calculate collateral liquidation price
            uint256 collateralLT = _factory.collateralLT(pos.collateral.id);
            collateralLiqPrice =
                (mutc * collateralLT * pricePrecision) /
                (newCollateralAmount * collateralMUT);
        }

        {
            // avoid too deep stack
            // calculate base token liquidation price
            uint256 baseTokenMUT = _factory.baseTokenMUT(pos.baseToken.id);
            uint256 baseTokenLT = _factory.baseTokenLT(pos.baseToken.id);
            if (pos.quoteToken.amount > mutc) {
                uint256 baseLiqValue = ((pos.quoteToken.amount - mutc) *
                    baseTokenLT) / baseTokenMUT;
                baseLiqPrice =
                    (baseLiqValue * pricePrecision) /
                    pos.baseToken.amount;
            }
        }

        pos.collateral.liqPrice = collateralLiqPrice;
        pos.baseToken.liqPrice = baseLiqPrice;

        emit UpdateCollateralAmount(
            _params.positionKey,
            _params.amount,
            collateralLiqPrice,
            baseLiqPrice,
            _params.updater
        );
    }

    function updateDeadline(
        UpdateDeadlineParams memory _params
    ) external override returns (uint256 fee, uint256 protocolFee) {
        uint256 idx = positionIndex[_params.positionKey];
        if (idx == 0) revert TradePositionNotExists(_params.positionKey);

        TradePosition storage pos = positions[idx];

        IFactory _factory = IFactory(factory);
        if (msg.sender != _factory.poolByQuoteToken(pos.quoteToken.id))
            revert Forbidden(msg.sender);

        if (pos.status.isClosed)
            revert TradePositionClosedAlready(_params.positionKey);

        if (_params.updater != pos.owner)
            revert NotOwner(pos.owner, _params.updater);
        IUserStorage userStorage = IUserStorage(_factory.userStorage());
        bool canUpdateDeadline = userStorage.canUpdateDeadline(_params.updater);
        if (!canUpdateDeadline) revert NotAllowed(_params.updater);
        if (_params.deadline <= pos.deadline) revert InvalidParameter();

        uint256 interest = _factory.interest(pos.quoteToken.id);
        fee =
            (pos.quoteToken.amount *
                interest *
                (_params.deadline - pos.deadline)) /
            (365 * 24 * 60 * 60 * 10000);
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
