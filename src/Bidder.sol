// SPDX-License-Identifier: GPL-3.0

import "./Doc.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {Pausable} from "openzeppelin-contracts/security/Pausable.sol";
import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import {INounsAuctionHouse} from "./external/interfaces/INounsAuctionHouse.sol";

pragma solidity 0.8.19;

contract Bidder is Ownable, Pausable {
    /// Base gas to refund
    uint256 public constant REFUND_BASE_GAS = 36000;

    // Max priority fee used for refunds
    uint256 public constant MAX_REFUND_PRIORITY_FEE = 2 gwei;

    /// Max gas units that will be refunded to a caller
    uint256 public constant MAX_REFUND_GAS_USED = 200_000;

    /// Max base fee to refund a caller
    uint256 public constant MAX_REFUND_BASE_FEE = 200 gwei;

    // Returned when a caller attempts to create a bid but this contract
    // is already the highest bidder
    error AlreadyHighestBidder();

    // Returned when the caller attempts to create a bid but the auction has
    // ended
    error AuctionEnded();

    // Returned when the caller attempts to call withdraw for a token auction
    // that has not ended yet
    error AuctionNotEnded();

    // Returned when the owner attempts to withdraw funds but the last auction bid
    // on has not been settled yet
    error AuctionNotSettled();

    // Returned when an attempt is made to place a bid that exceeds the max
    // configurable amount
    error MaxBidExceeded();

    // Returned when an attempt is made to withdraw a token that has not been bid on
    error NoBidFoundForToken(uint256 tokenId);

    // Returned when an attempt is made to withdraw a token that has already been
    // transferred to the receiver
    error AlreadyWithdrawn();

    // Returned when an attempt is made to place a bid outside of the auction
    // bid window
    error NotInBidWindow();

    // Returned when updating config that does not have the receiver set
    error InvalidReceiver();

    // Returned when an attempt to withdraw funds or update config has been made
    // and the last bidder was not tipped for winning the auction
    error TipOwed();

    // Emitted when a caller places a bid
    event BidMade(address caller, uint256 tokenId, uint256 amount);

    // Emitted when a caller receives a gas refund
    event GasRefund(address indexed caller, uint256 refundAmount, bool refundSent);

    // Emitted when a token is withdrawn and last bidder tipped
    event WithdrawAndTip(
        address indexed caller, address indexed tipTo, uint256 tokenId, uint256 tipAmount, bool tipSent
    );

    // Emitted when config is updated
    event ConfigUpdate(Config config);

    // The structure of the config for this bidder
    struct Config {
        // Max bid that can be placed in an auction
        uint256 maxBid;
        // Min bid that can be placed in an auction
        uint256 minBid;
        // Time in seconds a bid can be placed before auction end time
        uint256 bidWindow;
        // Tip rewarded for caller winning auction
        uint256 tip;
        // Address that will receive tokens when withdrawn
        address receiver;
    }

    // The structure of the last bid as a record for tipping purposes
    struct LastBid {
        // The time that the auction bid on ends
        uint256 auctionEndTime;
        // Last address to make the bid
        address bidder;
        // If the last bid was a winning bid and the token was transferred / settled
        bool settled;
    }

    // The ERC721 token address that is being bid on
    IERC721 public immutable token;

    // The auction house address
    INounsAuctionHouse public immutable auctionHouse;

    // The last token id that was bid on
    uint256 public lastTokenId;

    // The config for this bidder
    Config internal config;

    // The last bidder for each token id
    mapping(uint256 => LastBid) internal lastBidForToken;

    constructor(IERC721 t, INounsAuctionHouse ah, address _owner, Config memory cfg) payable {
        token = t;
        auctionHouse = ah;
        config = cfg;

        // allow ownership to be transferred during instantiation; i.e. when
        // created by factory impl
        if (msg.sender != _owner) {
            _transferOwnership(_owner);
        }
    }

    /// @notice Submit a bid to the auction house
    function bid() external whenNotPaused returns (uint256, uint256) {
        uint256 startGas = gasleft();

        (uint256 nounId, uint256 amount,, uint256 endTime, address bidder,) = auctionHouse.auction();

        if (block.timestamp > endTime) {
            revert AuctionEnded();
        }

        if (block.timestamp + config.bidWindow < endTime) {
            revert NotInBidWindow();
        }

        if (bidder == address(this)) {
            revert AlreadyHighestBidder();
        }

        uint256 value = auctionHouse.reservePrice();
        if (amount > 0) {
            value = amount + ((amount * auctionHouse.minBidIncrementPercentage()) / 100);
        }

        if (value < config.minBid) {
            value = config.minBid;
        }

        if (value > config.maxBid) {
            revert MaxBidExceeded();
        }

        auctionHouse.createBid{value: value}(nounId);

        lastBidForToken[nounId] = LastBid({bidder: msg.sender, auctionEndTime: endTime, settled: false});
        lastTokenId = nounId;

        emit BidMade(msg.sender, nounId, value);

        _refundGas(startGas);

        return (nounId, value);
    }

    /**
     * @notice Withdraw the given token id from this contract
     * @dev Reentrancy is defended against with `lb.settled` check
     */
    function withdraw(uint256 tId) external {
        uint256 startGas = gasleft();

        LastBid storage lb = lastBidForToken[tId];
        if (lb.bidder == address(0)) {
            revert NoBidFoundForToken(tId);
        }

        if (lb.settled) {
            revert AlreadyWithdrawn();
        }

        if (block.timestamp < lb.auctionEndTime) {
            revert AuctionNotEnded();
        }

        lb.settled = true;

        token.transferFrom(address(this), config.receiver, tId);

        _tip(tId, lb.bidder);

        _refundGas(startGas);
    }

    /**
     * @notice Ensures that the last auction has been settled and that if an
     * auction was ever won all debts have been paid
     */
    modifier allDebtsPaid() {
        // auction that was last bid on has been settled
        (uint256 nounId,,,,,) = auctionHouse.auction();
        if (nounId == lastTokenId) {
            revert AuctionNotSettled();
        }

        // if this contract owns any tokens it means a tip has not been paid
        if (token.balanceOf(address(this)) > 0) {
            revert TipOwed();
        }

        _;
    }

    /// @notice Withdraw contract balance
    function withdrawBalance() external onlyOwner whenPaused allDebtsPaid {
        (bool sent,) = owner().call{value: address(this).balance}("");
        require(sent, "failed to withdraw ether");
    }

    /// @notice Handles updating the config for this bidder
    function setConfig(Config calldata cfg) external onlyOwner whenPaused allDebtsPaid {
        if (cfg.receiver == address(0)) {
            revert InvalidReceiver();
        }

        config = cfg;
        emit ConfigUpdate(cfg);
    }

    /// @notice Locks the contract to withdraw its balance or update config
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unlocks the contract to allow bidding
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Returns the config for this bidder
    function getConfig() external view returns (Config memory) {
        return config;
    }

    /// @notice Returns the last bid for the given token id
    function getLastBid(uint256 tId) external view returns (LastBid memory) {
        return lastBidForToken[tId];
    }

    /// @notice Sends tip to address
    function _tip(uint256 tId, address to) internal {
        unchecked {
            uint256 balance = address(this).balance;
            if (balance == 0) {
                return;
            }

            uint256 tipAmount = min(config.tip, balance);
            (bool tipSent,) = to.call{value: tipAmount}("");

            emit WithdrawAndTip(msg.sender, to, tId, tipAmount, tipSent);
        }
    }

    /// @notice Refunds gas spent on transaction to the caller
    function _refundGas(uint256 startGas) internal {
        unchecked {
            uint256 balance = address(this).balance;
            if (balance == 0) {
                return;
            }

            uint256 basefee = min(block.basefee, MAX_REFUND_BASE_FEE);
            uint256 gasPrice = min(tx.gasprice, basefee + MAX_REFUND_PRIORITY_FEE);
            uint256 gasUsed = min(startGas - gasleft() + REFUND_BASE_GAS, MAX_REFUND_GAS_USED);
            uint256 refundAmount = min(gasPrice * gasUsed, balance);
            (bool refundSent,) = tx.origin.call{value: refundAmount}("");
            emit GasRefund(tx.origin, refundAmount, refundSent);
        }
    }

    /// @notice Returns the min of two integers
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    receive() external payable {}
}
