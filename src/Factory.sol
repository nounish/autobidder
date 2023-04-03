// SPDX-License-Identifier: GPL-3.0

import "./Doc.sol";
import {IBidder} from "./IBidder.sol";
import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {INounsAuctionHouse} from "./external/interfaces/INounsAuctionHouse.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";

pragma solidity 0.8.19;

contract BidderFactory is Ownable {
    /// The name of this contract
    string public constant name = "Federation AutoBidder Factory v0.2";

    /// The address of the Bidder implementation
    address public immutable impl;

    // The default address of the ENS resolver for setting AutoBidder reverse records
    address public resolver;

    /// Returned if there was an error deploying a minimal proxy for Bidder
    error FailedToClone();

    /// Emitted when a new Bidder is created
    event CreateBidder(address b);

    /// Emitted when the ENS resolver address is changed
    event ENSResolverChanged(address r);

    constructor(address i, address r) {
        impl = i;
        resolver = r;
    }

    /// Update the default ENS resolver used for clones
    function setENSResolver(address r) external onlyOwner {
        resolver = r;
        emit ENSResolverChanged(r);
    }

    /// Deploy a new Federation AutoBidder
    /// @param t The address of the Nouns token contract
    /// @param ah The address of the Nouns Auction House contract
    /// @param _owner The address that should be the owner of the AutoBidder
    /// @param cfg The configuration for the AutoBidder
    function clone(address t, address ah, address _owner, IBidder.Config memory cfg)
        external
        payable
        returns (address)
    {
        address inst = Clones.clone(impl);
        bytes memory s = abi.encodeWithSelector(
            IBidder.initialize.selector, IERC721(t), INounsAuctionHouse(ah), _owner, resolver, cfg
        );

        (bool success,) = inst.call{value: msg.value}(s);
        if (!success) {
            revert FailedToClone();
        }

        emit CreateBidder(inst);

        return inst;
    }
}
