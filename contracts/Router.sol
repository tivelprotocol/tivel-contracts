// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "./libraries/TransferHelper.sol";
import "./libraries/PoolAddress.sol";
import "./interfaces/external/IWETH9.sol";
import "./interfaces/ICloseCallback.sol";
import "./interfaces/IDEXAggregator.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IRouter.sol";
import "./base/PeripheryValidation.sol";

contract Router is IRouter, ICloseCallback, PeripheryValidation {
    address public immutable override WETH;
    address public immutable override factory;
    address public immutable poolDeployer;
    address public immutable positionStorage;

    error InvalidPool(address pool);
    error InsufficientInput();
    error InvalidParameters();

    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
        poolDeployer = IFactory(_factory).poolDeployer();
        positionStorage = IFactory(_factory).positionStorage();
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    function preview(
        IRouter.OpenTradePositionParams memory _params
    ) external view override returns (IPositionStorage.TradePosition memory) {
        IPositionStorage _positionStorage = IPositionStorage(positionStorage);
        return
            _positionStorage.previewTradePosition(
                IPositionStorage.OpenTradePositionParams({
                    owner: msg.sender,
                    baseToken: _params.baseToken,
                    quoteToken: _params.quoteToken,
                    collateral: _params.collateral,
                    baseAmount: _params.baseAmount,
                    quoteAmount: _params.quoteAmount,
                    collateralAmount: _params.collateralAmount,
                    deadline: _params.deadline,
                    stoplossPrice: _params.stoplossPrice,
                    takeProfitPrice: _params.takeProfitPrice
                })
            );
    }

    function _openPosition(
        address _pool,
        IRouter.OpenTradePositionParams memory _params
    ) internal returns (bytes32 positionKey) {
        positionKey = IPool(_pool).open(
            IPositionStorage.OpenTradePositionParams({
                owner: msg.sender,
                baseToken: _params.baseToken,
                quoteToken: _params.quoteToken,
                collateral: _params.collateral,
                baseAmount: _params.baseAmount,
                quoteAmount: _params.quoteAmount,
                collateralAmount: _params.collateralAmount,
                deadline: _params.deadline,
                stoplossPrice: _params.stoplossPrice,
                takeProfitPrice: _params.takeProfitPrice
            })
        );
    }

    function open(
        IRouter.OpenTradePositionParams memory _params
    )
        external
        override
        checkDeadline(_params.txDeadline)
        returns (bytes32 positionKey)
    {
        address pool = PoolAddress.computeAddress(
            poolDeployer,
            _params.quoteToken
        );
        if (pool == address(0)) revert InvalidPool(pool);
        TransferHelper.safeTransferFrom(
            _params.collateral,
            msg.sender,
            pool,
            _params.collateralAmount
        );
        TransferHelper.safeTransferFrom(
            _params.baseToken,
            msg.sender,
            pool,
            _params.baseAmount
        );
        positionKey = _openPosition(pool, _params);
    }

    function openWithEthAsCollateral(
        IRouter.OpenTradePositionParams memory _params
    )
        external
        payable
        override
        checkDeadline(_params.txDeadline)
        returns (bytes32 positionKey)
    {
        if (_params.collateral != WETH) revert InvalidParameters();
        if (msg.value < _params.collateralAmount) revert InsufficientInput();
        address pool = PoolAddress.computeAddress(
            poolDeployer,
            _params.quoteToken
        );
        if (pool == address(0)) revert InvalidPool(pool);
        IWETH9(_params.collateral).deposit{value: _params.collateralAmount}();
        assert(
            IERC20(_params.collateral).transfer(pool, _params.collateralAmount)
        );
        TransferHelper.safeTransferFrom(
            _params.baseToken,
            msg.sender,
            pool,
            _params.baseAmount
        );
        positionKey = _openPosition(pool, _params);
    }

    function openWithEthAsBaseToken(
        IRouter.OpenTradePositionParams memory _params
    )
        external
        payable
        override
        checkDeadline(_params.txDeadline)
        returns (bytes32 positionKey)
    {
        if (_params.baseToken != WETH) revert InvalidParameters();
        if (msg.value < _params.baseAmount) revert InsufficientInput();
        address pool = PoolAddress.computeAddress(
            poolDeployer,
            _params.quoteToken
        );
        if (pool == address(0)) revert InvalidPool(pool);
        IWETH9(_params.baseToken).deposit{value: _params.baseAmount}();
        assert(IERC20(_params.baseToken).transfer(pool, _params.baseAmount));
        TransferHelper.safeTransferFrom(
            _params.collateral,
            msg.sender,
            pool,
            _params.collateralAmount
        );
        positionKey = _openPosition(pool, _params);
    }

    function openETH(
        IRouter.OpenTradePositionParams memory _params
    )
        external
        payable
        override
        checkDeadline(_params.txDeadline)
        returns (bytes32 positionKey)
    {
        address _WETH = WETH; // gas savings
        if (_params.baseToken != _WETH || _params.collateral != _WETH)
            revert InvalidParameters();
        uint256 totalInputAmount = _params.collateralAmount +
            _params.baseAmount;
        if (msg.value < totalInputAmount) revert InsufficientInput();
        address pool = PoolAddress.computeAddress(
            poolDeployer,
            _params.quoteToken
        );
        if (pool == address(0)) revert InvalidPool(pool);
        IWETH9(_params.collateral).deposit{value: totalInputAmount}();
        assert(IERC20(_params.collateral).transfer(pool, totalInputAmount));
        positionKey = _openPosition(pool, _params);
    }

    function closeCallback(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountOut,
        bytes calldata /* _data */
    ) external override {
        IFactory _factory = IFactory(factory);
        IDEXAggregator aggregator = IDEXAggregator(_factory.dexAggregator());

        uint256 balance = IERC20(_tokenIn).balanceOf(address(this));
        TransferHelper.safeTransfer(_tokenIn, address(aggregator), balance);
        (uint256 amountOut,) = IDEXAggregator(aggregator).swap(
            address(0),
            _tokenIn,
            _tokenOut,
            _amountOut,
            address(this)
        );
        TransferHelper.safeTransfer(_tokenOut, address(msg.sender), amountOut);

        uint256 dust = IERC20(_tokenOut).balanceOf(address(this));
        if (dust > 0) {
            (uint256 dustOut, ) = IDEXAggregator(aggregator).getAmountOut(
                address(0),
                _tokenOut,
                _tokenIn,
                dust
            );
            if (dustOut > 0) {
                TransferHelper.safeTransfer(
                    _tokenOut,
                    address(aggregator),
                    dust
                );
                IDEXAggregator(aggregator).swap(
                    address(0),
                    _tokenOut,
                    _tokenIn,
                    0,
                    address(msg.sender)
                );
            } else {
                TransferHelper.safeTransfer(
                    _tokenOut,
                    _factory.protocolFeeTo(),
                    dust
                );
            }
        }
    }

    function close(
        IRouter.CloseTradePositionParams memory _params
    ) external override checkDeadline(_params.txDeadline) {
        uint256 index = IFactory(factory).poolIndex(_params.pool);
        if (index == 0) revert InvalidPool(_params.pool);
        IPool(_params.pool).close(
            IPositionStorage.CloseTradePositionParams({
                positionKey: _params.positionKey,
                data0: new bytes(0),
                data1: new bytes(0),
                closer: msg.sender
            })
        );
    }

    function rollback(
        IRouter.RollbackTradePositionParams memory _params
    ) external override checkDeadline(_params.txDeadline) {
        IFactory _factory = IFactory(factory);
        uint256 index = _factory.poolIndex(_params.pool);
        if (index == 0) revert InvalidPool(_params.pool);

        IPositionStorage _positionStorage = IPositionStorage(positionStorage);
        IPositionStorage.TradePosition memory pos = _positionStorage.position(
            _params.positionKey
        );
        TransferHelper.safeTransferFrom(
            pos.quoteToken.id,
            msg.sender,
            _params.pool,
            pos.quoteToken.amount
        );

        address serviceToken = _factory.serviceToken();
        uint256 serviceFee = _factory.rollbackFee();
        if (serviceToken != address(0) && serviceFee > 0) {
            TransferHelper.safeTransferFrom(
                serviceToken,
                msg.sender,
                _params.pool,
                serviceFee
            );
        }

        IPool(_params.pool).rollback(
            IPositionStorage.RollbackTradePositionParams({
                positionKey: _params.positionKey,
                rollbacker: msg.sender
            })
        );
    }

    function updateTPnSL(
        IRouter.UpdateTPnSLParams memory _params
    ) external override checkDeadline(_params.txDeadline) {
        IFactory _factory = IFactory(factory);
        uint256 index = _factory.poolIndex(_params.pool);
        if (index == 0) revert InvalidPool(_params.pool);

        address serviceToken = _factory.serviceToken();
        uint256 serviceFee = _factory.updateTPnSLFee();
        if (serviceToken != address(0) && serviceFee > 0) {
            TransferHelper.safeTransferFrom(
                serviceToken,
                msg.sender,
                _params.pool,
                serviceFee
            );
        }

        IPositionStorage _positionStorage = IPositionStorage(positionStorage);
        _positionStorage.updateTPnSL(
            IPositionStorage.UpdateTPnSLParams({
                positionKey: _params.positionKey,
                takeProfitPrice: _params.takeProfitPrice,
                stoplossPrice: _params.stoplossPrice,
                updater: msg.sender,
                serviceToken: serviceToken,
                serviceFee: serviceFee
            })
        );
    }

    function updateCollateralAmount(
        IRouter.UpdateCollateralAmountParams memory _params
    )
        external
        override
        checkDeadline(_params.txDeadline)
        returns (uint256 collateralLiqPrice)
    {
        IFactory _factory = IFactory(factory);
        uint256 index = _factory.poolIndex(_params.pool);
        if (index == 0) revert InvalidPool(_params.pool);

        IPositionStorage _positionStorage = IPositionStorage(positionStorage);
        IPositionStorage.TradePosition memory pos = _positionStorage.position(
            _params.positionKey
        );
        TransferHelper.safeTransferFrom(
            pos.collateral.id,
            msg.sender,
            _params.pool,
            _params.amount
        );

        address serviceToken = _factory.serviceToken();
        uint256 serviceFee = _factory.updateCollateralAmountFee();
        if (serviceToken != address(0) && serviceFee > 0) {
            TransferHelper.safeTransferFrom(
                serviceToken,
                msg.sender,
                _params.pool,
                serviceFee
            );
        }

        collateralLiqPrice = IPool(_params.pool).updateCollateralAmount(
            IPositionStorage.UpdateCollateralAmountParams({
                positionKey: _params.positionKey,
                amount: _params.amount,
                updater: msg.sender
            })
        );
    }

    function updateDeadline(
        IRouter.UpdateDeadlineParams memory _params
    ) external override checkDeadline(_params.txDeadline) {
        IFactory _factory = IFactory(factory);
        uint256 index = _factory.poolIndex(_params.pool);
        if (index == 0) revert InvalidPool(_params.pool);

        address serviceToken = _factory.serviceToken();
        uint256 serviceFee = _factory.updateDeadlineFee();
        if (serviceToken != address(0) && serviceFee > 0) {
            TransferHelper.safeTransferFrom(
                serviceToken,
                msg.sender,
                _params.pool,
                serviceFee
            );
        }

        IPool(_params.pool).updateDeadline(
            IPositionStorage.UpdateDeadlineParams({
                positionKey: _params.positionKey,
                deadline: _params.deadline,
                updater: msg.sender
            })
        );
    }
}
