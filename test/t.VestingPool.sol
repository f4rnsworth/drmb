// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "src/Transfer.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("MockUSDC", "USDC") {
        _mint(msg.sender, 1_000_000 * 10 ** 6); // Mint 1M USDC for testing
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract VestingPoolTest is Test {
    VestingPool vestingPool;
    MockUSDC usdc;
    address owner = address(1);
    address user1 = address(2);
    address user2 = address(3);

    function setUp() public {
        vm.startPrank(owner);
        usdc = new MockUSDC();
        vestingPool = new VestingPool(
            owner,
            address(usdc),
            block.timestamp + 1 days
        );
        vm.stopPrank();

        usdc.mint(user1, 5000 * 10 ** 6);
        usdc.mint(user2, 5000 * 10 ** 6);

        vm.prank(user1);
        usdc.approve(address(vestingPool), type(uint256).max);

        vm.prank(user2);
        usdc.approve(address(vestingPool), type(uint256).max);
    }

    function testMembershipPayment() public {
        vm.prank(user1);
        vestingPool.payMembership();
        assertGt(vestingPool.membershipExpiry(user1), block.timestamp);
    }

    function testDeposit() public {
        vm.prank(owner);
        vestingPool.addToAllowList(user1);

        vm.prank(user1);
        vestingPool.payMembership();

        vm.prank(user1);
        vestingPool.deposit(1000 * 10 ** 6);

        (uint256 amount, bool withdrawn) = vestingPool.memberDeposits(user1);
        assertEq(amount, 1000 * 10 ** 6);
        assertFalse(withdrawn);
    }

    function testTransferToOwner() public {
        vm.prank(owner);
        vestingPool.addToAllowList(user1);
        vm.prank(user1);
        vestingPool.payMembership();
        vm.prank(user1);
        vestingPool.deposit(1000 * 10 ** 6);

        vm.warp(block.timestamp + 2 days);
        vm.prank(owner);
        vestingPool.transferToOwner();
    }

    function testWithdraw() public {
        vm.prank(owner);
        vestingPool.addToAllowList(user1);
        vm.prank(user1);
        vestingPool.payMembership();
        vm.prank(user1);
        vestingPool.deposit(1000 * 10 ** 6);

        vm.warp(block.timestamp + 365 days);
        vm.prank(owner);
        vestingPool.depositForDispersal(1060 * 10 ** 6);
        vm.prank(user1);
        vestingPool.withdraw();
    }
}

