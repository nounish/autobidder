![auctionbidder.png](https://i.postimg.cc/bJGmk8s6/auctionbidder.png)

## AutoBidder

An onchain bidder for Nouns style auctions. It provides incentives for anyone
to submit auction bids on behalf of the contract owner. Whoever successfully
places the winning bid for an auction is automatically rewarded with a tip!

## Use Cases

- Have others bid on your behalf in Nouns auctions
- Acquire Nouns as a group or community
- Participate in auctions with minimal overhead

## Features

- Configurable tip for the last caller who helped win the auction
- Gas refunds for anyone kicking off a bid
- Bid submitters don't need to trust the contract owner, all tips are guaranteed

## Usage

**Objective**  

```
Call bid() to help win a Nouns auction. This contract will automatically bid the
minimum amount required to win.

The last person to call bid() and win the auction is rewarded with a tip.
```

**Gas Refunds**  

All calls to `bid()` and `withdraw()` are refunded gas.

**Constraints**  

- You can only call `bid()` in the last `bidWindow` seconds of an auction
  - Call `getConfig()` to see the current bid window
- You can only call `bid()` if this contract is not already the highest bidder
- A max bid is defined by the contract owner. Calling `bid()` when the next one
  would exceed the max bid value will cause the transaction to revert

**If an auction is won**  

After the auction has settled, call `withdraw(uint256)` with the given
token id that was won withdraw any tokens and send a tip to the address that placed the winning bid.

### As a contract owner

Deploy this contract and seed it with some ETH. This bidder can be configured with
min or max bid amounts for auctions. As well as a window of time that bids can
be placed.

Share the address with friends or bots and have them call `bid()` during an active
auction.

If this contract wins `withdraw()` can be called after the auction is settled and
a tip will be sent to the last caller of `bid()`.

## Deploy

To deploy your own Bidder call `clone()` on the contract deployed at address `0x9d3496639FBD68A88718425f080dCe178c8Bf2D6` passing in your desired config.

## Config

`t` - address of the ERC721 token at auction  
`ah` - address of the auction house  
`_owner` - owner address of this contract  
  
**Bidder.Config**  

`maxBid`: `max bid in wei`  
`minBid`: `min bid in wei`  
`bidWindow`: `seconds that a bid can be placed before an auction ends`  
`tip`: `tip in wei`  
`receiver`: `address to transfer tokens won at auction`

## Version

v0.1
