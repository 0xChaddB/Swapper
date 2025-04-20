// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Swapper {
    // --- Immutable config ---
    address public immutable fromToken;
    address public immutable toToken;
    address public immutable governor;

    // --- State ---
    bool public hasSwapped;
    uint256 public totalDeposited;

    mapping(address => uint256) public deposited;
    mapping(address => uint256) public withdrawable;

    // --- Participant tracking ---
    address[] private _participants;
    mapping(address => bool) private _isParticipant;

    constructor(address _fromToken, address _toToken) {
        fromToken = _fromToken;
        toToken = _toToken;
        governor = msg.sender;
    }

    function provide(uint256 amount) external {
        require(!hasSwapped, "Swapper: already swapped");
        require(amount > 0, "Swapper: amount must be > 0");

        IERC20(fromToken).transferFrom(msg.sender, address(this), amount);
        deposited[msg.sender] += amount;
        totalDeposited += amount;

        _track(msg.sender);
    }

    function cancel() external {
        require(!hasSwapped, "Swapper: already swapped");
        uint256 amount = deposited[msg.sender];
        require(amount > 0, "Swapper: nothing to cancel");

        deposited[msg.sender] = 0;
        totalDeposited -= amount;
        IERC20(fromToken).transfer(msg.sender, amount);
    }

    function swap() external {
        require(!hasSwapped, "Swapper: already swapped");
        require(totalDeposited > 0, "Swapper: nothing to swap");

        hasSwapped = true;

        uint256 balance = IERC20(toToken).balanceOf(address(this));
        require(balance >= totalDeposited, "Swapper: insufficient toToken");

        for (uint256 i = 0; i < _participants.length; ++i) {
            address user = _participants[i];
            uint256 amount = deposited[user];
            if (amount > 0) {
                withdrawable[user] = amount;
                deposited[user] = 0;
            }
        }
    }

    function withdraw() external {
        uint256 amount = withdrawable[msg.sender];
        require(amount > 0, "Swapper: nothing to withdraw");

        withdrawable[msg.sender] = 0;
        IERC20(toToken).transfer(msg.sender, amount);
    }

    function _track(address user) internal {
        if (!_isParticipant[user]) {
            _participants.push(user);
            _isParticipant[user] = true;
        }
    }
}
