// test/Swapper.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Swapper.sol";
import "../src/MockERC20.sol";

contract SwapperTest is Test {
    Swapper swapper;
    MockERC20 fromToken;
    MockERC20 toToken;

    address alice = address(0xA1);
    address bob = address(0xB2);

    function setUp() public {
        fromToken = new MockERC20("FromToken", "FT");
        toToken = new MockERC20("ToToken", "TT");

        swapper = new Swapper(address(fromToken), address(toToken));

        // Mint tokens to users
        fromToken.mint(alice, 1000e18);
        fromToken.mint(bob, 1000e18);
        toToken.mint(address(swapper), 1000e18); // preload toToken liquidity
    }

    function testProvide() public {
        vm.startPrank(alice);
        fromToken.approve(address(swapper), 500e18);
        swapper.provide(500e18);
        vm.stopPrank();

        assertEq(swapper.totalDeposited(), 500e18);
        assertEq(swapper.deposited(alice), 500e18);
    }

    function testCancelBeforeSwap() public {
        vm.startPrank(alice);
        fromToken.approve(address(swapper), 500e18);
        swapper.provide(500e18);
        swapper.cancel();
        vm.stopPrank();

        assertEq(swapper.totalDeposited(), 0);
        assertEq(swapper.deposited(alice), 0);
        assertEq(fromToken.balanceOf(alice), 1000e18);
    }

    function testSwapAndWithdraw() public {
        // Alice and Bob provide
        vm.startPrank(alice);
        fromToken.approve(address(swapper), 400e18);
        swapper.provide(400e18);
        vm.stopPrank();

        vm.startPrank(bob);
        fromToken.approve(address(swapper), 600e18);
        swapper.provide(600e18);
        vm.stopPrank();

        // Anyone can call swap
        swapper.swap();

        // Both can withdraw
        vm.startPrank(alice);
        swapper.withdraw();
        assertEq(toToken.balanceOf(alice), 400e18);
        vm.stopPrank();

        vm.startPrank(bob);
        swapper.withdraw();
        assertEq(toToken.balanceOf(bob), 600e18);
        vm.stopPrank();
    }

    function testCannotProvideAfterSwap() public {
        vm.startPrank(alice);
        fromToken.approve(address(swapper), 200e18);
        swapper.provide(200e18);
        vm.stopPrank();

        swapper.swap();

        vm.startPrank(bob);
        fromToken.approve(address(swapper), 200e18);
        vm.expectRevert("Swapper: already swapped");
        swapper.provide(200e18);
        vm.stopPrank();
    }

    function testCannotSwapTwice() public {
        vm.startPrank(alice);
        fromToken.approve(address(swapper), 100e18);
        swapper.provide(100e18);
        vm.stopPrank();

        swapper.swap();

        vm.expectRevert("Swapper: already swapped");
        swapper.swap();
    }

    function testCannotWithdrawBeforeSwap() public {
        vm.startPrank(alice);
        fromToken.approve(address(swapper), 100e18);
        swapper.provide(100e18);
        vm.expectRevert("Swapper: nothing to withdraw");
        swapper.withdraw();
        vm.stopPrank();
    }
}
