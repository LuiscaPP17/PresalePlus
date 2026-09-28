# PresalePlus

## Overview

**PresalePlus** is a token presale contract with phased pricing, dual payment methods, and linear token vesting.

Users can purchase presale tokens using either USDT/USDC or native ETH (converted to USD in real time via a Chainlink price feed). The sale is structured in three configurable phases, each with its own token cap, price, and end time — the contract automatically advances to the next phase once a cap is reached or a phase's end time passes. To keep the distribution fair, each wallet is capped at a maximum purchase amount set at deployment.

Once the presale ends, purchased tokens don't unlock all at once — they vest linearly over a configurable period, and users call `claim()` to withdraw whatever portion has unlocked so far. The contract also includes an admin blacklist, pause/unpause controls for the buying functions, and emergency withdrawal functions for the owner.

## How it works

- [`PresalePlus.sol`](https://github.com/LuiscaPP17/PresalePlus/blob/main/src/PresalePlus.sol) — the main presale contract
- [`IAggregator.sol`](https://github.com/LuiscaPP17/PresalePlus/blob/main/src/Interfaces/IAggregator.sol) — Chainlink price feed interface

## Technical docs

### `constructor`
[Check function](https://github.com/LuiscaPP17/PresalePlus/blob/main/src/PresalePlus.sol#L86-L113)

```solidity
/**
* @param saleTokenAddress_ The token being sold in the presale
* @param usdtAddress_ USDT contract address, accepted as payment
* @param usdcAddress_ USDC contract address, accepted as payment
* @param fundsReceiverAddress_ Address that receives all payments
* @param dataFeedAddress_ Chainlink price feed used to convert ETH payments to USD value
* @param maxSellingAmount_ Total tokens available across the entire presale
* @param maxPerWallet_ Maximum tokens a single wallet can purchase
* @param startingTime_ Timestamp when the presale opens
* @param endingTime_ Timestamp when the presale closes and vesting begins
* @param vestingDuration_ How long tokens take to fully vest after endingTime
* @param phases_ Pricing phases, each holding [token cap, price, phase end time]
*/
constructor(
    address saleTokenAddress_,
    address usdtAddress_,
    address usdcAddress_,
    address fundsReceiverAddress_,
    address dataFeedAddress_,
    uint256 maxSellingAmount_,
    uint256 maxPerWallet_,
    uint256 startingTime_,
    uint256 endingTime_,
    uint256 vestingDuration_,
    uint256[][3] memory phases_
) Ownable(msg.sender) {
    saleTokenAddress = saleTokenAddress_;
    usdtAddress = usdtAddress_;
    usdcAddress = usdcAddress_;
    fundsReceiverAddress = fundsReceiverAddress_;
    dataFeedAddress = dataFeedAddress_;
    maxSellingAmount = maxSellingAmount_;
    maxPerWallet = maxPerWallet_;
    startingTime = startingTime_;
    endingTime = endingTime_;
    vestingDuration = vestingDuration_;
    phases = phases_;

    require(endingTime > startingTime, "Incorrect Time");
    IERC20(saleTokenAddress_).safeTransferFrom(msg.sender, address(this), maxSellingAmount);
}
```

### `blacklist`
[Check function](https://github.com/LuiscaPP17/PresalePlus/blob/main/src/PresalePlus.sol#L119-L121)

```solidity
/**
* @notice Blocks an address from participating in the presale. Only callable by the contract owner
* @param user_ The address to blacklist
*/
function blacklist(address user_) external onlyOwner {
    isBlacklisted[user_] = true;
}
```

### `removeBlacklist`
[Check function](https://github.com/LuiscaPP17/PresalePlus/blob/main/src/PresalePlus.sol#L127-L129)

```solidity
/**
* @notice Removes an address from the blacklist. Only callable by the contract owner
* @param user_ The address to remove from the blacklist
*/
function removeBlacklist(address user_) external onlyOwner {
    isBlacklisted[user_] = false;
}
```

### `checkCurrentPhase` (private)
[Check function](https://github.com/LuiscaPP17/PresalePlus/blob/main/src/PresalePlus.sol#L137-L147)

```solidity
/**
* @notice Advances the current phase if this purchase would meet the phase's token cap
* or if the phase's end time has been reached, whichever comes first
* @param amount_ The amount of tokens about to be purchased, checked against the phase cap
* @return phase The resulting current phase after this check
*/
function checkCurrentPhase(uint256 amount_) private returns (uint256 phase) {
    if (
        (totalSold + amount_ >= phases[currentPhase][0] || (block.timestamp >= phases[currentPhase][2]))
            && currentPhase < 2
    ) {
        currentPhase++;
        phase = currentPhase;
    } else {
        phase = currentPhase;
    }
}
```

### `buyWithStable`
[Check function](https://github.com/LuiscaPP17/PresalePlus/blob/main/src/PresalePlus.sol#L155-L178)

```solidity
/**
* @notice Buys presale tokens using USDT or USDC. Respects the max supply, wallet purchase limit,
* blacklist, and presale time window
* @param tokenUsedToBuy_ The stablecoin used for payment (must be USDT or USDC)
* @param amount_ The amount of the stablecoin to spend
*/
function buyWithStable(address tokenUsedToBuy_, uint256 amount_) external whenNotPaused {
    require(!isBlacklisted[msg.sender], "User is Blacklisted");
    require(block.timestamp >= startingTime && block.timestamp <= endingTime, "Presale not started yet");
    require(tokenUsedToBuy_ == usdtAddress || tokenUsedToBuy_ == usdcAddress, "Incorrect token");

    uint256 tokenAmountToReceive;
    if (ERC20(tokenUsedToBuy_).decimals() == 18) {
        tokenAmountToReceive = amount_ * 1e6 / phases[currentPhase][1];
    } else {
        tokenAmountToReceive = amount_ * 10 ** (18 - ERC20(tokenUsedToBuy_).decimals()) * 1e6 / phases[currentPhase][1];
    }
    checkCurrentPhase(tokenAmountToReceive);

    totalSold += tokenAmountToReceive;
    require(totalSold <= maxSellingAmount, "Sold Out");
    require(userTokenBalance[msg.sender] + tokenAmountToReceive <= maxPerWallet, "Wallet purchase limit exceeded");

    IERC20(tokenUsedToBuy_).safeTransferFrom(msg.sender, fundsReceiverAddress, amount_);

    userTokenBalance[msg.sender] += tokenAmountToReceive;

    emit TokenBuy(msg.sender, tokenAmountToReceive);
}
```

### `buyWithEther`
[Check function](https://github.com/LuiscaPP17/PresalePlus/blob/main/src/PresalePlus.sol#L184-L202)

```solidity
/**
* @notice Buys presale tokens using native ETH, converted to USD value via the Chainlink price feed.
* Respects the max supply, wallet purchase limit, blacklist, and presale time window
*/
function buyWithEther() external payable whenNotPaused {
    require(!isBlacklisted[msg.sender], "User is Blacklisted");
    require(block.timestamp >= startingTime && block.timestamp <= endingTime, "Presale not started yet");

    uint256 usdValue = msg.value * getEtherPrice() / 1e18;
    uint256 tokenAmountToReceive = usdValue / phases[currentPhase][1];
    checkCurrentPhase(tokenAmountToReceive);

    totalSold += tokenAmountToReceive;
    require(totalSold <= maxSellingAmount, "Sold Out");
    require(userTokenBalance[msg.sender] + tokenAmountToReceive <= maxPerWallet, "Wallet purchase limit exceeded");

    userTokenBalance[msg.sender] += tokenAmountToReceive;

    (bool success,) = fundsReceiverAddress.call{value: msg.value}("");
    require(success, "Transfer fail");

    emit TokenBuy(msg.sender, tokenAmountToReceive);
}
```

### `getEtherPrice`
[Check function](https://github.com/LuiscaPP17/PresalePlus/blob/main/src/PresalePlus.sol#L207-L211)

```solidity
/**
* @notice Returns the current ETH/USD price from the Chainlink price feed, normalized to 18 decimals
*/
function getEtherPrice() public view returns (uint256) {
    (, int256 price,,,) = IAggregator(dataFeedAddress).latestRoundData();
    price = price * (10 ** 10);
    return uint256(price);
}
```

### `claim`
[Check function](https://github.com/LuiscaPP17/PresalePlus/blob/main/src/PresalePlus.sol#L217-L234)

```solidity
/**
* @notice Claims vested presale tokens. Tokens unlock linearly over vestingDuration,
* starting once the presale ends
*/
function claim() external {
    require(block.timestamp > endingTime, "Presale not ended");

    uint256 totalVested_;
    if (block.timestamp >= endingTime + vestingDuration) {
        totalVested_ = userTokenBalance[msg.sender];
    } else {
        uint256 timeElapsed_ = block.timestamp - endingTime;
        totalVested_ = (userTokenBalance[msg.sender] * timeElapsed_) / vestingDuration;
    }

    uint256 claimable_ = totalVested_ - claimedAmount[msg.sender];
    require(claimable_ > 0, "Nothing to claim yet");

    claimedAmount[msg.sender] += claimable_;

    IERC20(saleTokenAddress).safeTransfer(msg.sender, claimable_);
}
```

### `emergencyERC20Withdraw`
[Check function](https://github.com/LuiscaPP17/PresalePlus/blob/main/src/PresalePlus.sol#L241-L243)

```solidity
/**
* @notice Allows the owner to withdraw any ERC20 token from the contract in an emergency
* @param tokenAddress_ The token to withdraw
* @param amount_ The amount to withdraw
*/
function emergencyERC20Withdraw(address tokenAddress_, uint256 amount_) external onlyOwner {
    IERC20(tokenAddress_).safeTransfer(msg.sender, amount_);
}
```

### `emergencyETHWithdraw`
[Check function](https://github.com/LuiscaPP17/PresalePlus/blob/main/src/PresalePlus.sol#L248-L252)

```solidity
/**
* @notice Allows the owner to withdraw all ETH held by the contract in an emergency
*/
function emergencyETHWithdraw() external onlyOwner {
    uint256 balance = address(this).balance;
    (bool success,) = msg.sender.call{value: balance}("");
    require(success, "Transfer Fail");
}
```

### `pause`
[Check function](https://github.com/LuiscaPP17/PresalePlus/blob/main/src/PresalePlus.sol#L257-L259)

```solidity
/**
* @notice Pauses buyWithStable() and buyWithEther(). claim() and emergency withdrawals are never affected
*/
function pause() external onlyOwner {
    _pause();
}
```

### `unpause`
[Check function](https://github.com/LuiscaPP17/PresalePlus/blob/main/src/PresalePlus.sol#L264-L266)

```solidity
/**
* @notice Resumes buyWithStable() and buyWithEther()
*/
function unpause() external onlyOwner {
    _unpause();
}
```

## Usage Example

*(Pending — to be added if deployed to testnet or mainnet)*

## Contract addresses

*(Pending — to be added if deployed)*

## Tech

- Solidity 0.8.24
- Foundry
- OpenZeppelin Contracts (Ownable, Pausable, ERC20, SafeERC20)
- Chainlink Price Feeds
- Fork testing against Arbitrum One mainnet

## Testing

100% branch coverage.

```
╭----------------------------+-----------------+-----------------+-----------------+-----------------╮
| File                       | % Lines         | % Statements    | % Branches      | % Funcs         |
+====================================================================================================+
| src/PresalePlus.sol        | 100.00% (75/75) | 100.00% (76/76) | 100.00% (34/34) | 100.00% (12/12) |
|----------------------------+-----------------+-----------------+-----------------+-----------------|
| test/PresalePlusTest.t.sol | 100.00% (6/6)   | 100.00% (3/3)   | 100.00% (0/0)   | 100.00% (3/3)   |
|----------------------------+-----------------+-----------------+-----------------+-----------------|
| Total                      | 100.00% (81/81) | 100.00% (79/79) | 100.00% (34/34) | 100.00% (15/15) |
╰----------------------------+-----------------+-----------------+-----------------+-----------------╯
```
