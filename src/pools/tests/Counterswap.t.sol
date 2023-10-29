// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.21;

import "../../dev/Deployment.sol";
import "../../root_tests/TestERC20.sol";
import "../Pools.sol";
import "./TestPools.sol";
import "../../dev/Deployment.sol";
import "../PoolUtils.sol";
import "../Counterswap.sol";
import "../../pools/Pools.sol";
import "../../pools/PoolUtils.sol";
import "../../arbitrage/ArbitrageSearch.sol";
import "../../pools/Counterswap.sol";
import "../../rewards/SaltRewards.sol";
import "../../stable/CollateralAndLiquidity.sol";
import "../../ExchangeConfig.sol";
import "../../staking/Staking.sol";
import "../../rewards/RewardsEmitter.sol";
import "../../price_feed/tests/IForcedPriceFeed.sol";
import "../../price_feed/tests/ForcedPriceFeed.sol";
import "../../pools/PoolsConfig.sol";
import "../../price_feed/PriceAggregator.sol";
import "../../dao/Proposals.sol";
import "../../dao/DAO.sol";
import "../../AccessManager.sol";
import "../../launch/BootstrapBallot.sol";


contract TestCounterswap2 is Deployment
	{
	TestPools public _pools;


	constructor()
		{
		vm.prank(address(initialDistribution));
		salt.transfer(DEPLOYER, 100000000 ether );

		vm.startPrank(DEPLOYER);

		poolsConfig = new PoolsConfig();
		usds = new USDS(wbtc, weth);

		exchangeConfig = new ExchangeConfig(salt, wbtc, weth, dai, usds, teamWallet );

		priceAggregator = new PriceAggregator();
		priceAggregator.setInitialFeeds( IPriceFeed(address(forcedPriceFeed)), IPriceFeed(address(forcedPriceFeed)), IPriceFeed(address(forcedPriceFeed)) );

		_pools = new TestPools(exchangeConfig, poolsConfig);
		staking = new Staking( exchangeConfig, poolsConfig, stakingConfig );
		collateralAndLiquidity = new CollateralAndLiquidity(_pools, exchangeConfig, poolsConfig, stakingConfig, stableConfig, priceAggregator);

		stakingRewardsEmitter = new RewardsEmitter( staking, exchangeConfig, poolsConfig, rewardsConfig, false );
		liquidityRewardsEmitter = new RewardsEmitter( collateralAndLiquidity, exchangeConfig, poolsConfig, rewardsConfig, true );

		emissions = new Emissions( saltRewards, exchangeConfig, rewardsConfig );

		poolsConfig.whitelistPool(_pools, salt, wbtc);
		poolsConfig.whitelistPool(_pools, salt, weth);
		poolsConfig.whitelistPool(_pools, salt, usds);
		poolsConfig.whitelistPool(_pools, wbtc, usds);
		poolsConfig.whitelistPool(_pools, weth, usds);
		poolsConfig.whitelistPool(_pools, wbtc, dai);
		poolsConfig.whitelistPool(_pools, weth, dai);
		poolsConfig.whitelistPool(_pools, usds, dai);
		poolsConfig.whitelistPool(_pools, wbtc, weth);

		proposals = new Proposals( staking, exchangeConfig, poolsConfig, daoConfig );

		address oldDAO = address(dao);
		dao = new DAO( _pools, proposals, exchangeConfig, poolsConfig, stakingConfig, rewardsConfig, stableConfig, daoConfig, priceAggregator, liquidityRewardsEmitter);

		airdrop = new Airdrop(exchangeConfig, staking);

		accessManager = new AccessManager(dao);

		exchangeConfig.setAccessManager( accessManager );
		exchangeConfig.setStakingRewardsEmitter( stakingRewardsEmitter);
		exchangeConfig.setLiquidityRewardsEmitter( liquidityRewardsEmitter);
		exchangeConfig.setDAO( dao );
		exchangeConfig.setAirdrop(airdrop);

		saltRewards = new SaltRewards(exchangeConfig, rewardsConfig);

		upkeep = new Upkeep(_pools, exchangeConfig, poolsConfig, daoConfig, priceAggregator, saltRewards, collateralAndLiquidity, emissions);
		exchangeConfig.setUpkeep(upkeep);

		bootstrapBallot = new BootstrapBallot(exchangeConfig, airdrop, 60 * 60 * 24 * 3 );
		initialDistribution = new InitialDistribution(salt, poolsConfig, emissions, bootstrapBallot, dao, daoVestingWallet, teamVestingWallet, airdrop, saltRewards, collateralAndLiquidity);
		exchangeConfig.setInitialDistribution(initialDistribution);

		_pools.setContracts(dao, collateralAndLiquidity);

		usds.setContracts(collateralAndLiquidity, _pools, exchangeConfig );

		// Transfer ownership of the newly created config files to the DAO
		Ownable(address(exchangeConfig)).transferOwnership( address(dao) );
		Ownable(address(poolsConfig)).transferOwnership( address(dao) );
		Ownable(address(priceAggregator)).transferOwnership(address(dao));
		vm.stopPrank();

		vm.startPrank(address(oldDAO));
		Ownable(address(stakingConfig)).transferOwnership( address(dao) );
		Ownable(address(rewardsConfig)).transferOwnership( address(dao) );
		Ownable(address(stableConfig)).transferOwnership( address(dao) );
		Ownable(address(daoConfig)).transferOwnership( address(dao) );
		vm.stopPrank();

		vm.prank(DEPLOYER);
		salt.transfer(address(initialDistribution), 100000000 ether);


		grantAccessAlice();
		grantAccessBob();
		grantAccessCharlie();
		grantAccessDeployer();
		grantAccessDefault();

		finalizeBootstrap();

		vm.prank(address(daoVestingWallet));
		salt.transfer(DEPLOYER, 25000000 ether);
		}


	function setUp() public
		{
		// DEPLOYER should have all the test tokens alreayd, but needs some minted USDS
		vm.prank(address(collateralAndLiquidity));
		usds.mintTo( address(DEPLOYER), 1000000 ether );

		vm.startPrank(DEPLOYER);
		wbtc.approve( address(_pools), type(uint256).max );
		weth.approve( address(_pools), type(uint256).max );
		salt.approve( address(_pools), type(uint256).max );
		usds.approve( address(_pools), type(uint256).max );
		wbtc.approve( address(collateralAndLiquidity), type(uint256).max );
		weth.approve( address(collateralAndLiquidity), type(uint256).max );
		salt.approve( address(collateralAndLiquidity), type(uint256).max );
		usds.approve( address(collateralAndLiquidity), type(uint256).max );

		// Add initial liquidity
		collateralAndLiquidity.depositLiquidityAndIncreaseShare( wbtc, salt, 100 * 10**8, 1000 ether, 0, block.timestamp, true );
		collateralAndLiquidity.depositLiquidityAndIncreaseShare( weth, salt, 100 ether, 1000 ether, 0, block.timestamp, true );
		collateralAndLiquidity.depositLiquidityAndIncreaseShare( salt, usds, 100 ether, 1000 ether, 0, block.timestamp, true );
		collateralAndLiquidity.depositLiquidityAndIncreaseShare( wbtc, usds, 100 * 10**8, 1000 ether, 0, block.timestamp, true );
		collateralAndLiquidity.depositLiquidityAndIncreaseShare( weth, usds, 100 ether, 1000 ether, 0, block.timestamp, true );
		collateralAndLiquidity.depositCollateralAndIncreaseShare( 100 * 10**8, 1000 ether, 0, block.timestamp, true );

		// DAO needs some WBTC and WETH for the counterswap deposits
		wbtc.transfer(address(dao), 100000 * 10**8 );
		weth.transfer(address(dao), 100000 ether );

		vm.stopPrank();
		}


	// A unit test in which a non-DAO, non-USDS contract attempts to deposit tokens. This should not be allowed, according to the requirements specified in the depositToken function.
	function testNonDAOorUSDSDeposit() public
		{
		// Attempting to deposit tokens from an address that's not the DAO or USDS contract
		IERC20 tokenA = new TestERC20("TEST", 18);

		vm.expectRevert("Pools.depositTokenForCounterswap is only callable from the Upkeep or USDS contracts");
		pools.depositTokenForCounterswap(Counterswap.WETH_TO_SALT, tokenA, 5 ether);
		}


	function _testShouldCounterswap( IERC20 token0, IERC20 token1, uint256 swapAmountIn ) public {

		address counterswapAddress = Counterswap._determineCounterswapAddress( token0, token1, wbtc, weth, salt, usds );

		assertEq( _pools.depositedBalance(counterswapAddress, token0), 0, "Initial token0 balance should be zero" );
		assertEq( _pools.depositedBalance(counterswapAddress, token1), 0, "Initial token1 balance should be zero" );

		vm.prank(DEPLOYER);
		uint256 swapAmountOut = _pools.depositSwapWithdraw( token1, token0, swapAmountIn, 0, block.timestamp);

		vm.roll( block.number + 1 );

		// Deposit token0 for counterswapping to token1
		uint256 amountToDeposit = swapAmountOut * 75 / 100;

		vm.prank(address(dao));
		token0.transfer(address(upkeep), amountToDeposit);

		vm.startPrank(address(upkeep));
		token0.approve( address(_pools), type(uint256).max );
        _pools.depositTokenForCounterswap(counterswapAddress, token0, amountToDeposit);
        vm.stopPrank();

		// Check the deposited balances
		assertEq( _pools.depositedBalance(counterswapAddress, token0), amountToDeposit );

        // Checking shouldCounterswap when swapAmountOut is more than the deposited amount
        bool shouldCounterswapMore = _pools.shouldCounterswap(token1, token0, amountToDeposit + 100);
        assertFalse(shouldCounterswapMore, "shouldCounterswap should return false for swapAmountOut > deposit");
		assertEq( _pools.depositedBalance(counterswapAddress, token0), amountToDeposit );

        // Checking shouldCounterswap when swapAmountOut is less than the deposited amount
		vm.prank(DEPLOYER);
		_pools.depositSwapWithdraw( token1, token0, swapAmountIn, 0, block.timestamp);
		vm.roll( block.number + 1 );

        bool shouldCounterswapLess = _pools.shouldCounterswap(token1, token0, amountToDeposit - 100);
        assertTrue(shouldCounterswapLess, "shouldCounterswap should return true for swapAmountOut < deposit");
		assertEq( _pools.depositedBalance(counterswapAddress, token0), amountToDeposit );

		// Checking a swap made in the same block
		vm.prank(DEPLOYER);
		_pools.depositSwapWithdraw( token1, token0, swapAmountIn, 0, block.timestamp);

        bool shouldCounterswapLess2 = _pools.shouldCounterswap(token1, token0, amountToDeposit - 100);
        assertFalse(shouldCounterswapLess2, "shouldCounterswap should return false with a swap placed in the same block");
		assertEq( _pools.depositedBalance(counterswapAddress, token0), amountToDeposit );

    }


	// A unit test in which a token is deposited and then a shouldCounterswap check is made with the deposited and desired token, where the swapAmountOut is more than, less than, and equal to the deposited amount. The test should verify that shouldCounterswap correctly returns true or false based on the recent average ratio and the swap ratio, and that the _depositedTokens mapping is correctly updated.
	function testShouldCounterswap() public
		{
		_testShouldCounterswap(weth, wbtc, 1 * 10**8 );
		_testShouldCounterswap(weth, salt, 1 ether );
		_testShouldCounterswap(weth, usds, 1 ether );
		_testShouldCounterswap(wbtc, usds, 1 ether);
		}


	// A unit test to verify that the withdrawToken function fails when called by an address other than the DAO or USDS contracts.
    function testWithdrawTokenPermission() public {
    	IERC20 tokenToWithdraw = new TestERC20("TEST", 18);
    	uint256 amountToWithdraw = 5 ether;

    	// Attempting to withdraw tokens from an address that's not the DAO or USDS contract
    	vm.expectRevert("Pools.withdrawTokenFromCounterswap is only callable from the Upkeep or USDS contracts");
    	pools.withdrawTokenFromCounterswap(address(0x123), tokenToWithdraw, amountToWithdraw);
    }


	// A unit test to verify that the withdrawToken function correctly withdraws tokens from the Pools contract and transfers them to the caller.
	function _testWithdrawToken( IERC20 token0, IERC20 token1, uint256 amountToDeposit ) public {

		address counterswapAddress = Counterswap._determineCounterswapAddress( token0, token1, wbtc, weth, salt, usds );

		assertEq( _pools.depositedBalance(counterswapAddress, token0), 0, "Initial token0 balance should be zero" );
		assertEq( _pools.depositedBalance(counterswapAddress, token1), 0, "Initial token1 balance should be zero" );

		uint256 poolsBalance0 = token0.balanceOf( address(_pools) );

		vm.prank(address(dao));
		token0.transfer(address(upkeep), amountToDeposit);

		uint256 upkeepBalance0 = token0.balanceOf( address(upkeep) );

		vm.startPrank(address(upkeep));
		token0.approve( address(_pools), type(uint256).max );
		_pools.depositTokenForCounterswap(counterswapAddress, token0, amountToDeposit);
		vm.stopPrank();

		assertEq( _pools.depositedBalance(counterswapAddress, token0), amountToDeposit );

		uint256 upkeepBalance1 = token0.balanceOf( address(upkeep) );
		uint256 poolsBalance1 = token0.balanceOf( address(_pools) );

		assertEq( upkeepBalance1, upkeepBalance0 - amountToDeposit );
		assertEq( poolsBalance1, poolsBalance0 + amountToDeposit );

    	uint256 amountToWithdraw = amountToDeposit / 2;
    	vm.prank( address(upkeep) );
    	_pools.withdrawTokenFromCounterswap(counterswapAddress, token0, amountToWithdraw);

		uint256 upkeepBalance2 = token0.balanceOf( address(upkeep) );
		uint256 poolsBalance2 = token0.balanceOf( address(_pools) );

		assertEq( upkeepBalance2, upkeepBalance1 + amountToWithdraw );
		assertEq( poolsBalance2, poolsBalance1 - amountToWithdraw );
    }


	// A unit test ito test withdrawing tokens from counterswap
	function testWithdrawToken() public
		{
		_testWithdrawToken(weth, wbtc, 1 ether );
		_testWithdrawToken(weth, salt, 1 ether);
		_testWithdrawToken(weth, usds, 1 ether);
		_testWithdrawToken(wbtc, usds, 1 * 10**8);
		}



	// A unit test to verify that withdrawTokenFromCounterswap reverts when called by any other address than the specified ones.
	function testWithdrawTokenFromCounterswap() public {

		address counterswapAddress = Counterswap.WETH_TO_USDS;

      // Expect the function to revert to protect against unauthorized withdrawals
      vm.expectRevert("Pools.withdrawTokenFromCounterswap is only callable from the Upkeep or USDS contracts");
      _pools.withdrawTokenFromCounterswap(counterswapAddress, usds, 1 ether);
    }



	// A unit test to verify that the _determineCounterswapAddress function returns address zero when tokenToCounterswap and/or desiredToken do not match any of the pre-defined counterswap pairs.
	function testCheckCounterswapAddressReturnZero() public {
        IERC20 tokenNotMatched = new TestERC20("TEST", 18); // or any other token that is not in the pre-defined counterswap pairs

        // when tokenToCounterswap does not match
        address counterswapAddress = Counterswap._determineCounterswapAddress( tokenNotMatched, wbtc, wbtc, weth, salt, usds );
        assertEq(counterswapAddress, address(0), "Test failed when tokenToCounterswap does not match");

        // when desiredToken does not match
        counterswapAddress = Counterswap._determineCounterswapAddress( wbtc, tokenNotMatched, wbtc, weth, salt, usds );
        assertEq(counterswapAddress, address(0), "Test failed when desiredToken does not match");

        // when both tokenToCounterswap and desiredToken do not match
        counterswapAddress = Counterswap._determineCounterswapAddress( tokenNotMatched, tokenNotMatched, wbtc, weth, salt, usds );
        assertEq(counterswapAddress, address(0), "Test failed when both tokens do not match");
    }


   }



