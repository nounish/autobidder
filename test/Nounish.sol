// SPDX-License-Identifier: GPL-3.0

/// @title Test implementation of a Nounish NFT

import {ERC721} from "nouns-contracts/base/ERC721.sol";
import {ERC721Checkpointable} from "nouns-contracts/base/ERC721Checkpointable.sol";

pragma solidity 0.8.19;

contract NounishToken is ERC721Checkpointable {
    uint256 i;

    constructor() public ERC721("Nounish", "NOUNISH") {}

    function mint() external returns (uint256) {
        _mint(address(this), msg.sender, i);
        i++;
        return i - 1;
    }

    function burn(uint256 id) external {
        _burn(id);
    }
}
