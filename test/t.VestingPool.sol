// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Transfer.sol";
import "../src/MockUsdc.sol";

contract VestingPoolTest is Test {
    VestingPool vestingPool;
    MockUSDC usdc;
    address owner;
    address user1;
    address user2;

    uint256 constant APY = 8;
    uint256 constant DEPOSIT_AMOUNT = 1000e6; // 1000 USDC
    uint256 startDate;
    uint256 oneYear = 365 days;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        startDate = block.timestamp + 60; // Start in 1 min

        // Deploy Mock USDC Token
        usdc = new MockUSDC();

        // Deploy Vesting Pool
        vestingPool = new VestingPool(address(usdc), startDate);

        // Fund users with mock USDC
        usdc.mint(user1, DEPOSIT_AMOUNT);
        usdc.mint(user2, DEPOSIT_AMOUNT);
    }

    function testDeposit() public {
        vm.startPrank(user1);
        usdc.approve(address(vestingPool), DEPOSIT_AMOUNT);
        vestingPool.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        assertEq(vestingPool.userBalances(user1), DEPOSIT_AMOUNT);
    }

    function testTransferToOwner() public {
        // User deposits
        vm.startPrank(user1);
        usdc.approve(address(vestingPool), DEPOSIT_AMOUNT);
        vestingPool.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Fast forward to start date
        vm.warp(startDate + 1);

        // Transfer funds to owner
        uint256 ownerBalanceBefore = usdc.balanceOf(owner);
        vestingPool.transferToOwner();
        uint256 ownerBalanceAfter = usdc.balanceOf(owner);

        assertEq(ownerBalanceAfter - ownerBalanceBefore, DEPOSIT_AMOUNT);
    }

    function testWithdrawAfterVesting() public {
        // User deposits funds
        vm.startPrank(user1);
        usdc.approve(address(vestingPool), DEPOSIT_AMOUNT);
        vestingPool.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Simulate owner returning funds + interest
        uint256 interest = (DEPOSIT_AMOUNT * APY) / 100;
        uint256 totalReturn = DEPOSIT_AMOUNT + interest;
        usdc.mint(address(vestingPool), totalReturn);

        // Fast forward to 12 months later
        vm.warp(startDate + oneYear);

        // User withdraws
        vm.startPrank(user1);
        vestingPool.withdraw();
        vm.stopPrank();

        assertEq(usdc.balanceOf(user1), totalReturn);
    }
}
