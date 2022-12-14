// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../src/Factory.sol";

contract DeployFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new BidderFactory();
        vm.stopBroadcast();
    }
}
