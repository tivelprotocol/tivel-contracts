// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;
pragma abicoder v2;

import "./libraries/PoolAddress.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/INonfungiblePositionManager.sol";
import "./interfaces/INonfungibleTokenPositionDescriptor.sol";
import "./interfaces/IPool.sol";
import "./base/LiquidityManagement.sol";
import "./base/PeripheryImmutableState.sol";
import "./base/DelegateMulticall.sol";
import "./base/ERC721Permit.sol";
import "./base/PeripheryValidation.sol";
import "./base/SelfPermit.sol";

/// @title NFT positions
/// @notice Wraps positions in the ERC721 non-fungible token interface
contract NonfungiblePositionManager is
    INonfungiblePositionManager,
    Multicall,
    ERC721Permit,
    PeripheryImmutableState,
    LiquidityManagement,
    PeripheryValidation,
    SelfPermit
{
    struct Position {
        // the nonce for permits
        uint96 nonce;
        // the address that is approved for spending this token
        address operator;
        uint80 poolId;
        address token;
        uint256 liquidity;
        uint256 feeDebt;
        uint256 pendingFee;
        uint256 withdrawingLiquidity;
    }

    mapping(address => uint80) private _poolIds;

    mapping(uint80 => address) private _poolIdToPoolToken;

    mapping(uint256 => Position) private _positions;

    /// @dev The ID of the next token that will be minted. Skips 0
    uint176 private _nextId = 1;
    /// @dev The ID of the next pool that is used for the first time. Skips 0
    uint80 private _nextPoolId = 1;

    /// @dev The address of the token descriptor contract, which handles generating token URIs for position tokens
    address private _tokenDescriptor;

    error Forbidden(address sender);
    error InvalidTokenID(uint256 tokenId);
    error InsufficientOutput();
    error EmptyArrays();
    error NotCleared(uint256 tokenId);

    constructor(
        address _factory,
        address _WETH9,
        address _tokenDescriptor_
    )
        ERC721Permit("Tivel V1 Positions NFT-V1", "TIVEL-V1-POS", "1")
        PeripheryImmutableState(_factory, _WETH9)
    {
        _tokenDescriptor = _tokenDescriptor_;
    }

    function setTokenDescriptor(address _tokenDescriptor_) external {
        if (msg.sender != IFactory(factory).manager())
            revert Forbidden(msg.sender);
        _tokenDescriptor = _tokenDescriptor_;
    }

    /// @inheritdoc INonfungiblePositionManager
    function positions(
        uint256 _tokenId
    )
        external
        view
        override
        returns (
            uint96 nonce,
            address operator,
            address token,
            uint256 liquidity,
            uint256 withdrawingLiquidity,
            uint256 claimableFee
        )
    {
        Position memory position = _positions[_tokenId];
        if (position.poolId == 0) revert InvalidTokenID(_tokenId);
        IPool pool = IPool(
            PoolAddress.computeAddress(poolDeployer, position.token)
        );
        uint256 accFeePerShare = pool.accFeePerShare();
        uint256 precision = pool.precision();
        uint256 fee = position.pendingFee +
            (accFeePerShare * position.liquidity) /
            precision -
            position.feeDebt;
        return (
            position.nonce,
            position.operator,
            position.token,
            position.liquidity,
            position.withdrawingLiquidity,
            fee
        );
    }

    /// @dev Caches a pool token
    function cachePoolToken(
        address _pool,
        address _token
    ) private returns (uint80 poolId) {
        poolId = _poolIds[_pool];
        if (poolId == 0) {
            _poolIds[_pool] = (poolId = _nextPoolId++);
            _poolIdToPoolToken[poolId] = _token;
        }
    }

    /// @inheritdoc INonfungiblePositionManager
    function mint(
        MintParams calldata _params
    )
        external
        payable
        override
        checkDeadline(_params.deadline)
        returns (uint256 tokenId)
    {
        IPool pool;
        pool = addLiquidity(_params.token, _params.liquidity, address(this));

        _mint(_params.to, (tokenId = _nextId++));

        uint256 accFeePerShare = pool.accFeePerShare();
        uint256 precision = pool.precision();
        uint256 feeDebt = (accFeePerShare * _params.liquidity) / precision;

        // idempotent set
        uint80 poolId = cachePoolToken(address(pool), _params.token);

        _positions[tokenId] = Position({
            nonce: 0,
            operator: address(0),
            poolId: poolId,
            token: _params.token,
            liquidity: _params.liquidity,
            feeDebt: feeDebt,
            pendingFee: 0,
            withdrawingLiquidity: 0
        });

        emit IncreaseLiquidity(tokenId, _params.token, _params.liquidity);
    }

    modifier isAuthorizedForToken(uint256 _tokenId) {
        require(_isApprovedOrOwner(msg.sender, _tokenId), "Not approved");
        _;
    }

    function tokenURI(
        uint256 _tokenId
    ) public view override(ERC721, IERC721Metadata) returns (string memory) {
        require(_exists(_tokenId));
        return
            INonfungibleTokenPositionDescriptor(_tokenDescriptor).tokenURI(
                this,
                _tokenId
            );
    }

    /// @inheritdoc INonfungiblePositionManager
    function increaseLiquidity(
        IncreaseLiquidityParams calldata _params
    ) external payable override checkDeadline(_params.deadline) {
        Position storage position = _positions[_params.tokenId];

        IPool pool;
        pool = addLiquidity(position.token, _params.liquidity, address(this));

        uint256 accFeePerShare = pool.accFeePerShare();
        uint256 precision = pool.precision();
        if (position.liquidity > 0) {
            position.pendingFee +=
                (accFeePerShare * position.liquidity) /
                precision -
                position.feeDebt;
        }
        position.liquidity += _params.liquidity;
        position.feeDebt = (accFeePerShare * position.liquidity) / precision;

        emit IncreaseLiquidity(
            _params.tokenId,
            position.token,
            _params.liquidity
        );
    }

    /// @inheritdoc INonfungiblePositionManager
    function addDecreaseLiquidityRequest(
        DecreaseLiquidityParams calldata _params
    )
        external
        payable
        override
        isAuthorizedForToken(_params.tokenId)
        checkDeadline(_params.deadline)
    {
        require(_params.liquidity > 0);
        Position storage position = _positions[_params.tokenId];

        uint256 positionLiquidity = position.liquidity;
        if (
            positionLiquidity <
            _params.liquidity + position.withdrawingLiquidity
        ) revert InsufficientOutput();
        position.withdrawingLiquidity += _params.liquidity;

        IPool pool = IPool(
            PoolAddress.computeAddress(poolDeployer, position.token)
        );
        uint256 requestIndex = pool.addBurnRequest(
            _params.liquidity,
            msg.sender,
            abi.encode(_params.tokenId)
        );

        emit AddDecreaseLiquidityRequest(
            _params.tokenId,
            position.token,
            _params.liquidity,
            requestIndex
        );
    }

    /// @inheritdoc IBurnCallback
    function burnCallback(
        uint256 _liquidity,
        bytes calldata _data
    ) external override {
        uint256 tokenId = abi.decode(_data, (uint256));
        Position storage position = _positions[tokenId];
        CallbackValidation.verifyCallback(poolDeployer, position.token);

        if (position.withdrawingLiquidity < _liquidity)
            revert InsufficientOutput();
        IPool pool = IPool(msg.sender);

        uint256 accFeePerShare = pool.accFeePerShare();
        uint256 precision = pool.precision();
        if (position.liquidity > 0) {
            position.pendingFee +=
                (accFeePerShare * position.liquidity) /
                precision -
                position.feeDebt;
        }
        position.liquidity -= _liquidity;
        position.withdrawingLiquidity -= _liquidity;
        position.feeDebt = (accFeePerShare * position.liquidity) / precision;

        emit DecreaseLiquidity(tokenId, position.token, _liquidity);
    }

    function _collect(
        uint256 _tokenId,
        address _to
    ) internal isAuthorizedForToken(_tokenId) returns (uint256 amount) {
        Position storage position = _positions[_tokenId];
        IPool pool = IPool(
            PoolAddress.computeAddress(poolDeployer, position.token)
        );

        uint256 accFeePerShare = pool.accFeePerShare();
        uint256 precision = pool.precision();
        if (position.liquidity > 0) {
            position.pendingFee +=
                (accFeePerShare * position.liquidity) /
                precision -
                position.feeDebt;
        }
        position.feeDebt = (accFeePerShare * position.liquidity) / precision;

        amount = position.pendingFee;
        pool.collect(_to, amount);
        position.pendingFee = 0;

        emit Collect(_tokenId, _to, amount);
    }

    /// @inheritdoc INonfungiblePositionManager
    function collect(
        CollectParams calldata _params
    ) external payable override returns (uint256 amount) {
        if (_params.tokenIds.length == 0) revert EmptyArrays();
        // allow collecting to the nft position manager address with address 0
        address to = _params.to == address(0) ? address(this) : _params.to;

        for (uint256 i; i < _params.tokenIds.length; i++) {
            amount += _collect(_params.tokenIds[i], to);
        }
    }

    /// @inheritdoc INonfungiblePositionManager
    function burn(
        uint256 _tokenId
    ) external payable override isAuthorizedForToken(_tokenId) {
        Position storage position = _positions[_tokenId];
        if (position.liquidity > 0 || position.pendingFee > 0)
            revert NotCleared(_tokenId);
        delete _positions[_tokenId];
        _burn(_tokenId);
    }

    function _getAndIncrementNonce(
        uint256 tokenId
    ) internal override returns (uint256) {
        return uint256(_positions[tokenId].nonce++);
    }

    /// @inheritdoc IERC721
    function getApproved(
        uint256 tokenId
    ) public view override(ERC721, IERC721) returns (address) {
        require(
            _exists(tokenId),
            "ERC721: approved query for nonexistent token"
        );

        return _positions[tokenId].operator;
    }

    /// @dev Overrides _approve to use the operator in the position, which is packed with the position permit nonce
    function _approve(address to, uint256 tokenId) internal override(ERC721) {
        _positions[tokenId].operator = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }
}
