// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../src/PresalePlus.sol";
import "../lib/forge-std/src/Test.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 50_000_000 ether);
    }
}

contract MockStable18 is ERC20 {
    constructor() ERC20("Mock USD 18", "mUSD18") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

contract RejectEther {
    receive() external payable {
        revert("I don't accept ETH");
    }
}

contract PresalePlusTest is Test {
    PresalePlus presale;
    MockToken saleToken;

    address deployer = vm.addr(1);
    address user = vm.addr(2);

    address ethUsdPriceFeed = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address realUser = 0x2c04Ac9eCD66fd05b938eEa6520F3C0f2c437224; // wallet real con USDT

    uint256 maxSellingAmount = 30_000_000 ether;
    uint256 maxPerWallet = 1_000_000 ether;
    uint256 startingTime;
    uint256 endingTime;
    uint256 vestingDuration = 30 days;
    uint256[][3] phases;

    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc");

        startingTime = block.timestamp;
        endingTime = block.timestamp + 5000;

        phases[0] = [10_000_000 ether, 5000, block.timestamp + 1000];
        phases[1] = [10_000_000 ether, 500, block.timestamp + 3000];
        phases[2] = [10_000_000 ether, 50, block.timestamp + 5000];

        vm.startPrank(deployer);

        saleToken = new MockToken();

        address predictedPresaleAddress = vm.computeCreateAddress(deployer, vm.getNonce(deployer));
        saleToken.approve(predictedPresaleAddress, maxSellingAmount);

        presale = new PresalePlus(
            address(saleToken),
            USDT,
            USDC,
            deployer,
            ethUsdPriceFeed,
            maxSellingAmount,
            maxPerWallet,
            startingTime,
            endingTime,
            vestingDuration,
            phases
        );

        vm.stopPrank();
    }

    function testHasBeenDeployedCorrectly() public view {
        assertEq(presale.saleTokenAddress(), address(saleToken), "Sale token should match");
        assertEq(presale.usdtAddress(), USDT, "USDT address should match");
        assertEq(presale.usdcAddress(), USDC, "USDC address should match");
        assertEq(presale.fundsReceiverAddress(), deployer, "Funds receiver should match");
        assertEq(presale.dataFeedAddress(), ethUsdPriceFeed, "Data feed should match");
        assertEq(presale.maxSellingAmount(), maxSellingAmount, "Max selling amount should match");
        assertEq(presale.maxPerWallet(), maxPerWallet, "Max per wallet should match");
        assertEq(presale.startingTime(), startingTime, "Starting time should match");
        assertEq(presale.endingTime(), endingTime, "Ending time should match");
        assertEq(presale.vestingDuration(), vestingDuration, "Vesting duration should match");

        for (uint256 i = 0; i < 3; i++) {
            assertEq(presale.phases(i, 0), phases[i][0], "Phase cap should match");
            assertEq(presale.phases(i, 1), phases[i][1], "Phase price should match");
            assertEq(presale.phases(i, 2), phases[i][2], "Phase end time should match");
        }
    }

    function testBlacklistSuccess() public {
        vm.startPrank(deployer);

        presale.blacklist(user);

        vm.stopPrank();

        assertEq(presale.isBlacklisted(user), true, "User should be blacklisted");
    }

    function testBlacklistRevertsWhenNotOwner() public {
        vm.startPrank(user);

        vm.expectRevert();
        presale.blacklist(user);

        vm.stopPrank();
    }

    function testRemoveBlacklistedCorrectly() public {
        vm.startPrank(deployer);

        presale.blacklist(user);
        assertEq(presale.isBlacklisted(user), true, "User should be blacklisted");

        presale.removeBlacklist(user);
        assertEq(presale.isBlacklisted(user), false, "User should no longer be blacklisted");

        vm.stopPrank();
    }

    function testRemoveBlacklistRevertsWhenNotOwner() public {
        vm.startPrank(user);

        vm.expectRevert();
        presale.removeBlacklist(user);

        vm.stopPrank();
    }

    function testBuyWithStableCorrectly() public {
        vm.startPrank(realUser);

        console.log("USDT balance", IERC20(USDT).balanceOf(realUser));
        uint256 amountToSpend = 5 * 1e6;
        IERC20(USDT).approve(address(presale), amountToSpend);

        uint256 usdtBalanceBefore = IERC20(USDT).balanceOf(realUser);
        uint256 userTokenBalanceBefore = presale.userTokenBalance(realUser);
        uint256 totalSoldBefore = presale.totalSold();
        presale.buyWithStable(USDT, amountToSpend);
        uint256 usdtBalanceAfter = IERC20(USDT).balanceOf(realUser);
        uint256 userTokenBalanceAfter = presale.userTokenBalance(realUser);
        uint256 totalSoldAfter = presale.totalSold();

        assert(usdtBalanceAfter == usdtBalanceBefore - amountToSpend);
        assert(userTokenBalanceAfter > userTokenBalanceBefore);
        assert(totalSoldAfter > totalSoldBefore);

        vm.stopPrank();
    }

    function testBuyWithStableRevertsWhenBlacklisted() public {
        vm.startPrank(deployer);

        presale.blacklist(realUser);

        vm.stopPrank();
        vm.startPrank(realUser);

        console.log("USDT balance", IERC20(USDT).balanceOf(realUser));
        uint256 amountToSpend = 5 * 1e6;
        IERC20(USDT).approve(address(presale), amountToSpend);

        vm.expectRevert("User is Blacklisted");
        presale.buyWithStable(USDT, amountToSpend);

        vm.stopPrank();
    }

    function testBuyWithStableRevertsWhenPresaleNotStarted() public {
        vm.startPrank(realUser);

        vm.warp(startingTime - 1 days);

        console.log("USDT balance", IERC20(USDT).balanceOf(realUser));
        uint256 amountToSpend = 5 * 1e6;
        IERC20(USDT).approve(address(presale), amountToSpend);

        vm.expectRevert("Presale not started yet");
        presale.buyWithStable(USDT, amountToSpend);

        vm.stopPrank();
    }

    function testBuyWithStableRevertsWhenIncorrectToken() public {
        vm.startPrank(realUser);

        uint256 amountToSpend = 5 * 1e6;

        vm.expectRevert("Incorrect token");
        presale.buyWithStable(DAI, amountToSpend);

        vm.stopPrank();
    }

    function testBuyWithStableRevertsWhenSoldOut() public {
        vm.startPrank(realUser);

        vm.store(address(presale), bytes32(uint256(14)), bytes32(uint256(maxSellingAmount)));

        console.log("USDT balance", IERC20(USDT).balanceOf(realUser));
        uint256 amountToSpend = 5 * 1e6;
        IERC20(USDT).approve(address(presale), amountToSpend);

        vm.expectRevert("Sold Out");
        presale.buyWithStable(USDT, amountToSpend);

        vm.stopPrank();
    }

    function testBuyWithStableRevertsWhenWalletLimitExceeded() public {
        vm.startPrank(realUser);

        vm.store(address(presale), keccak256(abi.encode(realUser, uint256(17))), bytes32(uint256(maxPerWallet)));

        console.log("USDT balance", IERC20(USDT).balanceOf(realUser));
        uint256 amountToSpend = 5 * 1e6;
        IERC20(USDT).approve(address(presale), amountToSpend);

        vm.expectRevert("Wallet purchase limit exceeded");
        presale.buyWithStable(USDT, amountToSpend);

        vm.stopPrank();
    }

    function testBuyWithStableRevertsWhenPaused() public {
        vm.startPrank(deployer);

        presale.pause();

        vm.stopPrank();
        vm.startPrank(realUser);

        console.log("USDT balance", IERC20(USDT).balanceOf(realUser));
        uint256 amountToSpend = 5 * 1e6;
        IERC20(USDT).approve(address(presale), amountToSpend);

        vm.expectRevert();
        presale.buyWithStable(USDT, amountToSpend);

        vm.stopPrank();
    }

    function testBuyWithEtherCorrectly() public {
        vm.deal(realUser, 100 ether);
        vm.startPrank(realUser);

        uint256 amountToSpend = 5 ether;

        uint256 ethBalanceBefore = realUser.balance;
        uint256 userTokenBalanceBefore = presale.userTokenBalance(realUser);
        uint256 totalSoldBefore = presale.totalSold();
        presale.buyWithEther{value: amountToSpend}();
        uint256 ethBalanceAfter = realUser.balance;
        uint256 userTokenBalanceAfter = presale.userTokenBalance(realUser);
        uint256 totalSoldAfter = presale.totalSold();

        assert(ethBalanceAfter == ethBalanceBefore - amountToSpend);
        assert(userTokenBalanceAfter > userTokenBalanceBefore);
        assert(totalSoldAfter > totalSoldBefore);

        vm.stopPrank();
    }

    function testBuyWithEtherRevertsWhenBlackListed() public {
        vm.startPrank(deployer);

        presale.blacklist(realUser);

        vm.stopPrank();
        vm.deal(realUser, 100 ether);
        vm.startPrank(realUser);

        uint256 amountToSpend = 5 ether;

        vm.expectRevert("User is Blacklisted");
        presale.buyWithEther{value: amountToSpend}();

        vm.stopPrank();
    }

    function testBuyWithEtherRevertsWhenPresaleNotStarted() public {
        vm.startPrank(realUser);

        vm.warp(startingTime - 1 days);
        vm.deal(realUser, 100 ether);

        uint256 amountToSpend = 5 ether;

        vm.expectRevert("Presale not started yet");
        presale.buyWithEther{value: amountToSpend}();

        vm.stopPrank();
    }

    function testBuyWithEtherRevertsWhenSoldOut() public {
        vm.startPrank(realUser);

        vm.store(address(presale), bytes32(uint256(14)), bytes32(uint256(maxSellingAmount)));
        uint256 amountToSpend = 5 ether;

        vm.deal(realUser, 100 ether);

        vm.expectRevert("Sold Out");
        presale.buyWithEther{value: amountToSpend}();

        vm.stopPrank();
    }

    function testBuyWithEtherRevertsWhenWalletLimitExceed() public {
        vm.startPrank(realUser);

        vm.store(address(presale), keccak256(abi.encode(realUser, uint256(17))), bytes32(uint256(maxPerWallet)));

        vm.deal(realUser, 100 ether);

        uint256 amountToSpend = 5 ether;

        vm.expectRevert("Wallet purchase limit exceeded");
        presale.buyWithEther{value: amountToSpend}();

        vm.stopPrank();
    }

    function testBuyWithEtherRevertsWhenTransferFails() public {
        RejectEther rejectContract = new RejectEther();

        vm.store(address(presale), bytes32(uint256(4)), bytes32(uint256(uint160(address(rejectContract)))));

        vm.deal(realUser, 100 ether);
        vm.startPrank(realUser);

        uint256 amountToSpend = 5 ether;

        vm.expectRevert("Transfer fail");
        presale.buyWithEther{value: amountToSpend}();

        vm.stopPrank();
    }

    function testBuyWithEtherRevertsWhenPaused() public {
        vm.startPrank(deployer);

        presale.pause();

        vm.stopPrank();
        vm.deal(realUser, 100 ether);
        vm.startPrank(realUser);

        uint256 amountToSpend = 5 ether;

        vm.expectRevert();
        presale.buyWithEther{value: amountToSpend}();

        vm.stopPrank();
    }

    function testGetEtherPriceCorrectly() public view {
        (, int256 price,,,) = IAggregator(ethUsdPriceFeed).latestRoundData();
        uint256 expectedPrice = uint256(price) * 10 ** 10;

        assertEq(presale.getEtherPrice(), expectedPrice, "Price should match the feed normalized to 18 decimals");
        assertGt(presale.getEtherPrice(), 0, "Price should be greater than zero");
    }

    function testClaimRevertsWhenPresaleNotEnded() public {
        vm.startPrank(realUser);

        vm.expectRevert("Presale not ended");
        presale.claim();

        vm.stopPrank();
    }

    function testClaimRevertsWhenNothingToClaim() public {
        vm.warp(endingTime + 1 days);
        vm.startPrank(realUser);

        vm.expectRevert("Nothing to claim yet");
        presale.claim();

        vm.stopPrank();
    }

    function testClaimPartialVesting() public {
        vm.startPrank(realUser);

        uint256 amountToSpend = 5 * 1e6;
        IERC20(USDT).approve(address(presale), amountToSpend);
        presale.buyWithStable(USDT, amountToSpend);

        uint256 purchasedTokens = presale.userTokenBalance(realUser);
        uint256 saleTokenBalanceBefore = saleToken.balanceOf(realUser);

        vm.warp(endingTime + vestingDuration / 2);

        presale.claim();

        uint256 expectedClaim = (purchasedTokens * (vestingDuration / 2)) / vestingDuration;
        uint256 saleTokenBalanceAfter = saleToken.balanceOf(realUser);

        assertEq(
            saleTokenBalanceAfter - saleTokenBalanceBefore,
            expectedClaim,
            "Should receive the proportional vested amount"
        );
        assertEq(presale.claimedAmount(realUser), expectedClaim, "claimedAmount should match what was claimed");
        assertEq(expectedClaim, purchasedTokens / 2, "Half the vesting period should unlock half the tokens");

        vm.stopPrank();
    }

    function testClaimFullVesting() public {
        vm.startPrank(realUser);
        vm.deal(realUser, 100 ether);

        uint256 amountToSpend = 5 ether;
        presale.buyWithEther{value: amountToSpend}();

        uint256 purchasedTokens = presale.userTokenBalance(realUser);
        uint256 saleTokenBalanceBefore = saleToken.balanceOf(realUser);

        vm.warp(endingTime + vestingDuration);

        presale.claim();

        uint256 saleTokenBalanceAfter = saleToken.balanceOf(realUser);

        assertEq(
            saleTokenBalanceAfter - saleTokenBalanceBefore, purchasedTokens, "Should receive the full purchased amount"
        );
        assertEq(presale.claimedAmount(realUser), purchasedTokens, "claimedAmount should equal the full purchase");

        vm.stopPrank();
    }

    function testClaimTwiceDoesNotGiveMore() public {
        vm.startPrank(realUser);
        vm.deal(realUser, 100 ether);

        uint256 amountToSpend = 5 ether;
        presale.buyWithEther{value: amountToSpend}();

        vm.warp(endingTime + vestingDuration);

        presale.claim();

        uint256 saleTokenBalanceAfter = saleToken.balanceOf(realUser);

        vm.expectRevert("Nothing to claim yet");
        presale.claim();

        uint256 saleTokenBalanceAfterSecondClaim = saleToken.balanceOf(realUser);
        assertEq(saleTokenBalanceAfterSecondClaim, saleTokenBalanceAfter, "Balance should not change on a second claim");

        vm.stopPrank();
    }

    function testEmergencyERC20WithdrawSuccess() public {
        vm.startPrank(deployer);

        uint256 withdrawAmount = 1_000_000 ether;

        uint256 deployerBalanceBefore = saleToken.balanceOf(deployer);
        uint256 presaleBalanceBefore = saleToken.balanceOf(address(presale));

        presale.emergencyERC20Withdraw(address(saleToken), withdrawAmount);

        uint256 deployerBalanceAfter = saleToken.balanceOf(deployer);
        uint256 presaleBalanceAfter = saleToken.balanceOf(address(presale));

        assertEq(
            deployerBalanceAfter, deployerBalanceBefore + withdrawAmount, "Deployer should receive the withdrawn tokens"
        );
        assertEq(
            presaleBalanceAfter,
            presaleBalanceBefore - withdrawAmount,
            "Contract balance should decrease by the withdrawn amount"
        );

        vm.stopPrank();
    }

    function testEmergencyERC20WithdrawRevertsWhenNotOwner() public {
        vm.startPrank(realUser);

        vm.expectRevert();
        presale.emergencyERC20Withdraw(address(saleToken), 1_000_000 ether);

        vm.stopPrank();
    }

    function testEmergencyETHWithdrawSuccess() public {
        vm.etch(deployer, "");
        vm.deal(address(presale), 10 ether);
        vm.startPrank(deployer);

        uint256 deployerBalanceBefore = deployer.balance;
        uint256 presaleBalanceBefore = address(presale).balance;

        presale.emergencyETHWithdraw();

        uint256 deployerBalanceAfter = deployer.balance;
        uint256 presaleBalanceAfter = address(presale).balance;

        assertEq(
            deployerBalanceAfter,
            deployerBalanceBefore + presaleBalanceBefore,
            "Deployer should receive all the ETH from the contract"
        );
        assertEq(presaleBalanceAfter, 0, "Contract balance should be zero after withdrawal");

        vm.stopPrank();
    }

    function testEmergencyETHWithdrawRevertsWhenNotOwner() public {
        vm.startPrank(realUser);

        vm.expectRevert();
        presale.emergencyETHWithdraw();

        vm.stopPrank();
    }

    function testPauseSuccess() public {
        vm.startPrank(deployer);

        presale.pause();

        assertEq(presale.paused(), true, "Contract should be paused");

        vm.stopPrank();
    }

    function testPauseRevertsWhenNotOwner() public {
        vm.startPrank(user);

        vm.expectRevert();
        presale.pause();

        vm.stopPrank();
    }

    function testUnpauseSuccess() public {
        vm.startPrank(deployer);

        presale.pause();
        assertEq(presale.paused(), true, "Contract should be paused");

        presale.unpause();
        assertEq(presale.paused(), false, "Contract should no longer be paused");

        vm.stopPrank();
    }

    function testUnpauseRevertsWhenNotOwner() public {
        vm.startPrank(deployer);

        presale.pause();

        vm.stopPrank();
        vm.startPrank(user);

        vm.expectRevert();
        presale.unpause();

        vm.stopPrank();
    }

    function testConstructorRevertsWhenIncorrectTime() public {
        uint256 badStartingTime = block.timestamp;
        uint256 badEndingTime = badStartingTime;

        vm.expectRevert("Incorrect Time");
        new PresalePlus(
            address(saleToken),
            USDT,
            USDC,
            deployer,
            ethUsdPriceFeed,
            maxSellingAmount,
            maxPerWallet,
            badStartingTime,
            badEndingTime,
            vestingDuration,
            phases
        );
    }

    function testBuyWithStableCorrectlyWith18DecimalToken() public {
        MockStable18 mockStable = new MockStable18();

        vm.startPrank(deployer);
        MockToken newSaleToken = new MockToken();
        address predictedPresaleAddress = vm.computeCreateAddress(deployer, vm.getNonce(deployer));
        newSaleToken.approve(predictedPresaleAddress, maxSellingAmount);

        PresalePlus newPresale = new PresalePlus(
            address(newSaleToken),
            USDT,
            address(mockStable),
            deployer,
            ethUsdPriceFeed,
            maxSellingAmount,
            maxPerWallet,
            startingTime,
            endingTime,
            vestingDuration,
            phases
        );
        vm.stopPrank();

        mockStable.transfer(realUser, 1000 ether);

        vm.startPrank(realUser);
        uint256 amountToSpend = 5 ether;
        mockStable.approve(address(newPresale), amountToSpend);

        uint256 userTokenBalanceBefore = newPresale.userTokenBalance(realUser);
        newPresale.buyWithStable(address(mockStable), amountToSpend);
        uint256 userTokenBalanceAfter = newPresale.userTokenBalance(realUser);

        assertGt(
            userTokenBalanceAfter,
            userTokenBalanceBefore,
            "Should receive tokens when paying with an 18-decimal stablecoin"
        );

        vm.stopPrank();
    }

    function testEmergencyETHWithdrawRevertsOnTransferFail() public {
        RejectEther rejectOwner = new RejectEther();

        vm.store(address(presale), bytes32(uint256(0)), bytes32(uint256(uint160(address(rejectOwner)))));

        vm.deal(address(presale), 10 ether);
        vm.startPrank(address(rejectOwner));

        vm.expectRevert("Transfer Fail");
        presale.emergencyETHWithdraw();

        vm.stopPrank();
    }
} // forge test -vvvv --match-test
