// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "./libraries/TransferHelper.sol";
import "./interfaces/ICloseCallback.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IDEXAggregator.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IMintCallback.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IWithdrawalMonitor.sol";
import "./interfaces/external/IWETH9.sol";
import "./base/Lockable.sol";

contract Pool is Lockable, IPool {
    address public override factory;
    address public override positionStorage;
    address public override withdrawalMonitor;
    address public override quoteToken;
    uint256 public override precision;
    uint256 public override interest; // annual // 10000 = 100%
    uint256 public override maxOpenInterest;
    uint256 public override openInterest;

    uint256 public override quoteReserve;
    uint256 public override quoteInDebt;
    uint256 public override withdrawingLiquidity;
    uint256 public override accFee;
    uint256 public override accProtocolFee;
    uint256 public override accFeePerShare;
    mapping(address => bool) public override tradeableBaseToken;
    mapping(address => uint256) public override baseReserve;
    mapping(address => uint256) public override collateralReserve;
    mapping(address => LiquidityPosition) public override liquidityPosition;

    error InitializedAlready();
    error Forbidden(address sender);
    error BadLengths(uint256 length0, uint256 length1);
    error EthTransferFailed(address to, uint256 value);
    error TransferFailed(address token, address to, uint256 value);
    error InsufficientInput();
    error InsufficientOutput();
    error ZeroValue();
    error UntradeableBaseToken(address token);
    error InvalidParameters();
    error ExceedMaxOpenInterest();
    error InsufficientCollateral(uint256 amount, uint256 neededAmount);

    event SetInterest(uint256 newInterest);
    event SetMaxOpenInterest(uint256 newMaxOpenInterest);
    event SetBaseToken(address baseToken, address quoteToken, bool tradeable);
    event UpdateQuoteReserve(uint256 newQuoteReserve);
    event UpdateQuoteInDebt(uint256 newQuoteInDebt);
    event UpdateWithdrawingLiquidity(uint256 newWithdrawingLiquidity);
    event UpdateFee(uint256 newFee);
    event UpdateProtocolFee(uint256 newProtocolFee);
    event UpdateBaseReserve(address baseToken, uint256 newReserve);
    event UpdateCollateralReserve(address collateral, uint256 newReserve);
    event Mint(address indexed sender, address indexed to, uint256 liquidity);
    event Collect(address indexed sender, address indexed to, uint256 amount);
    event Burn(address indexed sender, uint256 liquidity);
    event Open(
        address indexed sender,
        address indexed owner,
        bytes32 indexed positionKey,
        address baseToken,
        address quoteToken,
        address collateral,
        uint256 baseAmount,
        uint256 quoteAmount,
        uint256 collateralAmount,
        uint256 fee,
        uint256 protocolFee
    );
    event Close(
        address indexed sender,
        address indexed owner,
        bytes32 indexed positionKey,
        address baseToken,
        address closer,
        uint256 liquidationFee
    );
    event Rollback(
        address indexed sender,
        bytes32 indexed positionKey,
        address rollbacker,
        address serviceToken,
        uint256 serviceFee
    );
    event CloseManuallyStep1(
        address indexed sender,
        bytes32 indexed positionKey,
        address indexed executor
    );
    event UpdateCollateralAmount(
        address indexed sender,
        bytes32 indexed positionKey,
        uint256 amount,
        uint256 newCollateralLiqPrice,
        address updater,
        address serviceToken,
        uint256 serviceFee
    );
    event UpdateDeadline(
        address indexed sender,
        bytes32 indexed positionKey,
        address baseToken,
        address quoteToken,
        uint256 newDeadline,
        uint256 fee,
        uint256 protocolFee,
        address updater,
        address serviceToken,
        uint256 serviceFee
    );

    function initialize(
        address _factory,
        address _quoteToken,
        uint256 _interest
    ) external {
        if (factory != address(0)) revert InitializedAlready();
        factory = _factory;
        positionStorage = IFactory(_factory).positionStorage();
        withdrawalMonitor = IFactory(_factory).withdrawalMonitor();
        quoteToken = _quoteToken;
        precision = 10 ** IERC20(_quoteToken).decimals();
        interest = _interest;
    }

    modifier onlyFactory() {
        if (msg.sender != factory) revert Forbidden(msg.sender);
        _;
    }

    modifier onlyOperator() {
        if (!IFactory(factory).operator(msg.sender)) {
            revert Forbidden(msg.sender);
        }
        _;
    }

    function _unrealizeLiquidity() internal view returns (uint256) {
        address _quoteToken = quoteToken;
        uint256 balance = IERC20(_quoteToken).balanceOf(address(this));
        return
            balance -
            collateralReserve[_quoteToken] -
            (quoteReserve - quoteInDebt);
    }

    function _unrealizeAmount(address _token) internal view returns (uint256) {
        if (_token == quoteToken) return _unrealizeLiquidity();
        uint256 balance = IERC20(_token).balanceOf(address(this));
        return balance - collateralReserve[_token] - baseReserve[_token];
    }

    function _availableLiquidity() internal view returns (uint256) {
        int256 result = int256(quoteReserve) -
            int256(quoteInDebt) -
            int256(withdrawingLiquidity);
        return result < 0 ? 0 : uint256(result);
    }

    function availableLiquidity() external view override returns (uint256) {
        return _availableLiquidity();
    }

    function claimableFee(
        address _owner
    ) external view override returns (uint256 amount) {
        LiquidityPosition memory pos = liquidityPosition[_owner];
        amount =
            pos.pendingFee +
            (accFeePerShare * pos.liquidity) /
            precision -
            pos.feeDebt;
        if (amount > accFee) amount = accFee;
    }

    function setInterest(uint256 _interest) external override onlyFactory {
        interest = _interest;

        emit SetInterest(_interest);
    }

    function setMaxOpenInterest(
        uint256 _maxOpenInterest
    ) external override onlyFactory {
        maxOpenInterest = _maxOpenInterest;

        emit SetMaxOpenInterest(_maxOpenInterest);
    }

    function setBaseTokens(
        address[] memory _baseTokens,
        bool[] memory _tradeables
    ) external override onlyFactory {
        address _quoteToken = quoteToken;
        if (_baseTokens.length != _tradeables.length)
            revert BadLengths(_baseTokens.length, _tradeables.length);
        for (uint256 i = 0; i < _baseTokens.length; i++) {
            tradeableBaseToken[_baseTokens[i]] = _tradeables[i];

            emit SetBaseToken(_baseTokens[i], _quoteToken, _tradeables[i]);
        }
    }

    function _addFee(uint256 _fee) internal {
        accFee += _fee;
        accFeePerShare += (_fee * precision) / quoteReserve;

        emit UpdateFee(accFee);
    }

    function _transferProtocolFee() internal {
        uint256 _protocolFee = accProtocolFee;
        if (_protocolFee > 0) {
            address feeTo = IFactory(factory).protocolFeeTo();
            if (feeTo != address(0)) {
                accProtocolFee = 0;
                TransferHelper.safeTransfer(quoteToken, feeTo, _protocolFee);
            }
        }
    }

    function availLiquidity() external override {
        if (msg.sender != withdrawalMonitor) {
            revert Forbidden(msg.sender);
        }
        withdrawingLiquidity = 0;
    }

    function mint(
        address _to,
        uint256 _liquidity,
        bytes calldata _data
    ) external override lock {
        address _quoteToken = quoteToken;
        LiquidityPosition storage pos = liquidityPosition[_to];

        uint256 _accFeePerShare = accFeePerShare;
        uint256 _precision = precision;

        if (pos.liquidity > 0) {
            pos.pendingFee +=
                (_accFeePerShare * pos.liquidity) /
                _precision -
                pos.feeDebt;
        }
        pos.liquidity += _liquidity;
        pos.feeDebt = (_accFeePerShare * pos.liquidity) / _precision;

        quoteReserve += _liquidity;
        _transferProtocolFee();

        uint256 balanceBefore = IERC20(_quoteToken).balanceOf(address(this));
        IMintCallback(msg.sender).mintCallback(_quoteToken, _liquidity, _data);

        uint256 balance = IERC20(_quoteToken).balanceOf(address(this));
        if (balance < balanceBefore + _liquidity) revert InsufficientInput();

        emit Mint(msg.sender, _to, _liquidity);
    }

    function collect(address _to, uint256 _amount) external override lock {
        if (_amount > 0) {
            LiquidityPosition storage pos = liquidityPosition[msg.sender];

            uint256 _accFeePerShare = accFeePerShare;
            uint256 _precision = precision;

            if (pos.liquidity > 0) {
                pos.pendingFee +=
                    (_accFeePerShare * pos.liquidity) /
                    _precision -
                    pos.feeDebt;
            }
            pos.feeDebt = (_accFeePerShare * pos.liquidity) / _precision;

            if (_amount > pos.pendingFee || _amount > accFee) {
                revert InsufficientOutput();
            }
            pos.pendingFee -= _amount;

            TransferHelper.safeTransfer(quoteToken, _to, _amount);

            emit Collect(msg.sender, _to, _amount);
        }
    }

    function addBurnRequest(
        uint256 _liquidity,
        address _to,
        bytes calldata _data
    ) external override lock returns (uint256) {
        LiquidityPosition storage pos = liquidityPosition[msg.sender];
        if (_liquidity + pos.withdrawingLiquidity > pos.liquidity)
            revert InsufficientOutput();

        pos.withdrawingLiquidity += _liquidity;
        withdrawingLiquidity += _liquidity;

        IWithdrawalMonitor monitor = IWithdrawalMonitor(withdrawalMonitor);
        return
            monitor.addRequest(msg.sender, quoteToken, _liquidity, _to, _data);
    }

    function burn(
        IWithdrawalMonitor.WithdrawalRequest memory _request
    ) external override lock {
        IWithdrawalMonitor monitor = IWithdrawalMonitor(withdrawalMonitor);
        if (msg.sender != address(monitor)) {
            revert Forbidden(msg.sender);
        }
        LiquidityPosition storage pos = liquidityPosition[_request.owner];
        if (_request.liquidity > pos.withdrawingLiquidity)
            revert InsufficientOutput();
        if (_request.liquidity > withdrawingLiquidity) {
            withdrawingLiquidity = 0;
        } else withdrawingLiquidity -= _request.liquidity;

        uint256 _accFeePerShare = accFeePerShare;
        uint256 _precision = precision;

        if (pos.liquidity > 0) {
            pos.pendingFee +=
                (_accFeePerShare * pos.liquidity) /
                _precision -
                pos.feeDebt;
        }
        pos.liquidity -= _request.liquidity;
        pos.withdrawingLiquidity -= _request.liquidity;
        pos.feeDebt = (_accFeePerShare * pos.liquidity) / _precision;

        quoteReserve -= _request.liquidity;
        _transferProtocolFee();

        // callback
        if (_request.data.length > 0) {
            bytes memory callbackData = abi.encodeWithSignature(
                "burnCallback(uint256,bytes)",
                _request.liquidity,
                _request.data
            );
            (bool success, bytes memory result) = _request.owner.call(
                callbackData
            );

            // will save callback result without caring if it is success or not, so be careful
            if (!success) {
                // Next 14 lines from https://ethereum.stackexchange.com/a/83577
                if (result.length < 68) {
                    monitor.updateCallbackResult(
                        _request.index,
                        "Callback transaction failed silently"
                    );
                } else {
                    assembly {
                        result := add(result, 0x04)
                    }
                    monitor.updateCallbackResult(
                        _request.index,
                        abi.decode(result, (string))
                    );
                }
            }
        }

        TransferHelper.safeTransfer(
            quoteToken,
            _request.to,
            _request.liquidity
        );

        emit Burn(msg.sender, _request.liquidity);
    }

    function _checkInputTokens(
        IPositionStorage.OpenTradePositionParams memory _params
    ) internal view returns (bool) {
        if (_params.collateral != _params.baseToken) {
            uint256 collateralAmount = IERC20(_params.collateral).balanceOf(
                address(this)
            );
            collateralAmount -= (collateralReserve[_params.collateral] +
                baseReserve[_params.collateral]);
            if (_params.collateral == _params.quoteToken) {
                collateralAmount -= (quoteReserve -
                    quoteInDebt -
                    accFee -
                    accProtocolFee);
            }
            if (collateralAmount < _params.collateralAmount) return false;

            uint256 baseAmount = IERC20(_params.baseToken).balanceOf(
                address(this)
            );
            baseAmount -= (collateralReserve[_params.baseToken] +
                baseReserve[_params.baseToken]);
            if (baseAmount < _params.baseAmount) return false;
        } else {
            uint256 addedAmount = IERC20(_params.collateral).balanceOf(
                address(this)
            );
            addedAmount -= (collateralReserve[_params.collateral] +
                baseReserve[_params.collateral]);
            if (addedAmount < _params.collateralAmount + _params.baseAmount)
                return false;
        }
        return true;
    }

    function open(
        IPositionStorage.OpenTradePositionParams memory _params
    ) external override lock returns (bytes32 positionKey) {
        if (!tradeableBaseToken[_params.baseToken])
            revert UntradeableBaseToken(_params.baseToken);
        if (openInterest + _params.quoteAmount > maxOpenInterest)
            revert ExceedMaxOpenInterest();

        address _quoteToken = quoteToken;
        _params.quoteToken = _quoteToken;
        if (_params.baseToken == _quoteToken) revert InvalidParameters();
        if (!_checkInputTokens(_params)) revert InsufficientInput();

        IPositionStorage _positionStorage = IPositionStorage(positionStorage);
        IPositionStorage.TradePosition memory pos = _positionStorage
            .previewTradePosition(_params);
        if (pos.owner == address(0)) revert InvalidParameters();

        uint256 realQuoteAmount = pos.quoteToken.amount - pos.fee;
        uint256 available = _availableLiquidity();
        if (realQuoteAmount > available) revert InsufficientOutput();

        positionKey = _positionStorage.openTradePosition(pos);

        quoteInDebt += _params.quoteAmount;
        accProtocolFee += pos.protocolFee;
        baseReserve[_params.baseToken] += _params.baseAmount;
        collateralReserve[_params.collateral] += _params.collateralAmount;
        openInterest += pos.quoteToken.amount;
        _addFee(pos.fee - pos.protocolFee);

        TransferHelper.safeTransfer(
            _quoteToken,
            _params.owner,
            realQuoteAmount
        );

        emit Open(
            msg.sender,
            _params.owner,
            positionKey,
            _params.baseToken,
            _params.quoteToken,
            _params.collateral,
            _params.baseAmount,
            _params.quoteAmount,
            _params.collateralAmount,
            pos.fee,
            pos.protocolFee
        );
    }

    function _liquidateBaseToken(
        IPositionStorage.TradePosition memory _pos,
        bytes calldata _data
    ) internal returns (uint256) {
        uint256 balanceBefore = IERC20(_pos.quoteToken.id).balanceOf(
            address(this)
        );
        TransferHelper.safeTransfer(
            _pos.baseToken.id,
            msg.sender,
            _pos.baseToken.amount
        );
        ICloseCallback(msg.sender).closeCallback(
            _pos.baseToken.id,
            _pos.quoteToken.id,
            0,
            _data
        );

        uint256 balanceAfter = IERC20(_pos.quoteToken.id).balanceOf(
            address(this)
        );
        if (balanceAfter < balanceBefore) revert InsufficientInput();
        return balanceAfter - balanceBefore;
    }

    function _liquidateCollateral(
        IPositionStorage.TradePosition memory _pos,
        uint256 _neededCollateralAmount,
        uint256 _loss,
        bytes calldata _data
    ) internal returns (uint256) {
        uint256 colBalanceBefore = IERC20(_pos.collateral.id).balanceOf(
            address(this)
        );
        uint256 quoteBalanceBefore = IERC20(_pos.quoteToken.id).balanceOf(
            address(this)
        );
        TransferHelper.safeTransfer(
            _pos.collateral.id,
            msg.sender,
            _neededCollateralAmount
        );
        ICloseCallback(msg.sender).closeCallback(
            _pos.collateral.id,
            _pos.quoteToken.id,
            _loss,
            _data
        );

        uint256 colBalanceAfter = IERC20(_pos.collateral.id).balanceOf(
            address(this)
        );
        uint256 quoteBalanceAfter = IERC20(_pos.quoteToken.id).balanceOf(
            address(this)
        );
        if (quoteBalanceAfter < quoteBalanceBefore + _loss)
            revert InsufficientInput();
        return colBalanceAfter - (colBalanceBefore - _neededCollateralAmount); // > 0 in case used less than sent
    }

    function close(
        IPositionStorage.CloseTradePositionParams calldata _params
    ) external override lock onlyOperator {
        IFactory _factory = IFactory(factory);
        IPositionStorage _positionStorage = IPositionStorage(positionStorage);

        bool needLiquidate = _positionStorage.updateStatus(
            _params.positionKey,
            _params.closer
        );
        IPositionStorage.TradePosition memory pos = _positionStorage.position(
            _params.positionKey
        );
        uint256 baseValue = _liquidateBaseToken(pos, _params.data0);
        uint256 liquidationFee;
        uint256 quoteAmount = pos.quoteToken.amount;
        if (needLiquidate) {
            uint256 liquidationFeeRate = _factory.liquidationFeeRate();
            liquidationFee = (quoteAmount * liquidationFeeRate) / 10000;
            quoteAmount += liquidationFee;
        }
        uint256 loss;
        uint256 remainingCollateralAmount;
        // avoid too deep stack
        {
            uint256 neededCollateralAmount;
            if (baseValue < quoteAmount) {
                loss = quoteAmount - baseValue;
                neededCollateralAmount = loss;
                if (pos.collateral.id != pos.quoteToken.id) {
                    IDEXAggregator dexAggregator = IDEXAggregator(
                        _factory.dexAggregator()
                    );
                    (neededCollateralAmount, ) = dexAggregator.getAmountIn(
                        address(0),
                        pos.collateral.id,
                        pos.quoteToken.id,
                        loss
                    );
                    if (neededCollateralAmount > pos.collateral.amount) {
                        revert InsufficientCollateral(
                            pos.collateral.amount,
                            neededCollateralAmount
                        );
                    }
                    remainingCollateralAmount += _liquidateCollateral(
                        pos,
                        neededCollateralAmount,
                        loss,
                        _params.data1
                    );
                }
            }

            remainingCollateralAmount += (pos.collateral.amount -
                neededCollateralAmount);
        }

        _positionStorage.updateCloseValues(
            pos.positionKey,
            baseValue,
            loss,
            remainingCollateralAmount
        );

        quoteInDebt -= pos.quoteToken.amount;
        withdrawingLiquidity += pos.quoteToken.amount;
        baseReserve[pos.baseToken.id] -= pos.baseToken.amount;
        collateralReserve[pos.collateral.id] -= pos.collateral.amount;
        openInterest -= pos.quoteToken.amount;

        if (liquidationFee > 0) {
            address liquidationFeeTo = _factory.liquidationFeeTo();
            TransferHelper.safeTransfer(
                pos.quoteToken.id,
                liquidationFeeTo,
                liquidationFee
            );
        }
        if (loss == 0) {
            uint256 profit = baseValue - quoteAmount;
            if (profit > 0) {
                TransferHelper.safeTransfer(
                    pos.quoteToken.id,
                    pos.owner,
                    profit
                );
            }
        }
        if (remainingCollateralAmount > 0) {
            TransferHelper.safeTransfer(
                pos.collateral.id,
                pos.owner,
                remainingCollateralAmount
            );
        }

        emit Close(
            msg.sender,
            pos.owner,
            pos.positionKey,
            pos.baseToken.id,
            _params.closer,
            liquidationFee
        );
    }

    function rollback(
        IPositionStorage.RollbackTradePositionParams calldata _params
    ) external override lock onlyOperator {
        IPositionStorage _positionStorage = IPositionStorage(positionStorage);
        IPositionStorage.TradePosition memory pos = _positionStorage.position(
            _params.positionKey
        );
        uint256 quoteAmount = _unrealizeLiquidity();
        if (quoteAmount < pos.quoteToken.amount) revert InsufficientInput();

        _positionStorage.rollback(_params.positionKey, _params.rollbacker);

        quoteInDebt -= pos.quoteToken.amount;
        withdrawingLiquidity += pos.quoteToken.amount;
        baseReserve[pos.baseToken.id] -= pos.baseToken.amount;
        collateralReserve[pos.collateral.id] -= pos.collateral.amount;
        openInterest -= pos.quoteToken.amount;

        TransferHelper.safeTransfer(
            pos.baseToken.id,
            pos.owner,
            pos.baseToken.amount
        );
        TransferHelper.safeTransfer(
            pos.collateral.id,
            pos.owner,
            pos.collateral.amount
        );

        emit Rollback(
            msg.sender,
            pos.positionKey,
            _params.rollbacker,
            _params.serviceToken,
            _params.serviceFee
        );
    }

    // only in case ALL monitors cannot work
    function closeManuallyStep1(
        bytes32 _positionKey,
        address _executor
    ) external lock onlyOperator {
        IPositionStorage _positionStorage = IPositionStorage(positionStorage);
        _positionStorage.closeManuallyStep1(_positionKey);

        IPositionStorage.TradePosition memory pos = _positionStorage.position(
            _positionKey
        );

        // transfer all baseToken & collateral to executor to process manually
        TransferHelper.safeTransfer(
            pos.baseToken.id,
            _executor,
            pos.baseToken.amount
        );
        TransferHelper.safeTransfer(
            pos.collateral.id,
            _executor,
            pos.collateral.amount
        );

        baseReserve[pos.baseToken.id] -= pos.baseToken.amount;
        collateralReserve[pos.collateral.id] -= pos.collateral.amount;

        emit CloseManuallyStep1(msg.sender, _positionKey, _executor);
    }

    // only in case ALL monitors cannot work, after sending tokens to pool and liquidationFeeTo
    function closeManuallyStep2(
        bytes32 _positionKey,
        uint256 _baseValue,
        uint256 _remainingCollateralAmount,
        uint256 _liquidationFee
    ) external lock onlyOperator {
        IPositionStorage _positionStorage = IPositionStorage(positionStorage);
        IPositionStorage.TradePosition memory pos = _positionStorage.position(
            _positionKey
        );

        if (pos.collateral.id == pos.quoteToken.id) {
            uint256 amount = _unrealizeLiquidity();
            if (
                amount <
                _baseValue + _remainingCollateralAmount + _liquidationFee
            ) revert InsufficientInput();
        } else {
            uint256 quoteAmount = _unrealizeLiquidity();
            if (quoteAmount < _baseValue + _liquidationFee)
                revert InsufficientInput();
            uint256 _collateralReserve = collateralReserve[pos.collateral.id];
            uint256 _baseReserve = baseReserve[pos.collateral.id];
            uint256 collateralBalance = IERC20(pos.collateral.id).balanceOf(
                address(this)
            );
            uint256 collateralAmount = collateralBalance -
                _collateralReserve -
                _baseReserve;
            if (collateralAmount < _remainingCollateralAmount)
                revert InsufficientInput();
        }

        _positionStorage.closeManuallyStep2(_positionKey);

        uint256 loss;
        uint256 neededQuoteAmount = pos.quoteToken.amount + _liquidationFee;
        if (_baseValue < neededQuoteAmount) {
            loss = neededQuoteAmount - _baseValue;
        }
        _positionStorage.updateCloseValues(
            pos.positionKey,
            _baseValue,
            loss,
            _remainingCollateralAmount
        );

        quoteInDebt -= pos.quoteToken.amount;
        withdrawingLiquidity += pos.quoteToken.amount;
        openInterest -= pos.quoteToken.amount;

        if (_liquidationFee > 0) {
            address liquidationFeeTo = IFactory(factory).liquidationFeeTo();
            TransferHelper.safeTransfer(
                pos.quoteToken.id,
                liquidationFeeTo,
                _liquidationFee
            );
        }
        if (loss == 0) {
            uint256 profit = _baseValue - neededQuoteAmount;
            if (profit > 0) {
                TransferHelper.safeTransfer(
                    pos.quoteToken.id,
                    pos.owner,
                    profit
                );
            }
        }
        if (_remainingCollateralAmount > 0) {
            TransferHelper.safeTransfer(
                pos.collateral.id,
                pos.owner,
                _remainingCollateralAmount
            );
        }

        emit Close(
            msg.sender,
            pos.owner,
            _positionKey,
            pos.baseToken.id,
            msg.sender,
            _liquidationFee
        );
    }

    function updateCollateralAmount(
        IPositionStorage.UpdateCollateralAmountParams memory _params
    ) external override lock onlyOperator returns (uint256 collateralLiqPrice) {
        IPositionStorage _positionStorage = IPositionStorage(positionStorage);
        IPositionStorage.TradePosition memory pos = _positionStorage.position(
            _params.positionKey
        );
        uint256 addedCollateralAmount = _unrealizeAmount(pos.collateral.id);
        if (addedCollateralAmount < _params.amount) revert InsufficientInput();

        collateralLiqPrice = _positionStorage.updateCollateralAmount(_params);

        collateralReserve[pos.collateral.id] += _params.amount;

        emit UpdateCollateralAmount(
            msg.sender,
            _params.positionKey,
            _params.amount,
            collateralLiqPrice,
            _params.updater,
            _params.serviceToken,
            _params.serviceFee
        );
    }

    function updateDeadline(
        IPositionStorage.UpdateDeadlineParams memory _params
    ) external override lock onlyOperator {
        IPositionStorage _positionStorage = IPositionStorage(positionStorage);
        IPositionStorage.TradePosition memory pos = _positionStorage.position(
            _params.positionKey
        );
        (uint256 fee, uint256 protocolFee) = _positionStorage.updateDeadline(
            _params
        );

        _addFee(fee - protocolFee);
        accProtocolFee += protocolFee;

        emit UpdateDeadline(
            msg.sender,
            _params.positionKey,
            pos.baseToken.id,
            pos.quoteToken.id,
            _params.deadline,
            fee,
            protocolFee,
            _params.updater,
            _params.serviceToken,
            _params.serviceFee
        );
    }
}
