![auctionbidder.png](https://i.postimg.cc/bJGmk8s6/auctionbidder.png)

## AutoBidder

A tiny protocol for bidding on Nouns at auction! It refunds gas and provides a tip for 
anyone who kicks off a bid on behalf of the contract owner.

## Use Cases

- Have others bid on your behalf in Nouns auctions
- Acquire Nouns as a group or community
- Participate in Nouns auctions with minimal overhead

## Features

- Configurable tip for anyone kicking off a bid or withdrawal of tokens won
- Gas refunds for bid and withdrawal calls
- As the contract owner you can configure settings like the tip amount, min/max bids, and when one can be placed

## Usage

**Objective**  

```
Anyone can call bid() to help the owner bid on a Noun at auction. This contract will automatically bid the
minimum amount required to win.
```

**Gas Refunds**  

All calls to `bid()` and `withdraw(nounId)` are refunded gas and tipped.

**Constraints**  

- You can only call `bid()` in the last `bidWindow` seconds of an auction
  - Call `getConfig()` to see the current bid window
- You can only call `bid()` if this contract is not already the highest bidder
- A max bid amount is defined by the contract owner. Calling `bid()` when the next one
  would exceed the max bid value will cause the transaction to revert

**If an auction is won**  

After the auction has settled, call `withdraw(nounId)` to send the Noun to the
receiver defined in the contract config and receive a tip for doing so.

### Deploying your own

[Contract Address: 0x5a2DA0F09d65a0034F4398BdA40df4F8A79a3293](https://etherscan.io/address/0x5a2da0f09d65a0034f4398bda40df4f8a79a3293)

Deploy your own Bidder by calling `clone()` and seeding it with ETH. This bidder
can be configured with min or max bid amounts for auctions. As well as a window 
of time that bids can be placed.

Share the address with friends and have them call `bid()` during an active
auction.

If the Bidder wins, `withdraw(nounId)` can be called after the auction is settled.

## Things to keep in mind

- Ensure that a contract has more ETH than the max amount you're willing to bid
  - You want to incentivize others to submit bids on your behalf
- It's a good idea to configure a bidWindow that opens towards the end of an auction
  - competing bidders may grief you for tips throughout an extended auction period
- Consecutive bids cannot be made in the same block

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

## Setting an ENS reverse record

Visit [app.ens.domains](https://app.ens.domains/) to create a subdomain under one of your accounts. Add an address record pointing to your deployed AutoBidder contract.

Then you can call `setENSReverseRecord` on the AutoBidder passing in the ENS subdomain
created above.

![ensreverserecord.png](https://i.postimg.cc/pdrdZ2Bk/ensreverserecord.png)

## Version

v0.2

### Changelog

v0.2 - Add support for ENS reverse records

v0.1 - Initial release
