// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.4;

import "./interfaces/IUserStorage.sol";

contract UserStorage is IUserStorage {
    address public manager;
    mapping(address => bool) public operator;
    mapping(address => IUserStorage.User) private userInfo;

    error Forbidden(address sender);
    error BadLengths(uint256 length0, uint256 length1);

    event SetManager(address manager);
    event SetOperator(address user, bool isOperator);
    event UpdateRef(address indexed user, address indexed ref);
    event UpdateMembership(address indexed user, uint256 membershipLevel);

    constructor() {
        manager = msg.sender;
    }

    modifier onlyManager() {
        if (msg.sender != manager) revert Forbidden(msg.sender);
        _;
    }

    modifier onlyOperator() {
        if (!operator[msg.sender]) revert Forbidden(msg.sender);
        _;
    }

    function setManager(address _manager) external onlyManager {
        manager = _manager;

        emit SetManager(_manager);
    }

    function setOperators(
        address[] memory _users,
        bool[] memory _isOperators
    ) external onlyManager {
        if (_users.length != _isOperators.length)
            revert BadLengths(_users.length, _isOperators.length);
        for (uint256 i = 0; i < _users.length; i++) {
            operator[_users[i]] = _isOperators[i];
            emit SetOperator(_users[i], _isOperators[i]);
        }
    }

    function getUserInfo(
        address _user
    ) external view override returns (IUserStorage.User memory) {
        return userInfo[_user];
    }

    function discountedFee(
        address _user,
        uint256 _fee
    ) external view override returns (uint256) {
        User memory user = userInfo[_user];
        uint256 factor = 4; // TODO: find the best factor
        uint256 discount = (_fee * user.membershipLevel) /
            (user.membershipLevel + factor);
        return _fee - discount;
    }

    function canUpdateDeadline(
        address _user
    ) external view override returns (bool) {
        // User memory user = userInfo[_user];
        // return user.membershipLevel > 0;
        return true;
    }

    function updateRef(
        address _user,
        address _ref
    ) external override onlyOperator {
        User storage user = userInfo[_user];
        if (user.id == address(0)) {
            user.id = _user;
        }
        user.ref = _ref;

        emit UpdateRef(_user, _ref);
    }

    function updateMembership(
        address _user,
        uint256 _membershipLevel
    ) external override onlyOperator {
        User storage user = userInfo[_user];
        if (user.id == address(0)) {
            user.id = _user;
        }
        user.membershipLevel = _membershipLevel;

        emit UpdateMembership(_user, _membershipLevel);
    }
}
