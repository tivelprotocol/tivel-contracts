// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;
pragma abicoder v2;

import "./interfaces/IERC20.sol";

contract TokenReader {
    error ZeroAddress(address addr);

    function getTokenSupplies(
        address[] memory _tokens
    ) external view returns (uint256[] memory) {
        uint256 length = _tokens.length;
        uint256[] memory supplies = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            if (_tokens[i] == address(0)) revert ZeroAddress(_tokens[i]);
            supplies[i] = IERC20(_tokens[i]).totalSupply();
        }
        return supplies;
    }

    function getTokenDecimals(
        address[] memory _tokens
    ) external view returns (uint256[] memory) {
        uint256 length = _tokens.length;
        uint256[] memory decimals = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            if (_tokens[i] == address(0)) revert ZeroAddress(_tokens[i]);
            decimals[i] = IERC20(_tokens[i]).decimals();
        }
        return decimals;
    }

    function getTokensBalance(
        address _user,
        address[] memory _tokens
    ) external view returns (uint256[] memory) {
        uint256 length = _tokens.length;
        uint256[] memory balances = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            if (_tokens[i] == address(0)) revert ZeroAddress(_tokens[i]);
            balances[i] = IERC20(_tokens[i]).balanceOf(_user);
        }
        return balances;
    }

    function getTokenBalances(
        address[] memory _users,
        address _token
    ) external view returns (uint256[] memory) {
        if (_token == address(0)) revert ZeroAddress(_token);
        uint256 length = _users.length;
        uint256[] memory balances = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            balances[i] = IERC20(_token).balanceOf(_users[i]);
        }
        return balances;
    }

    function getTokensAllowance(
        address _user,
        address[] memory _tokens,
        address _spender
    ) external view returns (uint256[] memory) {
        uint256 length = _tokens.length;
        uint256[] memory allowances = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            if (_tokens[i] == address(0)) revert ZeroAddress(_tokens[i]);
            allowances[i] = IERC20(_tokens[i]).allowance(_user, _spender);
        }
        return allowances;
    }

    function getTokenAllowances(
        address[] memory _users,
        address _token,
        address _spender
    ) external view returns (uint256[] memory) {
        if (_token == address(0)) revert ZeroAddress(_token);
        uint256 length = _users.length;
        uint256[] memory allowances = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            allowances[i] = IERC20(_token).allowance(_users[i], _spender);
        }
        return allowances;
    }
}
