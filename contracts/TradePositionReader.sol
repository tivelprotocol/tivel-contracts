// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "./interfaces/IERC20.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IPool.sol";

struct Token {
    address token;
    string name;
    string symbol;
    uint256 decimals;
}

struct Pair {
    string ticker;
    address pool;
    Token baseToken;
    Token quoteToken;
    uint256 baseTokenLT;
}

struct TradePosition {
    Pair pair;
    Token collateral;
    IPositionStorage.TradePosition detail;
}

contract TradePositionReader {
    function pair(
        address _pool,
        address _baseToken
    ) public view returns (Pair memory) {
        address factory = IPool(_pool).factory();
        address quoteToken = IPool(_pool).quoteToken();
        string memory quoteTokenSymbol = IERC20(quoteToken).symbol();
        string memory baseTokenSymbol = IERC20(_baseToken).symbol();
        return
            Pair({
                pool: _pool,
                quoteToken: Token({
                    token: quoteToken,
                    name: IERC20(quoteToken).name(),
                    symbol: quoteTokenSymbol,
                    decimals: IERC20(quoteToken).decimals()
                }),
                baseToken: Token({
                    token: _baseToken,
                    name: IERC20(_baseToken).name(),
                    symbol: baseTokenSymbol,
                    decimals: IERC20(_baseToken).decimals()
                }),
                baseTokenLT: IFactory(factory).baseTokenLT(_baseToken),
                ticker: string(
                    abi.encodePacked(baseTokenSymbol, "/", quoteTokenSymbol)
                )
            });
    }

    function previewPosition(
        address _pool,
        IPositionStorage.OpenTradePositionParams memory _params
    ) external view returns (IPositionStorage.TradePosition memory) {
        address factory = IPool(_pool).factory();
        address positionStorage = IFactory(factory).positionStorage();
        return IPositionStorage(positionStorage).previewTradePosition(_params);
    }

    function positionDetail(
        address _factory,
        bytes32 _positionKey
    ) public view returns (IPositionStorage.TradePosition memory) {
        address positionStorage = IFactory(_factory).positionStorage();
        uint256 index = IPositionStorage(positionStorage).positionIndex(
            _positionKey
        );
        return IPositionStorage(positionStorage).position(index - 1);
    }

    function positionDetailByStorage(
        address _positionStorage,
        bytes32 _positionKey
    ) public view returns (IPositionStorage.TradePosition memory) {
        uint256 index = IPositionStorage(_positionStorage).positionIndex(
            _positionKey
        );
        return IPositionStorage(_positionStorage).position(index - 1);
    }

    function allUserPositions(
        address _factory,
        address _user
    ) public view returns (TradePosition[] memory) {
        address positionStorage = IFactory(_factory).positionStorage();
        uint256 length = IPositionStorage(positionStorage).userPositionLength(
            _user
        );
        TradePosition[] memory positions = new TradePosition[](length);
        for (uint256 i = 0; i < length; i++) {
            bytes32 positionKey = IPositionStorage(positionStorage)
                .positionKeyByUser(_user, i);
            IPositionStorage.TradePosition
                memory detail = positionDetailByStorage(
                    positionStorage,
                    positionKey
                );
            positions[i].detail = detail;
            positions[i].pair = pair(detail.pool, detail.baseToken.id);
            address collateralAddress = detail.collateral.id;
            string memory collateralSymbol = IERC20(collateralAddress).symbol();
            positions[i].collateral = Token({
                token: detail.collateral.id,
                name: IERC20(collateralAddress).name(),
                symbol: collateralSymbol,
                decimals: IERC20(collateralAddress).decimals()
            });
        }
        return positions;
    }
}
