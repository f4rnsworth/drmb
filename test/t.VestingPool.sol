// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "src/Transfer.sol"; // Your VestingPool contract
import "src/MockUsdc.sol"; // Your MockUSDC contract

contract VestingPoolTest is Test {
    VestingPool vestingPool;
    MockUSDC usdc; // Use MockUSDC instead of MockERC20
    address owner = address(this);
    address user1 = address(0x1);
    address user2 = address(0x2);
    uint256 constant ONE_YEAR = 365 days;
    uint256 constant MEMBERSHIP_FEE = 25 * 10 ** 6;
    uint256 constant MAX_DEPOSIT = 2500 * 10 ** 6;
    uint256 roundStartTime;

    function setUp() public {
        // Deploy MockUSDC
        usdc = new MockUSDC();

        // Set start time
        roundStartTime = block.timestamp + 1 days;

        // Deploy VestingPool with MockUSDC address
        vestingPool = new VestingPool(owner, address(usdc), roundStartTime);
    }

    function testDeployment() public {
        // Check that the usdcToken address in VestingPool matches the MockUSDC address
        assertEq(address(vestingPool.usdcToken()), address(usdc));

        // Check roundStartDate and dispersalDate
        assertEq(vestingPool.roundStartDate(), roundStartTime);
        assertEq(vestingPool.dispersalDate(), roundStartTime + ONE_YEAR);
        assertFalse(vestingPool.roundActive()); // Round starts inactive
    }

    function testOwnerPermissions() public {
        // Ensure only the owner can set the round start date
        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                user1
            )
        );
        vm.prank(user1);
        vestingPool.setRoundStartDate(block.timestamp + 1 days);
    }

    function testAllowListManagement() public {
        // Add user1 to the allow list and verify
        vestingPool.addToAllowList(user1);
        assertTrue(vestingPool.allowList(user1));

        // Remove user1 from the allow list and verify
        vestingPool.removeFromAllowList(user1);
        assertFalse(vestingPool.allowList(user1));
    }

    function testMembershipPayment() public {
        // Mint USDC to user1 for membership fee
        usdc.mint(user1, MEMBERSHIP_FEE);

        // Approve VestingPool to spend USDC
        vm.startPrank(user1);
        usdc.approve(address(vestingPool), MEMBERSHIP_FEE);

        // Pay membership fee
        vestingPool.payMembership();

        // Verify membership expiry
        assertEq(
            vestingPool.membershipExpiry(user1),
            block.timestamp + ONE_YEAR
        );
        vm.stopPrank();
    }

    function testDepositFunctionality() public {
        // Add user1 to the allow list
        vestingPool.addToAllowList(user1);

        // Mint USDC to user1 for deposit and membership fee
        usdc.mint(user1, MAX_DEPOSIT + MEMBERSHIP_FEE);

        // Approve VestingPool to spend USDC (enough for both membership fee and deposit)
        vm.startPrank(user1);
        usdc.approve(address(vestingPool), MAX_DEPOSIT + MEMBERSHIP_FEE);

        // Log allowance and balance before payMembership
        console.log(
            "Allowance Before PayMembership:",
            usdc.allowance(user1, address(vestingPool))
        );
        console.log("Balance Before PayMembership:", usdc.balanceOf(user1));

        // Pay membership fee (this will use 25 USDC of the allowance)
        vestingPool.payMembership();

        // Log allowance and balance after payMembership
        console.log(
            "Allowance After PayMembership:",
            usdc.allowance(user1, address(vestingPool))
        );
        console.log("Balance After PayMembership:", usdc.balanceOf(user1));

        // Ensure deposit is made before roundStartDate
        vm.warp(roundStartTime - 1); // Move time to just before roundStartDate

        // Log allowance and balance before deposit
        console.log(
            "Allowance Before Deposit:",
            usdc.allowance(user1, address(vestingPool))
        );
        console.log("Balance Before Deposit:", usdc.balanceOf(user1));

        // Deposit funds (this will use 2500 USDC of the allowance)
        vestingPool.deposit(MAX_DEPOSIT);
        vm.stopPrank();

        // Log allowance and balance after deposit
        console.log(
            "Allowance After Deposit:",
            usdc.allowance(user1, address(vestingPool))
        );
        console.log("Balance After Deposit:", usdc.balanceOf(user1));

        // Verify deposit funds
        assertEq(vestingPool.depositFunds(), MAX_DEPOSIT);
        assertTrue(vestingPool.roundActive()); // Round activated by deposit
    }

    function testTransferToOwner() public {
        // Add user1 to the allow list
        vestingPool.addToAllowList(user1);

        // Mint USDC to user1 for deposit
        usdc.mint(user1, MAX_DEPOSIT + MEMBERSHIP_FEE);

        // Approve VestingPool to spend USDC
        vm.startPrank(user1);
        usdc.approve(address(vestingPool), MAX_DEPOSIT + MEMBERSHIP_FEE);

        // Pay membership fee and deposit funds
        vestingPool.payMembership();
        vestingPool.deposit(MAX_DEPOSIT);
        vm.stopPrank();

        // Fast-forward time to after the dispersal date
        vm.warp(roundStartTime + 1 days);

        // Transfer funds to owner
        uint256 balanceBefore = usdc.balanceOf(owner);
        vestingPool.transferToOwner();

        // Verify owner's balance increased by MAX_DEPOSIT
        assertEq(usdc.balanceOf(owner), balanceBefore + MAX_DEPOSIT);
    }

    function testWithdrawAfterDispersal() public {
        vestingPool.addToAllowList(user1);
        usdc.mint(user1, MAX_DEPOSIT + MEMBERSHIP_FEE);
        vm.startPrank(user1);
        usdc.approve(address(vestingPool), MAX_DEPOSIT + MEMBERSHIP_FEE);
        vestingPool.payMembership();
        vestingPool.deposit(MAX_DEPOSIT);
        vm.stopPrank();

        vm.warp(roundStartTime + ONE_YEAR + 1 days);
        uint256 dispersalAmount = (MAX_DEPOSIT * 106) / 100; // 2650 USDC
        usdc.mint(owner, dispersalAmount);
        vm.prank(owner);
        usdc.approve(address(vestingPool), dispersalAmount);
        vm.prank(owner);
        vestingPool.depositForDispersal(dispersalAmount); // Use full amount

        // Optional: Debug logs (can remove after fix confirmed)
        console.log(
            "Contract USDC balance:",
            usdc.balanceOf(address(vestingPool))
        );
        console.log("dispersalFunds:", vestingPool.dispersalFunds());
        console.log("Owner USDC balance:", usdc.balanceOf(owner));

        uint256 balanceBefore = usdc.balanceOf(user1);
        vm.prank(user1);
        vestingPool.withdraw();
        assertEq(
            usdc.balanceOf(user1),
            balanceBefore + MAX_DEPOSIT + ((MAX_DEPOSIT * 6) / 100)
        );
    }

    // New tests for roundStartDate and roundActive
    function testSetRoundStartDateBeforeDeposits() public {
        uint256 newStartDate = block.timestamp + 2 days;
        vestingPool.setRoundStartDate(newStartDate);
        assertEq(vestingPool.roundStartDate(), newStartDate);
        assertEq(vestingPool.dispersalDate(), newStartDate + ONE_YEAR);
        assertFalse(vestingPool.roundActive());
    }

    function testSetRoundStartDateAfterDepositsFails() public {
        vestingPool.addToAllowList(user1);
        usdc.mint(user1, MAX_DEPOSIT + MEMBERSHIP_FEE);
        vm.startPrank(user1);
        usdc.approve(address(vestingPool), MAX_DEPOSIT + MEMBERSHIP_FEE);
        vestingPool.payMembership();
        vestingPool.deposit(MAX_DEPOSIT);
        vm.stopPrank();

        vm.expectRevert("Cannot modify an active round");
        vestingPool.setRoundStartDate(block.timestamp + 2 days);
    }

    function testSetRoundStartDateWithFundsFails() public {
        vestingPool.addToAllowList(user1);
        usdc.mint(user1, MAX_DEPOSIT + MEMBERSHIP_FEE);
        vm.startPrank(user1);
        usdc.approve(address(vestingPool), MAX_DEPOSIT + MEMBERSHIP_FEE);
        vestingPool.payMembership();
        vestingPool.deposit(MAX_DEPOSIT);
        vm.stopPrank();

        vm.expectRevert(); // Less strict: any revert is fine
        vestingPool.setRoundStartDate(block.timestamp + 2 days);
    }

    function testSetRoundStartDateInPastFails() public {
        vm.warp(roundStartTime + 1 days); // Move time past initial roundStartTime
        vm.expectRevert("Start date must be in the future");
        vestingPool.setRoundStartDate(block.timestamp - 1 days);
    }

    function testResetForNewRoundBeforeCompletionFails() public {
        vestingPool.addToAllowList(user1);
        usdc.mint(user1, MAX_DEPOSIT + MEMBERSHIP_FEE);
        vm.startPrank(user1);
        usdc.approve(address(vestingPool), MAX_DEPOSIT + MEMBERSHIP_FEE);
        vestingPool.payMembership();
        vestingPool.deposit(MAX_DEPOSIT);
        vm.stopPrank();

        vm.warp(roundStartTime + 1 days);
        vm.expectRevert("Current round not complete");
        vestingPool.resetForNewRound(block.timestamp + 1 days);
    }

    function testResetForNewRoundAfterCompletion() public {
        vestingPool.addToAllowList(user1);
        usdc.mint(user1, MAX_DEPOSIT + MEMBERSHIP_FEE);
        vm.startPrank(user1);
        usdc.approve(address(vestingPool), MAX_DEPOSIT + MEMBERSHIP_FEE);
        vestingPool.payMembership();
        vestingPool.deposit(MAX_DEPOSIT);
        vm.stopPrank();

        vm.warp(roundStartTime + 1 days);
        vestingPool.transferToOwner();

        vm.warp(roundStartTime + ONE_YEAR + 1 days);
        usdc.mint(owner, (MAX_DEPOSIT * 106) / 100);
        usdc.approve(address(vestingPool), (MAX_DEPOSIT * 106) / 100);
        vm.prank(owner);
        vestingPool.depositForDispersal((MAX_DEPOSIT * 106) / 100);

        vm.prank(user1);
        vestingPool.withdraw();
        assertEq(vestingPool.dispersalFunds(), 0); // Verify dispersalFunds is 0

        uint256 newStartDate = block.timestamp + 1 days;
        vestingPool.resetForNewRound(newStartDate);
        assertEq(vestingPool.roundStartDate(), newStartDate);
        assertEq(vestingPool.dispersalDate(), newStartDate + ONE_YEAR);
        assertFalse(vestingPool.roundActive());
    }
}
