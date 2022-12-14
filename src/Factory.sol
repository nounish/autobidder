// SPDX-License-Identifier: GPL-3.0

import "./Doc.sol";
import {Bidder} from "./Bidder.sol";
import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import {INounsAuctionHouse} from "./external/interfaces/INounsAuctionHouse.sol";

pragma solidity 0.8.19;

contract BidderFactory {
    event CreateBidder(address b);

    /// @notice Deploy a new Federation AutoBidder
    /// @param t The address of the Nouns token contract
    /// @param ah The address of the Nouns Auction House contract
    /// @param _owner The address that should be the owner of the AutoBidder
    /// @param cfg The configuration for the AutoBidder
    function deploy(address t, address ah, address _owner, Bidder.Config memory cfg)
        external
        payable
        returns (address)
    {
        Bidder b = new Bidder{value: msg.value}(IERC721(t), INounsAuctionHouse(ah), _owner, cfg);

        emit CreateBidder(address(b));

        return address(b);
    }
}
