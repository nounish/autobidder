// SPDX-License-Identifier: GPL-3.0

import {INounsAuctionHouse} from "../src/external/interfaces/INounsAuctionHouse.sol";
import {NounsAuctionHouse} from "nouns-contracts/NounsAuctionHouse.sol";
import {NounsAuctionHouseProxyAdmin} from "nouns-contracts/proxies/NounsAuctionHouseProxyAdmin.sol";
import {NounsAuctionHouseProxy} from "nouns-contracts/proxies/NounsAuctionHouseProxy.sol";
import {WETH} from "nouns-contracts/test/WETH.sol";
import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import {NounishToken} from "./Nounish.sol";
import {BidderFactory} from "../src/Factory.sol";
import {Bidder} from "../src/Bidder.sol";
import {IBidder} from "../src/IBidder.sol";
import "forge-std/Test.sol";

pragma solidity 0.8.19;

uint256 constant RESERVE_PRICE = 0.07 ether;
uint256 constant TIME_BUFFER = 5 minutes;
uint256 constant MIN_BID_INCREMENT_PERCENTAGE = 5;
uint256 constant AUCTION_DURATION = 1 days;
uint256 constant BID_WINDOW = 5 minutes;

contract TestBidder is Test {
    INounsAuctionHouse public auctionHouse;
    IERC721 public token;
    BidderFactory public bidderFactory;
    Bidder public bidderImpl;
    Bidder public autoBidder;
    Bidder public autoBidder2;

    address internal owner;
    address internal b1;
    address internal b2;

    function setUp() public {
        // deploy all the things
        WETH weth = new WETH();
        token = new NounishToken();
        NounsAuctionHouse ah = new NounsAuctionHouse();
        NounsAuctionHouseProxyAdmin proxyAdmin = new NounsAuctionHouseProxyAdmin();
        bidderImpl = new Bidder();
        bidderFactory = new BidderFactory(address(bidderImpl));

        bytes memory initParams = abi.encodeWithSignature(
            "initialize(address,address,uint256,uint256,uint8,uint256)",
            token,
            address(weth),
            TIME_BUFFER,
            RESERVE_PRICE,
            MIN_BID_INCREMENT_PERCENTAGE,
            AUCTION_DURATION
        );

        NounsAuctionHouseProxy proxy = new NounsAuctionHouseProxy(address(ah), address(proxyAdmin), initParams);
        auctionHouse = INounsAuctionHouse(address(proxy));

        // setup accounts
        b1 = vm.addr(0xB1);
        b2 = vm.addr(0xB2);
        owner = vm.addr(0xB3);

        vm.deal(b1, 100 ether);
        vm.deal(b2, 100 ether);
        vm.deal(owner, 100 ether);

        // setup and deploy auto bidder for auction house
        IBidder.Config memory cfg = IBidder.Config({
            maxBid: 20 ether,
            minBid: 0.1 ether,
            bidWindow: BID_WINDOW,
            tip: 0.01 ether,
            receiver: owner
        });

        autoBidder =
            Bidder(payable(bidderFactory.clone{value: 100 ether}(address(token), address(auctionHouse), owner, cfg)));

        // setup second autobidder
        IBidder.Config memory cfg2 =
            IBidder.Config({maxBid: 20 ether, minBid: 0 ether, bidWindow: BID_WINDOW, tip: 0.01 ether, receiver: owner});

        autoBidder2 =
            Bidder(payable(bidderFactory.clone{value: 100 ether}(address(token), address(auctionHouse), owner, cfg2)));
    }

    // testCreateBid tests the bid function of the auto bidder
    function testCreateBid() public {
        auctionHouse.unpause();

        uint256 startingAmount = _getCurrentAuction().amount;
        assertEq(startingAmount, 0);

        // should revert if we are not in the bid window
        vm.expectRevert(abi.encodeWithSignature("NotInBidWindow()"));
        autoBidder.bid();

        vm.warp(_getCurrentAuction().endTime - BID_WINDOW);

        // autoBidder2 has no min bid so should bid RESERVE_PRICE
        (uint256 tId, uint256 bidAmount) = autoBidder2.bid();
        assertEq(bidAmount, RESERVE_PRICE);

        // should bid minBid or RESERVE_PRICE if there are no bids (whichever is greater)
        (tId, bidAmount) = autoBidder.bid();
        assertEq(bidAmount, 0.1 ether);
        assertGt(bidAmount, RESERVE_PRICE);

        // bid with a second account and ensure that the next bid made by the
        // autobidder is MIN_BID_INCREMENT_PERCENTAGE higher
        vm.prank(b2);
        uint256 value = bidAmount + (bidAmount * MIN_BID_INCREMENT_PERCENTAGE / 100);
        auctionHouse.createBid{value: value}(tId);

        (, uint256 nextBidAmount) = autoBidder.bid();
        assertEq(nextBidAmount, value + (value * MIN_BID_INCREMENT_PERCENTAGE / 100));

        // should revert if it is already the highest bidder
        vm.expectRevert(abi.encodeWithSignature("AlreadyHighestBidder()"));
        autoBidder.bid();

        // should revert if next bid would exceed the configured maximum
        vm.prank(b1);
        value = 19.5 ether;
        auctionHouse.createBid{value: value}(tId);

        vm.expectRevert(abi.encodeWithSignature("MaxBidExceeded()"));
        autoBidder.bid();

        vm.warp(_getCurrentAuction().endTime);
        auctionHouse.settleCurrentAndCreateNewAuction();
        vm.warp(_getCurrentAuction().endTime - BID_WINDOW);
        autoBidder.bid();

        // noun id should be tId + 1 since it is second mint
        assertEq(tId + 1, _getCurrentAuction().nounId);

        address lb = autoBidder.getLastBidder(tId);
        assertEq(lb, tx.origin);

        // should revert if autobidder is paused
        vm.warp(_getCurrentAuction().endTime);
        auctionHouse.settleCurrentAndCreateNewAuction();
        vm.warp(_getCurrentAuction().endTime - BID_WINDOW);

        vm.prank(owner);
        autoBidder.pause();

        vm.expectRevert(bytes("Pausable: paused"));
        autoBidder.bid();

        vm.prank(owner);
        autoBidder.unpause();
        autoBidder.bid();

        // should revert if auction has already ended
        vm.warp(_getCurrentAuction().endTime + 10 minutes);
        vm.expectRevert(bytes("Auction expired"));
        autoBidder2.bid();
    }

    // testWithdraw runs an auction and ensures that it can be withdrawn to the
    // receiver configured for the auto bidder
    function testWithdraw() public {
        auctionHouse.unpause();

        // should revert if there is no bid for the token yet
        vm.expectRevert(abi.encodeWithSelector(IBidder.NoBidFoundForToken.selector, 0));
        autoBidder.withdraw(0);

        // should revert if attempt to withdraw is before auction end time
        vm.warp(_getCurrentAuction().endTime - BID_WINDOW);
        autoBidder.bid();
        vm.expectRevert(bytes("ERC721: transfer caller is not owner nor approved"));
        autoBidder.withdraw(0);

        // should revert if the autobidder did not win (it does not own token)
        vm.prank(b1);
        auctionHouse.createBid{value: 1 ether}(0);
        vm.warp(_getCurrentAuction().endTime + 69420);

        vm.expectRevert(bytes("ERC721: transfer caller is not owner nor approved"));
        autoBidder.withdraw(0);

        // should tip the last caller of bid()
        auctionHouse.settleCurrentAndCreateNewAuction();

        vm.warp(_getCurrentAuction().endTime - BID_WINDOW);
        vm.prank(b1);
        autoBidder.bid();
        vm.warp(_getCurrentAuction().endTime + 69420);
        auctionHouse.settleCurrentAndCreateNewAuction();

        // tips are always send to the tx origin
        uint256 beforeBal = address(tx.origin).balance;
        autoBidder.withdraw(1);
        uint256 afterBal = address(tx.origin).balance;

        // b1 outbid the autobidder so it should own the token
        assertEq(b1, token.ownerOf(0));
        // owner is token receiver configured on autobidder
        assertEq(owner, token.ownerOf(1));

        assertEq(afterBal - beforeBal, 0.01 ether);

        // should revert if attempting to withdraw a token again
        vm.expectRevert(bytes("ERC721: transfer caller is not owner nor approved"));
        autoBidder.withdraw(1);

        // should allow withdraw when paused
        vm.warp(_getCurrentAuction().endTime - BID_WINDOW);
        autoBidder.bid();

        vm.prank(owner);
        autoBidder.pause();

        vm.warp(_getCurrentAuction().endTime + 69420);
        auctionHouse.settleCurrentAndCreateNewAuction();
        autoBidder.withdraw(2);

        vm.prank(owner);
        autoBidder.unpause();
    }

    function testOwnership() public {
        // owner is set during clone deployment in setUp()
        assertEq(owner, autoBidder.owner());

        auctionHouse.unpause();
        vm.warp(_getCurrentAuction().endTime);
        auctionHouse.settleCurrentAndCreateNewAuction();

        vm.prank(owner);
        autoBidder.transferOwnership(b1);

        vm.prank(b1);
        autoBidder.pause();

        // should revert if not called by owner
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        autoBidder.withdrawBalance();

        // owner should be able to withdraw remaining balance
        uint256 abBeforeBal = address(autoBidder).balance;
        uint256 b1BeforeBal = b1.balance;

        vm.prank(b1);
        autoBidder.withdrawBalance();

        assertEq(b1, autoBidder.owner());
        assertEq(0, address(autoBidder).balance);
        assertEq(abBeforeBal + b1BeforeBal, b1.balance);
    }

    function testSetConfig() public {
        auctionHouse.unpause();
        vm.warp(_getCurrentAuction().endTime);
        auctionHouse.settleCurrentAndCreateNewAuction();

        vm.prank(owner);
        autoBidder.pause();

        // verify bids change with new config
        vm.warp(_getCurrentAuction().endTime - BID_WINDOW);

        IBidder.Config memory cfg = IBidder.Config({
            maxBid: 30 ether,
            minBid: 30 ether,
            bidWindow: BID_WINDOW,
            tip: 0.01 ether,
            receiver: owner
        });

        // should revert if caller is not owner
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        autoBidder.setConfig(cfg);

        vm.prank(owner);
        autoBidder.setConfig(cfg);

        vm.prank(owner);
        autoBidder.unpause();

        // new min bid should be 30 ether
        (, uint256 bidAmount) = autoBidder.bid();
        assertEq(bidAmount, 30 ether);

        // we lost this auction, new bid that exceeds max bid should revert
        auctionHouse.createBid{value: 31.5 ether}(1);
        vm.expectRevert(abi.encodeWithSignature("MaxBidExceeded()"));
        autoBidder.bid();

        vm.prank(owner);
        autoBidder.pause();

        cfg = IBidder.Config({
            maxBid: 30 ether,
            minBid: 30 ether,
            bidWindow: BID_WINDOW,
            tip: 0.01 ether,
            receiver: address(0)
        });

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("AuctionNotSettled()"));
        autoBidder.setConfig(cfg);

        vm.warp(_getCurrentAuction().endTime);
        auctionHouse.settleCurrentAndCreateNewAuction();

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidReceiver()"));
        autoBidder.setConfig(cfg);

        vm.prank(owner);
        cfg.receiver = owner;
        autoBidder.setConfig(cfg);

        vm.prank(owner);
        autoBidder.unpause();

        // can continue bidding
        vm.warp(_getCurrentAuction().endTime - BID_WINDOW);
        autoBidder.bid();
    }

    function testTipOwed() public {
        // won auction
        auctionHouse.unpause();
        vm.warp(_getCurrentAuction().endTime - BID_WINDOW);
        autoBidder.bid();
        vm.warp(_getCurrentAuction().endTime);
        auctionHouse.settleCurrentAndCreateNewAuction();

        vm.prank(owner);
        autoBidder.pause();

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("TipOwed()"));
        autoBidder.withdrawBalance();

        Bidder.Config memory cfg = autoBidder.getConfig();
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("TipOwed()"));
        autoBidder.setConfig(cfg);

        autoBidder.withdraw(0);

        // should properly withdraw remaining balance after tip is paid
        uint256 autoBidderBal = address(autoBidder).balance;
        uint256 beforeBal = owner.balance;
        vm.prank(owner);
        autoBidder.withdrawBalance();
        uint256 afterBal = owner.balance;
        assertEq(afterBal - beforeBal, autoBidderBal);
        assertEq(address(autoBidder).balance, 0);

        vm.prank(owner);
        autoBidder.setConfig(cfg);
    }

    function testTipOwedInPast() public {
        // won auction
        auctionHouse.unpause();
        vm.warp(_getCurrentAuction().endTime - BID_WINDOW);
        autoBidder.bid();
        vm.warp(_getCurrentAuction().endTime);
        auctionHouse.settleCurrentAndCreateNewAuction();

        // lost auction
        vm.warp(_getCurrentAuction().endTime - BID_WINDOW);
        autoBidder.bid();
        auctionHouse.createBid{value: 1 ether}(1);
        vm.warp(_getCurrentAuction().endTime);
        auctionHouse.settleCurrentAndCreateNewAuction();

        vm.prank(owner);
        autoBidder.pause();

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("TipOwed()"));
        autoBidder.withdrawBalance();

        autoBidder.withdraw(0);

        vm.prank(owner);
        autoBidder.withdrawBalance();
    }

    function testConfigChange() public {
        auctionHouse.unpause();
        vm.warp(_getCurrentAuction().endTime);
        auctionHouse.settleCurrentAndCreateNewAuction();

        vm.warp(_getCurrentAuction().endTime - BID_WINDOW);
        vm.prank(owner);
        autoBidder.pause();

        Bidder.Config memory cfg = autoBidder.getConfig();
        vm.prank(owner);
        autoBidder.setConfig(cfg);

        vm.prank(owner);
        autoBidder.unpause();
        autoBidder.bid();
    }

    function testRevertBidIfPaused() public {
        auctionHouse.unpause();
        vm.warp(_getCurrentAuction().endTime - BID_WINDOW);
        vm.prank(owner);
        autoBidder.pause();

        vm.expectRevert(bytes("Pausable: paused"));
        autoBidder.bid();

        vm.warp(_getCurrentAuction().endTime);
        auctionHouse.settleCurrentAndCreateNewAuction();

        vm.prank(owner);
        autoBidder.unpause();

        vm.warp(_getCurrentAuction().endTime - BID_WINDOW);
        autoBidder.bid();

        vm.prank(owner);
        autoBidder.pause();

        vm.expectRevert(bytes("Pausable: paused"));
        autoBidder.bid();

        auctionHouse.createBid{value: 1 ether}(1);

        vm.prank(owner);
        autoBidder.unpause();
        autoBidder.bid();
    }

    function testShouldOnlyInitOnce() public {
        IBidder.Config memory cfg = IBidder.Config({
            maxBid: 30 ether,
            minBid: 30 ether,
            bidWindow: BID_WINDOW,
            tip: 0.01 ether,
            receiver: owner
        });

        // implementation should disable initializers when deployed
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        bidderImpl.initialize(token, auctionHouse, owner, cfg);

        // bidder was initialized in setup; should revert if attempted again
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        autoBidder.initialize(token, auctionHouse, owner, cfg);
    }

    function _getCurrentAuction() internal view returns (INounsAuctionHouse.Auction memory) {
        (uint256 nounId, uint256 amount, uint256 startTime, uint256 endTime, address bidder, bool settled) =
            auctionHouse.auction();

        INounsAuctionHouse.Auction memory auction = INounsAuctionHouse.Auction({
            nounId: nounId,
            amount: amount,
            startTime: startTime,
            endTime: endTime,
            bidder: payable(bidder),
            settled: settled
        });

        return auction;
    }
}
