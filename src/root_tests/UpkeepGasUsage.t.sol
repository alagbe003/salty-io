// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "forge-std/Test.sol";
import "../dev/Deployment.sol";
import "../root_tests/TestERC20.sol";
import "../pools/PoolUtils.sol";
import "../Upkeep.sol";
import "../pools/PoolsConfig.sol";
import "../price_feed/PriceAggregator.sol";
import "../ExchangeConfig.sol";
import "../staking/Liquidity.sol";
import "../stable/CollateralAndLiquidity.sol";
import "../pools/Pools.sol";
import "../staking/Staking.sol";
import "../rewards/RewardsEmitter.sol";
import "../dao/Proposals.sol";
import "../dao/DAO.sol";
import "../AccessManager.sol";
import "../launch/InitialDistribution.sol";


contract TestMaxUpkeep is Deployment
	{
    address public constant alice = address(0x1111);


	constructor()
		{
		// Transfer the salt from the original initialDistribution to the DEPLOYER
		vm.prank(address(initialDistribution));
		salt.transfer(DEPLOYER, 100000000 ether);

		vm.startPrank(DEPLOYER);

		poolsConfig = new PoolsConfig();
		usds = new USDS(wbtc, weth);

		exchangeConfig = new ExchangeConfig(salt, wbtc, weth, dai, usds, teamWallet );

		priceAggregator = new PriceAggregator();
		priceAggregator.setInitialFeeds( IPriceFeed(address(forcedPriceFeed)), IPriceFeed(address(forcedPriceFeed)), IPriceFeed(address(forcedPriceFeed)) );

		pools = new Pools(exchangeConfig, poolsConfig);
		staking = new Staking( exchangeConfig, poolsConfig, stakingConfig );
		collateralAndLiquidity = new CollateralAndLiquidity(pools, exchangeConfig, poolsConfig, stakingConfig, stableConfig, priceAggregator);

		stakingRewardsEmitter = new RewardsEmitter( staking, exchangeConfig, poolsConfig, rewardsConfig, false );
		liquidityRewardsEmitter = new RewardsEmitter( collateralAndLiquidity, exchangeConfig, poolsConfig, rewardsConfig, true );

		emissions = new Emissions( saltRewards, exchangeConfig, rewardsConfig );

		poolsConfig.whitelistPool(  salt, wbtc);
		poolsConfig.whitelistPool(  salt, weth);
		poolsConfig.whitelistPool(  salt, usds);
		poolsConfig.whitelistPool(  wbtc, usds);
		poolsConfig.whitelistPool(  weth, usds);
		poolsConfig.whitelistPool(  wbtc, dai);
		poolsConfig.whitelistPool(  weth, dai);
		poolsConfig.whitelistPool(  usds, dai);
		poolsConfig.whitelistPool(  wbtc, weth);

		proposals = new Proposals( staking, exchangeConfig, poolsConfig, daoConfig );

		address oldDAO = address(dao);
		dao = new DAO( pools, proposals, exchangeConfig, poolsConfig, stakingConfig, rewardsConfig, stableConfig, daoConfig, priceAggregator, liquidityRewardsEmitter);

		airdrop = new Airdrop(exchangeConfig, staking);

		accessManager = new AccessManager(dao);

		exchangeConfig.setAccessManager( accessManager );
		exchangeConfig.setStakingRewardsEmitter( stakingRewardsEmitter);
		exchangeConfig.setLiquidityRewardsEmitter( liquidityRewardsEmitter);
		exchangeConfig.setDAO( dao );
		exchangeConfig.setAirdrop(airdrop);

		saltRewards = new SaltRewards(exchangeConfig, rewardsConfig);

		upkeep = new Upkeep(pools, exchangeConfig, poolsConfig, daoConfig, priceAggregator, saltRewards, collateralAndLiquidity, emissions);
		exchangeConfig.setUpkeep(upkeep);

		bootstrapBallot = new BootstrapBallot(exchangeConfig, airdrop, 60 * 60 * 24 * 3 );
		initialDistribution = new InitialDistribution(salt, poolsConfig, emissions, bootstrapBallot, dao, daoVestingWallet, teamVestingWallet, airdrop, saltRewards, collateralAndLiquidity);
		exchangeConfig.setInitialDistribution(initialDistribution);

		pools.setContracts(dao, collateralAndLiquidity
);

		usds.setContracts(collateralAndLiquidity, pools, exchangeConfig );

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

		// Move the SALT to the new initialDistribution contract
		vm.prank(DEPLOYER);
		salt.transfer(address(initialDistribution), 100000000 ether);


		grantAccessAlice();
		grantAccessBob();
		grantAccessCharlie();
		grantAccessDeployer();
		grantAccessDefault();

		whitelistAlice();

		finalizeBootstrap();

		vm.prank(address(daoVestingWallet));
		salt.transfer(DEPLOYER, 1000000 ether);

		// Increase max pools to 100
		for( uint256 i = 0; i < 5; i++ )
			{
			vm.prank(address(dao));
			poolsConfig.changeMaximumWhitelistedPools(true);
			}

		_setupBaselineGas();
		}


	function _setupPools() public
		{
		vm.startPrank(DEPLOYER);
		wbtc.approve(address(collateralAndLiquidity), type(uint256).max);
		weth.approve(address(collateralAndLiquidity), type(uint256).max);
		salt.approve(address(collateralAndLiquidity), type(uint256).max);

		wbtc.approve(address(pools), type(uint256).max);
		weth.approve(address(pools), type(uint256).max);
		salt.approve(address(pools), type(uint256).max);
		wbtc.approve(address(collateralAndLiquidity), type(uint256).max);
		weth.approve(address(collateralAndLiquidity), type(uint256).max);

        collateralAndLiquidity.depositCollateralAndIncreaseShare(100 * 10**8, 100 ether, 0, block.timestamp, false);
        collateralAndLiquidity.depositLiquidityAndIncreaseShare(salt, wbtc, 100 ether, 100 * 10**8, 0, block.timestamp, false);
        collateralAndLiquidity.depositLiquidityAndIncreaseShare(salt, weth, 100 ether, 100 ether, 0, block.timestamp, false);
		vm.stopPrank();

		uint256 totalPools = 100;

    	// Create additional whitelisted pools
    	while( poolsConfig.numberOfWhitelistedPools() < ( totalPools - 4 ) )
    		{
			vm.startPrank(DEPLOYER);
    		IERC20 tokenA = new TestERC20( "TEST", 18 );
    		IERC20 tokenB = new TestERC20( "TEST", 18 );
    		vm.stopPrank();

    		vm.startPrank(address(dao));
    		poolsConfig.whitelistPool(  tokenA, tokenB);
    		poolsConfig.whitelistPool(  tokenA, weth);
    		poolsConfig.whitelistPool(  tokenA, wbtc);
    		poolsConfig.whitelistPool(  tokenB, weth);
    		poolsConfig.whitelistPool(  tokenB, wbtc);
			vm.stopPrank();

			vm.startPrank(DEPLOYER);
    		tokenA.approve(address(collateralAndLiquidity), type(uint256).max);
			tokenB.approve(address(collateralAndLiquidity), type(uint256).max);
    		tokenA.approve(address(pools), type(uint256).max);
			tokenB.approve(address(pools), type(uint256).max);

			// Multiple pools will be needed for arbitrage
            collateralAndLiquidity.depositLiquidityAndIncreaseShare(tokenA, tokenB, 100 ether, 100 ether, 0, block.timestamp, false);
            collateralAndLiquidity.depositLiquidityAndIncreaseShare(tokenA, weth, 100 ether, 100 ether, 0, block.timestamp, false);
            collateralAndLiquidity.depositLiquidityAndIncreaseShare(tokenA, wbtc, 100 ether, 100 * 10**8, 0, block.timestamp, false);
            collateralAndLiquidity.depositLiquidityAndIncreaseShare(tokenB, weth, 100 ether, 100 ether, 0, block.timestamp, false);
            collateralAndLiquidity.depositLiquidityAndIncreaseShare(tokenB, wbtc, 100 ether, 100 * 10**8, 0, block.timestamp, false);

	    	vm.stopPrank();
	    	}
		}


    function _placeTrades() public
    	{
		vm.startPrank(DEPLOYER);
    	bytes32[] memory poolIDs = poolsConfig.whitelistedPools();

    	// Performs swaps on all of the pools so that arbitrage profits exist everywhere
    	for( uint256 i = 9; i < poolIDs.length; i++ )
    		{
    		(IERC20 tokenA, IERC20 tokenB) = poolsConfig.underlyingTokenPair(poolIDs[i]);

            pools.depositSwapWithdraw(tokenA, tokenB, 10 ether, 0, block.timestamp, true);
    		}
    	vm.stopPrank();
    	}


	// Set the initial storage write baseline for performUpkeep()
    function _setupBaselineGas() internal
    	{
    	_setupPools();

    	_placeTrades();

		// One performUpkeep to write the initial storage variables (at higher gas cost)
    	vm.warp(block.timestamp + 1 hours);
    	upkeep.performUpkeep();

		vm.startPrank(DEPLOYER);
    	forcedPriceFeed.setBTCPrice(28000 ether);
    	forcedPriceFeed.setETHPrice(1800 ether);

		weth.transfer(address(usds), 1000 ether);
		wbtc.transfer(address(usds), 1000 * 10**8);

		weth.transfer(address(upkeep), 10 ether);
		wbtc.transfer(address(upkeep), 10 * 10**8);
    	vm.stopPrank();

		vm.startPrank(address(upkeep));
		weth.approve(address(pools), 10 ether);
		wbtc.approve(address(pools), 10 *10**8);

		pools.depositTokenForCounterswap(Counterswap.WETH_TO_SALT, weth, 5 ether);
		pools.depositTokenForCounterswap(Counterswap.WETH_TO_USDS, weth, 5 ether);
		pools.depositTokenForCounterswap(Counterswap.WBTC_TO_USDS, wbtc, 1 * 10**8);
		vm.stopPrank();

    	vm.prank(address(collateralAndLiquidity));
    	usds.shouldBurnMoreUSDS( 100 ether );

    	_placeTrades();

    	vm.warp(block.timestamp + 1 hours);
       	}


	// Determine gas usage for running performUpkeep() with the above pool setup, profits, and rewards to distribute to all pools
    function testGasMaxUpkeep() public
    	{
		// Just an extra performUpkeep() call
    	upkeep.performUpkeep();
    	}
	}
