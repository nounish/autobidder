// SPDX-License-Identifier: GPL-3.0

import {ENSResolver} from "src/ENSResolver.sol";

pragma solidity 0.8.19;

contract Resolver is ENSResolver {
    constructor() {}

    function setName(string memory) external pure returns (bytes32) {
        return bytes32(0);
    }
}
