// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

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
    bytes4 private constant SELECTOR =
        bytes4(keccak256(bytes("transfer(address,uint256)")));
    address public override factory;
    address public override quoteToken;
    uint256 public override precision;
    uint256 public override interest; // annual // 10000 = 100%

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
    error WrongPool(address token, address quoteToken);
    error InvalidParameters();
    error InsufficientCollateral(uint256 amount, uint256 neededAmount);

    event SetInterest(uint256 newInterest);
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
    event UpdateStoplossPrice(
        address indexed sender,
        bytes32 indexed positionKey,
        uint256 newStoplossPrice,
        address updater,
        address serviceToken,
        uint256 serviceFee
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

    modifier onlyWithdrawalMonitor() {
        if (msg.sender != IFactory(factory).withdrawalMonitor()) {
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
            accFee -
            accProtocolFee -
            (quoteReserve - quoteInDebt);
    }

    function _unrealizeAmount(address _token) internal view returns (uint256) {
        if (_token == quoteToken) return _unrealizeLiquidity();
        uint256 balance = IERC20(_token).balanceOf(address(this));
        return balance - collateralReserve[_token] - baseReserve[_token];
    }

    function _availableLiquidity() internal view returns (uint256) {
        address _quoteToken = quoteToken;
        uint256 balance = IERC20(_quoteToken).balanceOf(address(this));
        return
            balance -
            withdrawingLiquidity -
            collateralReserve[_quoteToken] -
            accFee -
            accProtocolFee;
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

    function _safeTransfer(
        address _token,
        address _to,
        uint256 _value
    ) internal {
        (bool success, bytes memory data) = _token.call(
            abi.encodeWithSelector(SELECTOR, _to, _value)
        );
        if (!success || !(data.length == 0 || abi.decode(data, (bool)))) {
            revert TransferFailed(_token, _to, _value);
        }
    }

    function _updateQuoteReserve(uint256 _quoteReserve) internal {
        quoteReserve = _quoteReserve;

        emit UpdateQuoteReserve(quoteReserve);
    }

    function _updateQuoteInDebt(uint256 _quoteInDebt) internal {
        quoteInDebt = _quoteInDebt;

        emit UpdateQuoteInDebt(quoteInDebt);
    }

    function _updateWithdrawingLiquidity(
        uint256 _withdrawingLiquidity
    ) internal {
        withdrawingLiquidity = _withdrawingLiquidity;

        emit UpdateWithdrawingLiquidity(_withdrawingLiquidity);
    }

    function _addFee(uint256 _fee) internal {
        accFee += _fee;
        accFeePerShare += (_fee * precision) / quoteReserve;

        emit UpdateFee(accFee);
    }

    function _updateProtocolFee(uint256 _protocolFee) internal {
        accProtocolFee = _protocolFee;

        emit UpdateProtocolFee(accProtocolFee);
    }

    function _updateBaseReserve(
        address _baseToken,
        uint256 _baseReserve
    ) internal {
        baseReserve[_baseToken] = _baseReserve;

        emit UpdateBaseReserve(_baseToken, _baseReserve);
    }

    function _updateCollateralReserve(
        address _collateral,
        uint256 _collateralReserve
    ) internal {
        collateralReserve[_collateral] = _collateralReserve;

        emit UpdateCollateralReserve(_collateral, _collateralReserve);
    }

    function _transferProtocolFee() internal {
        uint256 _protocolFee = accProtocolFee;
        if (_protocolFee > 0) {
            address feeTo = IFactory(factory).protocolFeeTo();
            if (feeTo != address(0)) {
                _updateProtocolFee(0);
                _safeTransfer(quoteToken, feeTo, _protocolFee);
            }
        }
    }

    function availLiquidity() external override onlyWithdrawalMonitor {
        _updateWithdrawingLiquidity(0);
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

        _updateQuoteReserve(quoteReserve + _liquidity);
        _transferProtocolFee();

        uint256 balanceBefore = IERC20(_quoteToken).balanceOf(address(this));
        IMintCallback(msg.sender).mintCallback(_quoteToken, _liquidity, _data);
        uint256 balance = IERC20(_quoteToken).balanceOf(address(this));
        if (balance < balanceBefore + _liquidity) revert InsufficientInput();

        emit Mint(msg.sender, _to, _liquidity);
    }

    function collect(address _to, uint256 _amount) external override lock {
        if (_amount == 0) revert ZeroValue();
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

        _safeTransfer(quoteToken, _to, _amount);

        emit Collect(msg.sender, _to, _amount);
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

        IWithdrawalMonitor monitor = IWithdrawalMonitor(
            IFactory(factory).withdrawalMonitor()
        );
        return
            monitor.addRequest(msg.sender, quoteToken, _liquidity, _to, _data);
    }

    function burn(
        IWithdrawalMonitor.WithdrawalRequest memory _request
    ) external override lock onlyWithdrawalMonitor {
        LiquidityPosition storage pos = liquidityPosition[_request.owner];
        if (_request.liquidity > pos.withdrawingLiquidity)
            revert InsufficientOutput();
        uint256 _withdrawingLiquidity = withdrawingLiquidity;
        if (_request.liquidity > _withdrawingLiquidity) {
            uint256 liq = _availableLiquidity();
            if (_request.liquidity > _withdrawingLiquidity + liq)
                revert InsufficientOutput();
            _updateWithdrawingLiquidity(0);
        } else
            _updateWithdrawingLiquidity(
                _withdrawingLiquidity - _request.liquidity
            );

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

        _updateQuoteReserve(quoteReserve - _request.liquidity);
        _transferProtocolFee();

        // callback
        if (_request.data.length > 0) {
            IWithdrawalMonitor monitor = IWithdrawalMonitor(
                IFactory(factory).withdrawalMonitor()
            );
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

        _safeTransfer(quoteToken, _request.to, _request.liquidity);

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
        address _quoteToken = quoteToken;
        if (_params.quoteToken != _quoteToken) {
            revert WrongPool(_params.quoteToken, _quoteToken);
        }
        if (_params.baseToken == _params.quoteToken) revert InvalidParameters();
        if (!_checkInputTokens(_params)) revert InsufficientInput();

        IPositionStorage positionStorage = IPositionStorage(
            IFactory(factory).positionStorage()
        );
        IPositionStorage.TradePosition memory pos = positionStorage
            .previewTradePosition(_params);
        if (pos.owner == address(0)) revert InvalidParameters();

        uint256 realQuoteAmount = pos.quoteToken.amount - pos.fee;
        uint256 available = _availableLiquidity();
        if (realQuoteAmount > available) revert InsufficientOutput();

        positionKey = positionStorage.openTradePosition(pos);

        _updateQuoteInDebt(quoteInDebt + _params.quoteAmount);
        _addFee(pos.fee - pos.protocolFee);
        _updateProtocolFee(accProtocolFee + pos.protocolFee);
        _updateBaseReserve(
            _params.baseToken,
            baseReserve[_params.baseToken] + _params.baseAmount
        );
        _updateCollateralReserve(
            _params.collateral,
            collateralReserve[_params.collateral] + _params.collateralAmount
        );

        _safeTransfer(_quoteToken, _params.owner, _params.quoteAmount);

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
        uint256 _baseValue,
        bytes calldata _data
    ) internal {
        uint256 balanceBefore = IERC20(_pos.quoteToken.id).balanceOf(
            address(this)
        );
        _safeTransfer(_pos.baseToken.id, msg.sender, _pos.baseToken.amount);
        ICloseCallback(msg.sender).closeCallback(
            _pos.baseToken.id,
            _pos.quoteToken.id,
            _baseValue,
            _data
        );
        uint256 balanceAfter = IERC20(_pos.quoteToken.id).balanceOf(
            address(this)
        );
        if (balanceAfter < balanceBefore + _baseValue)
            revert InsufficientInput();
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
        _safeTransfer(_pos.collateral.id, msg.sender, _neededCollateralAmount);
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
        IPositionStorage positionStorage = IPositionStorage(
            _factory.positionStorage()
        );

        bool needLiquidate = positionStorage.updateStatus(
            _params.positionKey,
            _params.closer
        );
        IPositionStorage.TradePosition memory pos = positionStorage
            .positionByKey(_params.positionKey);
        IDEXAggregator dexAggregator = IDEXAggregator(_factory.dexAggregator());
        (uint256 baseValue, ) = dexAggregator.getAmountOut(
            address(0),
            pos.baseToken.id,
            pos.quoteToken.id,
            pos.baseToken.amount
        );
        _liquidateBaseToken(pos, baseValue, _params.data0);
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

        positionStorage.updateCloseValues(
            pos.positionKey,
            baseValue,
            loss,
            remainingCollateralAmount
        );

        _updateQuoteInDebt(quoteInDebt - pos.quoteToken.amount);
        _updateWithdrawingLiquidity(
            withdrawingLiquidity + pos.quoteToken.amount
        );
        _updateBaseReserve(
            pos.baseToken.id,
            baseReserve[pos.baseToken.id] - pos.baseToken.amount
        );
        _updateCollateralReserve(
            pos.collateral.id,
            collateralReserve[pos.collateral.id] - pos.collateral.amount
        );

        if (liquidationFee > 0) {
            address liquidationFeeTo = _factory.liquidationFeeTo();
            _safeTransfer(pos.quoteToken.id, liquidationFeeTo, liquidationFee);
        }
        if (loss == 0) {
            uint256 profit = baseValue - quoteAmount;
            if (profit > 0) {
                _safeTransfer(pos.quoteToken.id, pos.owner, profit);
            }
        }
        if (remainingCollateralAmount > 0) {
            _safeTransfer(
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
        IFactory _factory = IFactory(factory);
        IPositionStorage positionStorage = IPositionStorage(
            _factory.positionStorage()
        );
        IPositionStorage.TradePosition memory pos = positionStorage
            .positionByKey(_params.positionKey);
        address serviceToken = _factory.serviceToken();
        uint256 serviceFee = _factory.rollbackFee();
        if (serviceToken == quoteToken) {
            uint256 quoteAmount = _unrealizeLiquidity();
            if (quoteAmount < pos.quoteToken.amount + serviceFee)
                revert InsufficientInput();
        } else {
            uint256 quoteAmount = _unrealizeLiquidity();
            if (quoteAmount < pos.quoteToken.amount) revert InsufficientInput();
            uint256 serviceTokenAmount = _unrealizeAmount(serviceToken);
            if (serviceTokenAmount < serviceFee) revert InsufficientInput();
        }
        if (serviceToken != address(0) && serviceFee > 0) {
            address serviceFeeTo = _factory.serviceFeeTo();
            _safeTransfer(serviceToken, serviceFeeTo, serviceFee);
        }

        positionStorage.rollback(_params.positionKey, _params.rollbacker);

        _updateQuoteInDebt(quoteInDebt - pos.quoteToken.amount);
        _updateWithdrawingLiquidity(
            withdrawingLiquidity + pos.quoteToken.amount
        );
        _updateBaseReserve(
            pos.baseToken.id,
            baseReserve[pos.baseToken.id] - pos.baseToken.amount
        );
        _updateCollateralReserve(
            pos.collateral.id,
            collateralReserve[pos.collateral.id] - pos.collateral.amount
        );

        _safeTransfer(pos.baseToken.id, pos.owner, pos.baseToken.amount);
        _safeTransfer(pos.collateral.id, pos.owner, pos.collateral.amount);

        emit Rollback(
            msg.sender,
            pos.positionKey,
            _params.rollbacker,
            serviceToken,
            serviceFee
        );
    }

    // only in case ALL monitors cannot work
    function closeManuallyStep1(
        bytes32 _positionKey,
        address _executor
    ) external lock onlyOperator {
        IPositionStorage positionStorage = IPositionStorage(
            IFactory(factory).positionStorage()
        );
        positionStorage.closeManuallyStep1(_positionKey);

        IPositionStorage.TradePosition memory pos = positionStorage
            .positionByKey(_positionKey);

        // transfer all baseToken & collateral to executor to process manually
        _safeTransfer(pos.baseToken.id, _executor, pos.baseToken.amount);
        _safeTransfer(pos.collateral.id, _executor, pos.collateral.amount);

        _updateBaseReserve(
            pos.baseToken.id,
            baseReserve[pos.baseToken.id] - pos.baseToken.amount
        );
        _updateCollateralReserve(
            pos.collateral.id,
            collateralReserve[pos.collateral.id] - pos.collateral.amount
        );

        emit CloseManuallyStep1(msg.sender, _positionKey, _executor);
    }

    // only in case ALL monitors cannot work, after sending tokens to pool and liquidationFeeTo
    function closeManuallyStep2(
        bytes32 _positionKey,
        uint256 _baseValue,
        uint256 _remainingCollateralAmount,
        uint256 _liquidationFee
    ) external lock onlyOperator {
        IPositionStorage positionStorage = IPositionStorage(
            IFactory(factory).positionStorage()
        );
        IPositionStorage.TradePosition memory pos = positionStorage
            .positionByKey(_positionKey);

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

        positionStorage.closeManuallyStep2(_positionKey);

        uint256 loss;
        uint256 neededQuoteAmount = pos.quoteToken.amount + _liquidationFee;
        if (_baseValue < neededQuoteAmount) {
            loss = neededQuoteAmount - _baseValue;
        }
        positionStorage.updateCloseValues(
            pos.positionKey,
            _baseValue,
            loss,
            _remainingCollateralAmount
        );

        _updateQuoteInDebt(quoteInDebt - pos.quoteToken.amount);
        _updateWithdrawingLiquidity(
            withdrawingLiquidity + pos.quoteToken.amount
        );

        if (_liquidationFee > 0) {
            address liquidationFeeTo = IFactory(factory).liquidationFeeTo();
            _safeTransfer(pos.quoteToken.id, liquidationFeeTo, _liquidationFee);
        }
        if (loss == 0) {
            uint256 profit = _baseValue - neededQuoteAmount;
            if (profit > 0) {
                _safeTransfer(pos.quoteToken.id, pos.owner, profit);
            }
        }
        if (_remainingCollateralAmount > 0) {
            _safeTransfer(
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

    function _handleServiceFee(
        IFactory _factory,
        address _serviceToken,
        uint256 _serviceFee
    ) internal {
        if (_serviceToken != address(0) && _serviceFee > 0) {
            uint256 serviceTokenAmount = _unrealizeAmount(_serviceToken);
            if (serviceTokenAmount < _serviceFee) revert InsufficientInput();
            address serviceFeeTo = _factory.serviceFeeTo();
            _safeTransfer(_serviceToken, serviceFeeTo, _serviceFee);
        }
    }

    function updateStoplossPrice(
        IPositionStorage.UpdateStoplossPriceParams memory _params
    ) external override lock onlyOperator {
        IFactory _factory = IFactory(factory);
        address serviceToken = _factory.serviceToken();
        uint256 serviceFee = _factory.updateStoplossPriceFee();
        _handleServiceFee(_factory, serviceToken, serviceFee);

        IPositionStorage positionStorage = IPositionStorage(
            _factory.positionStorage()
        );
        positionStorage.updateStoplossPrice(_params);

        emit UpdateStoplossPrice(
            msg.sender,
            _params.positionKey,
            _params.stoplossPrice,
            _params.updater,
            serviceToken,
            serviceFee
        );
    }

    function updateCollateralAmount(
        IPositionStorage.UpdateCollateralAmountParams memory _params
    )
        external
        override
        lock
        onlyOperator
        returns (uint256 collateralLiqPrice)
    {
        IFactory _factory = IFactory(factory);
        address serviceToken = _factory.serviceToken();
        uint256 serviceFee = _factory.updateCollateralAmountFee();
        _handleServiceFee(_factory, serviceToken, serviceFee);

        IPositionStorage positionStorage = IPositionStorage(
            _factory.positionStorage()
        );
        collateralLiqPrice = positionStorage
            .updateCollateralAmount(_params);

        emit UpdateCollateralAmount(
            msg.sender,
            _params.positionKey,
            _params.amount,
            collateralLiqPrice,
            _params.updater,
            serviceToken,
            serviceFee
        );
    }

    function updateDeadline(
        IPositionStorage.UpdateDeadlineParams memory _params
    ) external override lock onlyOperator {
        IFactory _factory = IFactory(factory);
        address serviceToken = _factory.serviceToken();
        uint256 serviceFee = _factory.updateDeadlineFee();
        _handleServiceFee(_factory, serviceToken, serviceFee);

        IPositionStorage positionStorage = IPositionStorage(
            _factory.positionStorage()
        );
        IPositionStorage.TradePosition memory pos = positionStorage
            .positionByKey(_params.positionKey);
        (uint256 fee, uint256 protocolFee) = positionStorage.updateDeadline(
            _params
        );

        _addFee(fee - protocolFee);
        _updateProtocolFee(accProtocolFee + protocolFee);

        emit UpdateDeadline(
            msg.sender,
            _params.positionKey,
            pos.baseToken.id,
            pos.quoteToken.id,
            _params.deadline,
            fee,
            protocolFee,
            _params.updater,
            serviceToken,
            serviceFee
        );
    }
}
