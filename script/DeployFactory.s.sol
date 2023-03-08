// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {BidderFactory} from "../src/Factory.sol";
import {Bidder} from "../src/Bidder.sol";

contract DeployFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        Bidder b = new Bidder();
        new BidderFactory(address(b));
        vm.stopBroadcast();
    }
}
