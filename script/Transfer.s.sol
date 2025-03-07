// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "src/Transfer.sol";

contract DeployVestingPool is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER"); // Ensure your .env file has DEPLOYER address
        address usdcToken = vm.envAddress("USDC_TOKEN"); // Set USDC token address in .env
        uint256 roundStartDate = block.timestamp + 7 days; // Example: Start 7 days from deployment

        vm.startBroadcast();
        VestingPool vestingPool = new VestingPool(
            deployer,
            usdcToken,
            roundStartDate
        );
        vm.stopBroadcast();

        console.log("VestingPool deployed at:", address(vestingPool));
    }
}
