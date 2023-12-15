// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

import "./IBurnCallback.sol";
import "./IERC721Permit.sol";
import "./IMintCallback.sol";
import "./IPeripheryImmutableState.sol";
import "./IPeripheryPayments.sol";

interface INonfungiblePositionManager is
    IMintCallback,
    IBurnCallback,
    IPeripheryPayments,
    IPeripheryImmutableState,
    IERC721Metadata,
    IERC721Enumerable,
    IERC721Permit
{
    event IncreaseLiquidity(
        uint256 indexed tokenId,
        address token,
        uint256 liquidity
    );
    event AddDecreaseLiquidityRequest(
        uint256 indexed tokenId,
        address token,
        uint256 liquidity,
        uint256 requestIndex
    );
    event DecreaseLiquidity(
        uint256 indexed tokenId,
        address token,
        uint256 liquidity
    );
    event Collect(uint256 indexed tokenId, address token, uint256 amount);

    function positions(
        uint256 tokenId
    )
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token,
            uint256 liquidity,
            uint256 claimableFee
        );

    struct MintParams {
        address token;
        uint256 liquidity;
        address to;
        uint256 deadline;
    }

    function mint(
        MintParams calldata params
    ) external payable returns (uint256 tokenId);

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 liquidity;
        uint256 deadline;
    }

    function increaseLiquidity(
        IncreaseLiquidityParams calldata params
    ) external payable;

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint256 liquidity;
        uint256 deadline;
    }

    function addDecreaseLiquidityRequest(
        DecreaseLiquidityParams calldata params
    ) external payable;

    struct CollectParams {
        uint256[] tokenIds;
        address to;
    }

    function collect(
        CollectParams calldata params
    ) external payable returns (uint256 amount);

    function burn(uint256 tokenId) external payable;
}
