// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IWETH} from "./IWETH.sol";

contract Swapper {
    // --- Immutable config ---
    address public immutable weth; // WETH address
    address public immutable dai; // DAI address
    address public immutable governor;
    address public immutable uniswapRouter; // Uniswap V3 Router

    // --- State ---
    bool public hasSwapped;
    uint256 public totalDeposited;

    mapping(address => uint256) public deposited;
    mapping(address => uint256) public withdrawable;

    // --- Participant tracking ---
    address[] private _participants;
    mapping(address => bool) private _isParticipant;

    constructor(address _weth, address _dai, address _uniswapRouter) {
        weth = _weth;
        dai = _dai;
        governor = msg.sender;
        uniswapRouter = _uniswapRouter;
    }

    // Deposit ETH via function call
    function provide() external payable {
        require(!hasSwapped, "Swapper: already swapped");
        require(msg.value > 0, "Swapper: amount must be > 0");

        // Wrap ETH to WETH
        IWETH(weth).deposit{value: msg.value}();

        deposited[msg.sender] += msg.value;
        totalDeposited += msg.value;

        _track(msg.sender);
    }

    // Allow direct ETH transfers
    receive() external payable {
        require(!hasSwapped, "Swapper: already swapped");
        require(msg.value > 0, "Swapper: amount must be > 0");

        // Wrap ETH to WETH
        IWETH(weth).deposit{value: msg.value}();

        deposited[msg.sender] += msg.value;
        totalDeposited += msg.value;

        _track(msg.sender);
    }

    function cancel() external {
        require(!hasSwapped, "Swapper: already swapped");
        uint256 amount = deposited[msg.sender];
        require(amount > 0, "Swapper: nothing to cancel");

        deposited[msg.sender] = 0;
        totalDeposited -= amount;

        // Unwrap WETH to ETH and send
        IWETH(weth).withdraw(amount);
        payable(msg.sender).transfer(amount);
    }

    function swap() external {
        require(!hasSwapped, "Swapper: already swapped");
        require(totalDeposited > 0, "Swapper: nothing to swap");

        hasSwapped = true;

        // Approve Uniswap Router to spend WETH
        IERC20(weth).approve(uniswapRouter, totalDeposited);

        // Perform swap via Uniswap V3 (WETH -> DAI)
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: weth,
            tokenOut: dai,
            fee: 3000, // 0.3% fee pool
            recipient: address(this),
            deadline: block.timestamp + 15 minutes,
            amountIn: totalDeposited,
            amountOutMinimum: 0, // For simplicity; add slippage protection in production
            sqrtPriceLimitX96: 0
        });

        uint256 amountOut = ISwapRouter(uniswapRouter).exactInputSingle(params);

        // Distribute DAI to withdrawable balances
        for (uint256 i = 0; i < _participants.length; ++i) {
            address user = _participants[i];
            uint256 userDeposit = deposited[user];
            if (userDeposit > 0) {
                uint256 userShare = (userDeposit * amountOut) / totalDeposited;
                withdrawable[user] = userShare;
                deposited[user] = 0;
            }
        }
    }

    function withdraw() external {
        uint256 amount = withdrawable[msg.sender];
        require(amount > 0, "Swapper: nothing to withdraw");

        withdrawable[msg.sender] = 0;
        IERC20(dai).transfer(msg.sender, amount);
    }

    function _track(address user) internal {
        if (!_isParticipant[user]) {
            _participants.push(user);
            _isParticipant[user] = true;
        }
    }
}