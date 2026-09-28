// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import "../src/Interfaces/IAggregator.sol";

/**
 * @title PresalePlus
 * @notice A token presale contract with phased pricing, Chainlink-based ETH pricing,
 * a per-wallet purchase limit, and linear vesting for claimed tokens
 */
contract PresalePlus is Ownable, Pausable {
    using SafeERC20 for IERC20;

    /**
     * @notice Core sale configuration
     * saleTokenAddress: the token being sold in the presale
     * usdtAddress: USDT contract address, accepted as payment
     * usdcAddress: USDC contract address, accepted as payment
     * fundsReceiverAddress: address that receives all payments (stablecoins and ETH)
     * dataFeedAddress: Chainlink price feed used to convert ETH payments to USD value
     */

    address public saleTokenAddress;
    address public usdtAddress;
    address public usdcAddress;
    address public fundsReceiverAddress;
    address public dataFeedAddress;

    /**
     * @notice Sale limits and timing
     * maxSellingAmount: total tokens available across the entire presale
     * maxPerWallet: maximum tokens a single wallet can purchase
     * startingTime: timestamp when the presale opens
     * endingTime: timestamp when the presale closes and vesting begins
     * vestingDuration: how long tokens take to fully vest after endingTime
     */
    uint256 public maxSellingAmount;
    uint256 public maxPerWallet;
    uint256 public startingTime;
    uint256 public endingTime;
    uint256 public vestingDuration;

    /**
     * @notice Phased pricing: each phase holds [token cap, price, phase end time]
     */
    uint256[][3] public phases;

    /**
     * @notice Sale progress tracking
     * totalSold: total tokens sold so far, across all phases
     * currentPhase: index of the active pricing phase
     */
    uint256 public totalSold;
    uint256 public currentPhase;

    /**
     * @notice Per-user tracking
     * isBlacklisted: addresses barred from purchasing
     * userTokenBalance: total tokens purchased by each wallet (fixed once bought)
     * claimedAmount: total tokens each wallet has already claimed via vesting
     */
    mapping(address => bool) public isBlacklisted;
    mapping(address => uint256) public userTokenBalance;
    mapping(address => uint256) public claimedAmount;

    event TokenBuy(address user, uint256 amount);

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

    /**
     * @notice Blocks an address from participating in the presale. Only callable by the contract owner
     * @param user_ The address to blacklist
     */
    function blacklist(address user_) external onlyOwner {
        isBlacklisted[user_] = true;
    }

    /**
     * @notice Removes an address from the blacklist. Only callable by the contract owner
     * @param user_ The address to remove from the blacklist
     */
    function removeBlacklist(address user_) external onlyOwner {
        isBlacklisted[user_] = false;
    }

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
            tokenAmountToReceive =
                amount_ * 10 ** (18 - ERC20(tokenUsedToBuy_).decimals()) * 1e6 / phases[currentPhase][1];
        }
        checkCurrentPhase(tokenAmountToReceive);

        totalSold += tokenAmountToReceive;
        require(totalSold <= maxSellingAmount, "Sold Out");
        require(userTokenBalance[msg.sender] + tokenAmountToReceive <= maxPerWallet, "Wallet purchase limit exceeded");

        IERC20(tokenUsedToBuy_).safeTransferFrom(msg.sender, fundsReceiverAddress, amount_);

        userTokenBalance[msg.sender] += tokenAmountToReceive;

        emit TokenBuy(msg.sender, tokenAmountToReceive);
    }

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

    /**
     * @notice Returns the current ETH/USD price from the Chainlink price feed, normalized to 18 decimals
     */
    function getEtherPrice() public view returns (uint256) {
        (, int256 price,,,) = IAggregator(dataFeedAddress).latestRoundData();
        price = price * (10 ** 10);
        return uint256(price);
    }

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

    /**
     * @notice Allows the owner to withdraw any ERC20 token from the contract in an emergency
     * @param tokenAddress_ The token to withdraw
     * @param amount_ The amount to withdraw
     */
    function emergencyERC20Withdraw(address tokenAddress_, uint256 amount_) external onlyOwner {
        IERC20(tokenAddress_).safeTransfer(msg.sender, amount_);
    }

    /**
     * @notice Allows the owner to withdraw all ETH held by the contract in an emergency
     */
    function emergencyETHWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success,) = msg.sender.call{value: balance}("");
        require(success, "Transfer Fail");
    }

    /**
     * @notice Pauses buyWithStable() and buyWithEther(). claim() and emergency withdrawals are never affected
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Resumes buyWithStable() and buyWithEther()
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
