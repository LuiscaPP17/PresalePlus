# PresalePlus

## Overview

**PresalePlus** is a token presale contract with phased pricing, dual payment methods, and linear token vesting.

Users can purchase presale tokens using either USDT/USDC or native ETH (converted to USD in real time via a Chainlink price feed). The sale is structured in three configurable phases, each with its own token cap, price, and end time — the contract automatically advances to the next phase once a cap is reached or a phase's end time passes. To keep the distribution fair, each wallet is capped at a maximum purchase amount set at deployment.

Once the presale ends, purchased tokens don't unlock all at once — they vest linearly over a configurable period, and users call `claim()` to withdraw whatever portion has unlocked so far. The contract also includes an admin blacklist, pause/unpause controls for the buying functions, and emergency withdrawal functions for the owner.

## How it works

- [`PresalePlus.sol`](LINK_PENDING) — the main presale contract
- [`IAggregator.sol`](LINK_PENDING) — Chainlink price feed interface

## Technical docs

### `constructor`
[Check function](LINK_PENDING)

```solidity
```

### `blacklist`
[Check function](LINK_PENDING)

```solidity
```

### `removeBlacklist`
[Check function](LINK_PENDING)

```solidity
```

### `checkCurrentPhase` (private)
[Check function](LINK_PENDING)

```solidity
```

### `buyWithStable`
[Check function](LINK_PENDING)

```solidity
```

### `buyWithEther`
[Check function](LINK_PENDING)

```solidity
```

### `getEtherPrice`
[Check function](LINK_PENDING)

```solidity
```

### `claim`
[Check function](LINK_PENDING)

```solidity
```

### `emergencyERC20Withdraw`
[Check function](LINK_PENDING)

```solidity
```

### `emergencyETHWithdraw`
[Check function](LINK_PENDING)

```solidity
```

### `pause`
[Check function](LINK_PENDING)

```solidity
```

### `unpause`
[Check function](LINK_PENDING)

```solidity
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
