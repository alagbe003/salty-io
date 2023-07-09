// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.12;

import "forge-std/Test.sol";
import "../../root_tests/TestERC20.sol";
import "../Pools.sol";
import "../../Deployment.sol";


contract TestPools is Test, Deployment
	{
	TestERC20[] private tokens = new TestERC20[](10);

	address public alice = address(0x1111);
	address public bob = address(0x2222);
	address public charlie = address(0x3333);


	constructor()
		{
		// If $COVERAGE=yes, create an instance of the contract so that coverage testing can work
		// Otherwise, what is tested is the actual deployed contract on the blockchain (as specified in Deployment.sol)
		if ( keccak256(bytes(vm.envString("COVERAGE" ))) == keccak256(bytes("yes" )))
			{
			vm.prank(DEPLOYER);
			pools = new Pools(exchangeConfig);
			}

		vm.startPrank( DEPLOYER );

		for( uint256 i = 0; i < 10; i++ )
			{
			tokens[i] = new TestERC20( 18 );
        	tokens[i].approve( address(pools), type(uint256).max );

        	tokens[i].transfer(address(this), 100000 ether );
			}

		for( uint256 i = 0; i < 9; i++ )
			{
			poolsConfig.whitelistPool( tokens[i], tokens[i + 1] );
			pools.addLiquidity( tokens[i], tokens[i + 1], 500 ether, 500 ether, 0, block.timestamp );
			}

		poolsConfig.whitelistPool( tokens[5], tokens[7] );
		pools.addLiquidity( tokens[5], tokens[7], 1000 ether, 1000 ether, 0, block.timestamp );

		pools.deposit( tokens[5], 1000 ether );
		pools.deposit( tokens[6], 1000 ether );
		pools.deposit( tokens[7], 1000 ether );
		pools.deposit( tokens[8], 1000 ether );

		poolsConfig.whitelistPool( tokens[0], tokens[9] );
		pools.addLiquidity( tokens[0], tokens[9], 1000000000 ether, 2000000000 ether, 0, block.timestamp );

		vm.stopPrank();

		for( uint256 i = 0; i < 10; i++ )
        	tokens[i].approve( address(pools), type(uint256).max );

		for( uint256 i = 0; i < 9; i++ )
			{
			pools.deposit( tokens[i], 1000 ether );
			pools.addLiquidity( tokens[i], tokens[i + 1], 500 ether, 500 ether, 0, block.timestamp );
        	}
		}



	function testGasAddLiquidity() public
		{
		vm.prank(DEPLOYER);
		pools.addLiquidity( tokens[0], tokens[1], 1000 ether, 1000 ether, 0, block.timestamp );
		}


	function testGasDualZap() public
		{
		pools.dualZapInLiquidity( tokens[0], tokens[1], 1000 ether, 2000 ether, 0, block.timestamp, false );
		}


	function testGasSwap() public
		{
		pools.depositSwapWithdraw(tokens[6], tokens[7], 10 ether, 5 ether, block.timestamp );
		}


	function testGasEcoSwap() public
		{
		IERC20[] memory arb = new IERC20[](2);
		arb[0] = tokens[5];
		arb[1] = tokens[6];

		pools.swap( arb, 10 ether, 5 ether, block.timestamp );
		}


	function testEmpty() public
		{
		}


	function testEmpty2() public
		{
		vm.startPrank(DEPLOYER);
		vm.stopPrank();
		}

	function testGasSwapAndAAA() public
		{
		pools.depositSwapWithdraw(tokens[6], tokens[7], 10 ether, 5 ether, block.timestamp );

		IERC20[] memory arb = new IERC20[](4);
		arb[0] = tokens[5];
		arb[1] = tokens[7];
		arb[2] = tokens[6];
		arb[3] = tokens[5];

		uint256 amountOut = pools.swap( arb, 1 ether, .5 ether, block.timestamp );
		console.log( "arbIn: ", 1 ether );
		console.log( "arbOut: ", amountOut );
		}


	// A unit test that ensures adding/removing liquidity fails when token0 and token1 are identical.
	function testAddRemoveLiquidityIdenticalTokens() public
    	{
		vm.startPrank(DEPLOYER);

        TestERC20 token0 = tokens[0];
        TestERC20 token1 = tokens[0];

        // Test that adding liquidity fails when token0 and token1 are the same.
        vm.expectRevert("Cannot add liquidity for duplicate tokens");
        pools.addLiquidity(token0, token1, 100 ether, 100 ether, 0, block.timestamp);

        // Test that removing liquidity fails when token0 and token1 are the same.
        vm.expectRevert("Cannot remove more liquidity than the current balance");
        pools.removeLiquidity(token0, token1, 50 ether, 0 ether, 0 ether, block.timestamp);
	    }


	// A unit test that handles a scenario where maxAmount0 exceeds the pool reserve ratio. The test should confirm that the function uss maxAmount1 and a proportional amoutn of maxAmount0, updates the reserves, and adjusts user's token balance
	function testAddLiquidityWithExceededMaxAmount0() public {
		vm.startPrank(DEPLOYER);

        // Define tokens for the test
        TestERC20 token0 = tokens[0];
        TestERC20 token1 = tokens[1];

		uint256 userBalance0 = token0.balanceOf( address(DEPLOYER) );
        uint256 userBalance1 = token1.balanceOf( address(DEPLOYER) );

        // Define maxAmount0 and maxAmount1
        uint256 maxAmount0 = 1500 ether;
        uint256 maxAmount1 = 1000 ether;

        // Get the current reserves before adding liquidity
        (uint256 reserve0Before, uint256 reserve1Before) = pools.getPoolReserves(token0, token1);

        // Calculate expected proportional maxAmount0
        uint256 expectedProportionalAmount0 = (maxAmount1 * reserve0Before) / reserve1Before;

        // Add liquidity
        pools.addLiquidity(token0, token1, maxAmount0, maxAmount1, 0, block.timestamp);

        // Get the reserves after adding liquidity
        (uint256 reserve0After, uint256 reserve1After) = pools.getPoolReserves(token0, token1);

        // Assert that the reserves have been updated correctly
        assertEq(reserve0After, reserve0Before + expectedProportionalAmount0);
        assertEq(reserve1After, reserve1Before + maxAmount1);

        assertEq( token0.balanceOf(address(DEPLOYER)), userBalance0 - expectedProportionalAmount0);
        assertEq( token1.balanceOf(address(DEPLOYER)), userBalance1 - maxAmount1);
    }


	// A unit test that handles a scenario where maxAmount1 exceeds the pool reserve ratio. The test should confirm that the function uss maxAmount1 and a proportional amoutn of maxAmount1, updates the reserves, and adjusts user's token balance
	function testAddLiquidityWithExceededMaxAmount1() public {
		vm.startPrank(DEPLOYER);

		// Define tokens for the test
        TestERC20 token0 = tokens[0];
        TestERC20 token1 = tokens[1];

		uint256 userBalance0 = token0.balanceOf( address(DEPLOYER) );
        uint256 userBalance1 = token1.balanceOf( address(DEPLOYER) );

        // Define maxAmount0 and maxAmount1
        uint256 maxAmount0 = 1000 ether;
        uint256 maxAmount1 = 1500 ether;

        // Get the current reserves before adding liquidity
        (uint256 reserve0Before, uint256 reserve1Before) = pools.getPoolReserves(token0, token1);

        // Calculate expected proportional maxAmount1
        uint256 expectedProportionalAmount1 = (maxAmount0 * reserve1Before) / reserve0Before;

        // Add liquidity
        pools.addLiquidity(token0, token1, maxAmount0, maxAmount1, 0, block.timestamp);

        // Get the reserves after adding liquidity
        (uint256 reserve0After, uint256 reserve1After) = pools.getPoolReserves(token0, token1);

        // Assert that the reserves have been updated correctly
        assertEq(reserve0After, reserve0Before + maxAmount0);
        assertEq(reserve1After, reserve1Before + expectedProportionalAmount1);

        assertEq( token0.balanceOf(address(DEPLOYER)), userBalance0 - maxAmount0);
        assertEq( token1.balanceOf(address(DEPLOYER)), userBalance1 - expectedProportionalAmount1);
    }


	// A unit test that verifies a token swap fails when the tokens array contains fewer than two tokens or more than two tokens, but the user hasn't deposited enough of the original token in the swap chain
	function testSwapFailures() public {
		vm.startPrank(DEPLOYER);

		// test for case where tokens array contains fewer than two tokens
        IERC20[] memory tokens1 = new IERC20[](1);
        tokens1[0] = tokens[0];

		uint256 amountIn = 300 ether;

        vm.expectRevert("Must swap at least two tokens");
        pools.swap(tokens1, amountIn, 1 ether, block.timestamp);

        // test for case where tokens array contains more than two tokens, but the user doesn't possess enough of one of the intermediate tokens
        IERC20[] memory tokens3 = new IERC20[](3);
        tokens3[0] = tokens[0];
        tokens3[1] = tokens[1];
        tokens3[2] = tokens[2];

        // Despoit an insufficient balance of the initial token
        pools.deposit( tokens[0], amountIn - 1);

        vm.expectRevert("Insufficient deposited token balance of initial token");
        pools.swap(tokens3, amountIn, 1 ether, block.timestamp);
    }


	// A unit test that handles scenarios related to exceeding pool reserve ratio, updating reserves, and adjusting user's token balance though deposits and withdrawals.
	function testReserveAndBalanceManagement() public
    	{
		vm.startPrank(DEPLOYER);

    	(uint256 token5PoolReserve, uint256 token7PoolReserve) = pools.getPoolReserves(tokens[5], tokens[7]);

    	// Scenario: Add liquidity and update pool reserves
    	poolsConfig.whitelistPool(tokens[5], tokens[7] );
    	pools.addLiquidity(tokens[5], tokens[7], 1 ether, 1 ether, 0, block.timestamp + 1 minutes);

    	(uint256 token5PoolReserves2, uint256 token7PoolReserves2) = pools.getPoolReserves(tokens[5], tokens[7]);

    	assertEq(token5PoolReserve + 1 ether, token5PoolReserves2, "Pool reserve for token5 not updated correctly");
    	assertEq(token7PoolReserve + 1 ether, token7PoolReserves2, "Pool reserve for token7 not updated correctly");

    	// Scenario: Adjust user's token balance by depositing and withdrawing token
    	uint256 initialToken5Balance = tokens[5].balanceOf(address(DEPLOYER));
    	uint256 initialToken7Balance = tokens[7].balanceOf(address(DEPLOYER));

    	pools.deposit(tokens[5], 1 ether);
    	pools.deposit(tokens[7], 1 ether);

    	assertEq(initialToken5Balance - 1 ether, tokens[5].balanceOf(address(DEPLOYER)), "Token5 balance not reduced after deposit");
    	assertEq(initialToken7Balance - 1 ether, tokens[7].balanceOf(address(DEPLOYER)), "Token7 balance not reduced after deposit");

    	pools.withdraw(tokens[5], 1 ether);
    	pools.withdraw(tokens[7], 1 ether);

    	assertEq(initialToken5Balance, tokens[5].balanceOf(address(DEPLOYER)), "Token5 balance not restored after withdrawal");
    	assertEq(initialToken7Balance, tokens[7].balanceOf(address(DEPLOYER)), "Token7 balance not restored after withdrawal");
    	}


	// Test a token swap and check that k = reserve0 * reserve1 remains constant
	function _checkSwapK( uint256 added0, uint256 added1, uint256 added1b, uint256 added2, uint256 amountIn ) internal
		{
		vm.startPrank(DEPLOYER);

		IERC20 token0 = new TestERC20(6);
		IERC20 token1 = new TestERC20(18);
		IERC20 token2 = new TestERC20(6);

			{
			poolsConfig.whitelistPool(token0, token1);
			poolsConfig.whitelistPool(token1, token2);

			token0.approve( address(pools), type(uint256).max );
			token1.approve( address(pools), type(uint256).max );
			token2.approve( address(pools), type(uint256).max );

			pools.addLiquidity(token0, token1, added0, added1, 0, block.timestamp );
			pools.addLiquidity(token1, token2, added1b, added2, 0, block.timestamp );

			uint256 amountOut = pools.depositSwapWithdraw(token0, token1, amountIn, 0, block.timestamp);
			pools.depositSwapWithdraw(token1, token2, amountOut, 0, block.timestamp);
			}

		// Check that k is still the same
		(uint256 reserves0, uint256 reserves1) = pools.getPoolReserves(token0, token1);
		(uint256 reserves1b, uint256 reserves2) = pools.getPoolReserves(token1, token2);

		assertEq( ( reserves0 * reserves1 + 5*10**21 ) / 10**22, added0 * added1 / 10**22, "k(0-1) not equal" );
		assertEq( ( reserves1b * reserves2 + 5*10**21 ) / 10**22, added1b * added2 / 10**22, "k(1-2) not equal" );

		vm.stopPrank();
		}


	function testCheckSwapK() public
		{
		_checkSwapK( 1000 * 10**6, 2000 ether, 3000 ether, 4000 * 10**6, 500 * 10**6 );
		_checkSwapK( 4000 * 10**6, 3000 ether, 3000 ether, 1000 * 10**6, 500 * 10**6 );
		_checkSwapK( 1000 * 10**6, 2000 ether, 500 ether, 1000 * 10**6, 500 * 10**6 );
		_checkSwapK( 2000 * 10**6, 1000 ether, 2000 ether, 1000 * 10**6, 500 * 10**6 );
		}


	// A unit test that verifies token swap succeeds when the tokens array is adequate and user possesses all tokens.
	function testSuccessfulTokenSwap() public
    {
   		vm.startPrank(DEPLOYER);

        // Define the array of tokens to be used in the swap operation
        IERC20[] memory chain = new IERC20[](3);
        chain[0] = tokens[2];   // First token
        chain[1] = tokens[3];   // Second token
        chain[2] = tokens[4];   // Third token

		// Make sure the user starts with zero deposited tokens[4]
		assertEq( pools.getUserDeposit( address(DEPLOYER), tokens[4] ), 0, "tokenOut should initial have zero deposits" );

        // Define the amount of the initial token to be used in the swap
        uint256 amountIn = 100 ether;

        // Define the minimum amount of the final token to be received from the swap
        uint256 minAmountOut = 1 ether;

        // Current timestamp plus 5 minutes
        uint256 deadline = block.timestamp + 5 minutes;

		pools.deposit(tokens[2], amountIn - 101 );

        // Call the swap function on the pools contract
		vm.expectRevert( "Insufficient deposited token balance of initial token" );
        pools.swap(chain, amountIn, minAmountOut, deadline);

		pools.deposit(tokens[2], 101 );
        pools.swap(chain, amountIn, minAmountOut, deadline);

		// Check that the user's deposited amount of tokens[2] is zero
		assertEq( pools.getUserDeposit( address(DEPLOYER), tokens[2] ), 0, "tokenIn deposited balance should now be zero" );

        // Check that the deposited balance of token is correct
        // the reserves for all pools in the transfer will initially be 1000 for each token
        assertEq(pools.getUserDeposit( address(DEPLOYER), tokens[4] ), 83.333333333333333334 ether , "Incorrect amountOut for final token in chain");
    }


	// A unit test that checks depositSwapWithdraw fails under various conditions, such as insufficient balance or allowance and verifies its correct operation under valid conditions.
	function testDepositSwapWithdraw() public {

        uint256 amountIn = 200 ether;

		vm.startPrank( alice );
		IERC20 token = new TestERC20( 18 );
		token.transfer( address(DEPLOYER), amountIn - 1 );
		vm.stopPrank();

  		vm.startPrank(DEPLOYER);

        IERC20 tokenIn = token;
        IERC20 tokenOut = tokens[1];
        poolsConfig.whitelistPool(tokenIn, tokenOut);

        uint256 minAmountOut = 1 ether;

		// Insufficient allowance?
		vm.expectRevert( "ERC20: insufficient allowance" );
        pools.depositSwapWithdraw(tokenIn, tokenOut, amountIn, minAmountOut, block.timestamp + 1 minutes);

       	tokenIn.approve( address(pools), type(uint256).max );

        // Test for insufficient tokenIn balance
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        pools.depositSwapWithdraw(tokenIn, tokenOut, amountIn, minAmountOut, block.timestamp + 1 minutes);

        vm.stopPrank();

        // Provide necessary balance
		vm.prank( alice );
        tokenIn.transfer(address(DEPLOYER), 1);

        // Test for low reserves
        vm.warp(block.timestamp + 1 hours);

  		vm.startPrank(DEPLOYER);
        vm.expectRevert("Insufficient reserve0 for swap");
        pools.depositSwapWithdraw(tokenIn, tokenOut, amountIn, minAmountOut, block.timestamp + 1 minutes);
		vm.stopPrank();

        // Add enough liquidity
        vm.startPrank( alice );
		tokenIn.approve( address(pools), type(uint256).max );
		tokenOut.approve( address(pools), type(uint256).max );

		vm.expectRevert( "ERC20: transfer amount exceeds balance" );
        pools.addLiquidity(tokenIn, tokenOut, 1000 ether, 1000 ether, 0, block.timestamp + 1 minutes);
        vm.stopPrank();

  		vm.prank(DEPLOYER);
        tokenOut.transfer(alice, 1000 ether );

		vm.startPrank( alice );
        pools.addLiquidity(tokenIn, tokenOut, 1000 ether, 1000 ether, 0, block.timestamp + 1 minutes);

        // Test for correct operation under valid conditions
        assertEq( tokenOut.balanceOf( alice ), 0, "Test wallet shoudl start with zero tokenOut" );
        uint256 amountOut = pools.depositSwapWithdraw(tokenIn, tokenOut, amountIn, minAmountOut, block.timestamp + 1 minutes);

        assertEq(amountOut, 166.666666666666666667 ether, "Unexpected amountOut");

        assertEq( tokenOut.balanceOf( alice ), amountOut, "Test wallet tokenOut balance is not amountOut" );
        vm.stopPrank();
    }


	// A unit test that tests all functions with invalid user addresses, non-existent tokens, or a token that has not been deposited, and returns zero for all such cases. This test also includes calls from the contract's owner.
	function testInvalidInputs() public {
   		vm.startPrank(DEPLOYER);

        // Invalid user addresses and non-existent tokens
        IERC20 nonExistentToken = IERC20(address(0));

        // Test with invalid user address and non-existent token
        assertEq(0, pools.getUserDeposit(address(0), nonExistentToken));

//        assertEq(0, pools.getTotalReserveForToken(nonExistentToken)); // will fail on nonExistentToken.balanceOf

        assertEq(0, pools.getUserLiquidity(address(0), tokens[0], nonExistentToken));
        (bytes32 poolID,) = PoolUtils.poolID(tokens[0], nonExistentToken);
        assertEq(0, pools.totalLiquidity(poolID));

		// Will fail due to reliance on balance of
//        vm.expectRevert("Insufficient allowance to deposit");
//        pools.deposit(nonExistentToken, 1000 ether);
//        vm.expectRevert("Insufficient balance to withdraw specified amount");
//        pools.withdraw(nonExistentToken, 1000 ether);

        // Test with token that has not been deposited
        IERC20 undepositedToken = new TestERC20( 18 );
        poolsConfig.whitelistPool(tokens[0], undepositedToken);

        assertEq(0, pools.getUserDeposit(address(DEPLOYER), undepositedToken));
        assertEq(0, pools.getUserLiquidity(address(DEPLOYER), tokens[0], undepositedToken));
        (poolID,) = PoolUtils.poolID(tokens[0], undepositedToken);
        assertEq(0, pools.totalLiquidity(poolID));

        vm.expectRevert("ERC20: insufficient allowance");
        pools.addLiquidity(tokens[0], undepositedToken, 1000 ether, 1000 ether, 0, block.timestamp + 300);

        undepositedToken.approve( address(pools), type(uint256).max );

		vm.expectRevert( "The amount of liquidityToRemove cannot be zero" );
        pools.removeLiquidity(tokens[0], undepositedToken, 0, 1000 ether, 1000 ether, block.timestamp + 300);

        vm.expectRevert("Insufficient balance to withdraw specified amount");
        pools.withdraw(undepositedToken, 1000 ether);

        IERC20[] memory tokensArray = new IERC20[](2);
        tokensArray[0] = undepositedToken;
        tokensArray[1] = tokens[0];

        vm.expectRevert("Insufficient deposited token balance of initial token");
        pools.swap(tokensArray, 1000 ether, 1 ether, block.timestamp + 300);

        vm.expectRevert("Insufficient reserve0 for swap");
        pools.depositSwapWithdraw(undepositedToken, tokens[0], 1000 ether, 1 ether, block.timestamp + 300);
    }


	// A unit test that ensures addLiquidity fails under various conditions and validates its correct initialization and operation under valid conditions.
	function testAddLiquidity() public
    {
   		vm.startPrank(DEPLOYER);

        IERC20 tokenA = new TestERC20( 18 );
        IERC20 tokenB = new TestERC20( 18 );
		poolsConfig.whitelistPool(tokenA, tokenB);

        // Check that adding liquidity with the same token fails
        vm.expectRevert("Cannot add liquidity for duplicate tokens");
        pools.addLiquidity(tokenA, tokenA, 10 ether, 10 ether, 0, block.timestamp + 100);

        // Check that adding liquidity with insufficient allowance fails
        vm.expectRevert("ERC20: insufficient allowance");
        pools.addLiquidity(tokenA, tokenB, 10 ether, 10 ether, 0, block.timestamp + 100);

        // Check that adding liquidity with insufficient balance fails
        tokenA.approve(address(pools), 5 ether);
        tokenB.approve(address(pools), 5 ether);
        vm.expectRevert("ERC20: insufficient allowance");
        pools.addLiquidity(tokenA, tokenB, 10 ether, 10 ether, 0, block.timestamp + 100);

		// Send all of token A elsewhere
		tokenA.transfer( address(0x1111), tokenA.balanceOf(address(DEPLOYER)));

        tokenA.approve(address(pools), 10 ether);
        tokenB.approve(address(pools), 10 ether);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        pools.addLiquidity(tokenA, tokenB, 10 ether, 10 ether, 0, block.timestamp + 100);
		vm.stopPrank();

		vm.startPrank( address(0x1111) );
		tokenA.transfer( address(DEPLOYER), tokenA.balanceOf(address(0x1111)));
		vm.stopPrank();

   		vm.startPrank(DEPLOYER);

        // Now add valid liquidity and confirm it has been added
        uint256 initialA = tokenA.balanceOf(address(DEPLOYER));
        uint256 initialB = tokenB.balanceOf(address(DEPLOYER));
        pools.addLiquidity(tokenA, tokenB, 10 ether, 10 ether, 0, block.timestamp + 100);
        assertEq(initialA - 10 ether, tokenA.balanceOf(address(DEPLOYER)));
        assertEq(initialB - 10 ether, tokenB.balanceOf(address(DEPLOYER)));

        // Check liquidity pool state
        (uint256 poolA, uint256 poolB) = pools.getPoolReserves(tokenA, tokenB);
        assertEq(poolA, 10 ether);
        assertEq(poolB, 10 ether);
    }


	// A unit test that checks removeLiquidity failure conditions and confirms its correct operation when the user has enough liquidity.
	function _testRemoveLiquidity() public
    {
   		vm.startPrank(DEPLOYER);

        IERC20 token0 = new TestERC20(18);
        IERC20 token1 = new TestERC20(6);

		poolsConfig.whitelistPool(token0, token1);
        token0.approve(address(pools), type(uint256).max);
        token1.approve(address(pools), type(uint256).max);

		uint256 added0 = 2000 ether;
		uint256 added1 = 1000 * 10 ** 6;

        (,, uint256 liquidityAdded) = pools.addLiquidity(token0, token1, added0, added1, 0, block.timestamp );
		uint256 deadline = block.timestamp;

        // Test failure when liquidityToRemove is too small
        vm.expectRevert("Insufficient underlying tokens returned");
        pools.removeLiquidity(token0, token1, 10, added0, added1, deadline);

        // Test failure when user doesn't have enough liquidity
        vm.expectRevert("Cannot remove more liquidity than the current balance");
        pools.removeLiquidity(token0, token1, liquidityAdded + 1, added0, added1, deadline);

        // Test failure when minReclaimed0 is not met
        vm.expectRevert("Insufficient underlying tokens returned");
        pools.removeLiquidity(token0, token1, liquidityAdded, added0 + 1, added1, deadline);

        // Test failure when minReclaimed1 is not met
        vm.expectRevert("Insufficient underlying tokens returned");
        pools.removeLiquidity(token0, token1, liquidityAdded, added0, added1 + 1, deadline);

        // Test successful operation
        (uint256 reclaimed0, uint256 reclaimed1) = pools.removeLiquidity(token0, token1, liquidityAdded, added0, added1, deadline);

        assertEq(reclaimed0, added0, "Reclaimed amount for token0 does not match expected amount");
        assertEq(reclaimed1, added1, "Reclaimed amount for token1 does not match expected amount");

        vm.stopPrank();
    }

	function testRemoveLiquidity() public
		{
		// Run the test multiple times to allow different reserve token order for the tokens
		for( uint256 i = 0; i < 20; i++ )
			_testRemoveLiquidity();
		}


	// A unit test that tests depositing and withdrawing tokens, both under failure conditions (insufficient balance, allowance, or deposited tokens) and correct operations.
	function testDepositWithdraw() public {
   		vm.startPrank(DEPLOYER);

        TestERC20 token = new TestERC20( 18 );

        uint256 initialBalance = token.balanceOf(address(DEPLOYER));

        // Test deposit
        uint256 depositAmount = 500 ether;
        vm.expectRevert( "ERC20: insufficient allowance" );
        pools.deposit(token, depositAmount);

        token.approve(address(pools), 1000 ether);
        pools.deposit(token, depositAmount);

        assertEq(token.balanceOf(address(DEPLOYER)), initialBalance - depositAmount);
        assertEq(pools.getUserDeposit(address(DEPLOYER), token), depositAmount);

        // Test failure when trying to withdraw more than the deposited amount
        vm.expectRevert("Insufficient balance to withdraw specified amount");
        pools.withdraw(token, depositAmount + 1);

        pools.withdraw(token, depositAmount);

        // Test failure when trying to withdraw without having any remaining tokens
        vm.expectRevert("Insufficient balance to withdraw specified amount");
        pools.withdraw(token, 1);

        // Test depositing more tokens and then withdrawing
        depositAmount = 250 ether;

        pools.deposit(token, depositAmount);
        assertEq(token.balanceOf(address(DEPLOYER)), initialBalance - depositAmount);
        assertEq(pools.getUserDeposit(address(DEPLOYER), token), depositAmount);

        uint256 withdrawAmount = 100 ether;
        pools.withdraw(token, withdrawAmount);
        assertEq(token.balanceOf(address(DEPLOYER)), initialBalance - depositAmount + withdrawAmount);
        assertEq(pools.getUserDeposit(address(DEPLOYER), token), depositAmount - withdrawAmount);

        // Test withdrawing all remaining deposited tokens
        pools.withdraw(token, depositAmount - withdrawAmount);
        assertEq(token.balanceOf(address(DEPLOYER)), initialBalance);
        assertEq(pools.getUserDeposit(address(DEPLOYER), token), 0);
    }


	// A unit test that verifies a token swap fails under various conditions and checks a valid token swap with multiple tokens in the path.
	function testTokenSwap() public
    {
   		vm.startPrank(DEPLOYER);

        // Test that swap fails with only one token
        IERC20[] memory oneToken = new IERC20[](1);
        oneToken[0] = tokens[0];
        vm.expectRevert("Must swap at least two tokens");
        pools.swap(oneToken, 500 ether, 1 ether, block.timestamp + 60);

        // Test that swap fails with insufficient balance
        IERC20[] memory twoTokens = new IERC20[](2);
        twoTokens[0] = tokens[5];
        twoTokens[1] = tokens[6];
        vm.expectRevert("Insufficient deposited token balance of initial token");
        pools.swap(twoTokens, 1500 ether, 1 ether, block.timestamp + 60);

        IERC20[] memory threeTokens = new IERC20[](3);
        threeTokens[0] = tokens[5];
        threeTokens[1] = tokens[6];
        threeTokens[2] = tokens[7];
        vm.expectRevert("Insufficient resulting token amount");
        pools.swap(threeTokens, 500 ether, 1500 ether, block.timestamp + 60);

        // Test valid swap with two tokens
        pools.swap(twoTokens, 500 ether, 1 ether, block.timestamp + 60);
        assertEq(pools.getUserDeposit(address(DEPLOYER), tokens[5]), 500 ether);

        (bytes32 poolID,) = PoolUtils.poolID(twoTokens[0], twoTokens[1]);
		(, , uint256 lastSwapTimestamp) = pools.poolInfo(poolID);
		assertEq( lastSwapTimestamp, block.timestamp );

		vm.warp( block.timestamp + 1 hours );

        // Deposit of tokenOut from setup was 1000 ether - 333.3333 ether more is expected from the trade
        assertEq(pools.getUserDeposit(address(DEPLOYER), tokens[6]), 1333.333333333333333334 ether);

		pools.getPoolReserves(tokens[5], tokens[6]);
		pools.getPoolReserves(tokens[6], tokens[7]);

        // Test valid swap with three tokens
        pools.swap(threeTokens, 500 ether, 1 ether, block.timestamp + 60);
        assertEq(pools.getUserDeposit(address(DEPLOYER), tokens[7]), 1142.857142857142857144 ether);

        (poolID,) = PoolUtils.poolID(threeTokens[0], threeTokens[1]);
		(, , lastSwapTimestamp) = pools.poolInfo(poolID);
		assertEq( lastSwapTimestamp, block.timestamp );

        (poolID,) = PoolUtils.poolID(threeTokens[1], threeTokens[2]);
		(, , lastSwapTimestamp) = pools.poolInfo(poolID);
		assertEq( lastSwapTimestamp, block.timestamp );
    }


	// A unit test that checks that the output from one three token swap is the same as 2 two token swaps and 2 depositSwapWithdraw swaps
	function testOutputThreeTokenSwapVsTwoTwoTokenSwaps() public {
   		vm.startPrank(DEPLOYER);

        uint256 amountIn = 500 ether;
        uint256 minAmountOut = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;

        // Three token swap
        IERC20[] memory tokensThree = new IERC20[](3);
        tokensThree[0] = new TestERC20( 18 );
        tokensThree[1] = new TestERC20( 18 );
        tokensThree[2] = new TestERC20( 18 );

		// Approve and create the liquidity for the three token swap
    	tokensThree[0].approve(address(pools), type(uint256).max);
		tokensThree[1].approve(address(pools), type(uint256).max);
		tokensThree[2].approve(address(pools), type(uint256).max);

		poolsConfig.whitelistPool(tokensThree[0], tokensThree[1]);
		poolsConfig.whitelistPool(tokensThree[1], tokensThree[2]);

        pools.addLiquidity( tokensThree[0], tokensThree[1], 1000 ether, 500 ether, 0, deadline );
        pools.addLiquidity( tokensThree[0], tokensThree[1], 1000 ether, 500 ether, 0, deadline );
        pools.addLiquidity( tokensThree[1], tokensThree[2], 500 ether, 500 ether, 0, deadline );

		pools.deposit( tokensThree[0], amountIn );
        uint256 amountOutThree = pools.swap(tokensThree, amountIn, minAmountOut, deadline);

        // Two two token swaps
        // New tokens
        tokensThree[0] = new TestERC20( 18 );
        tokensThree[1] = new TestERC20( 18 );
        tokensThree[2] = new TestERC20( 18 );

		poolsConfig.whitelistPool(tokensThree[0], tokensThree[1]);
		poolsConfig.whitelistPool(tokensThree[1], tokensThree[2]);

		// Approve and create fresh liquidity for the 2 two token swaps
    	tokensThree[0].approve(address(pools), type(uint256).max);
		tokensThree[1].approve(address(pools), type(uint256).max);
		tokensThree[2].approve(address(pools), type(uint256).max);

        pools.addLiquidity( tokensThree[0], tokensThree[1], 1000 ether, 500 ether, 0, deadline );
        pools.addLiquidity( tokensThree[0], tokensThree[1], 1000 ether, 500 ether, 0, deadline );
        pools.addLiquidity( tokensThree[1], tokensThree[2], 500 ether, 500 ether, 0, deadline );


        IERC20[] memory tokensTwo = new IERC20[](2);
        tokensTwo[0] = tokensThree[0];
        tokensTwo[1] = tokensThree[1];

		pools.deposit( tokensTwo[0], amountIn );
        uint256 amountOutTwoA = pools.swap(tokensTwo, amountIn, minAmountOut, deadline);

        tokensTwo[0] = tokensThree[1];
        tokensTwo[1] = tokensThree[2];
        uint256 amountOutTwoB = pools.swap(tokensTwo, amountOutTwoA, minAmountOut, deadline);

        // Assert that the amount out from three token swap is the same as the amount out from two two token swaps
        assertEq(amountOutThree, amountOutTwoB, "The amount out from one three token swap is not the same as the amount out from two equaivalent two token swaps");


       	// Should be the same as two testDepositSwapWithdraws() as well
        // New tokens
        tokensThree[0] = new TestERC20( 18 );
        tokensThree[1] = new TestERC20( 18 );
        tokensThree[2] = new TestERC20( 18 );

		poolsConfig.whitelistPool(tokensThree[0], tokensThree[1]);
		poolsConfig.whitelistPool(tokensThree[1], tokensThree[2]);

		// Approve and create fresh liquidity for the 2 two token swaps
    	tokensThree[0].approve(address(pools), type(uint256).max);
		tokensThree[1].approve(address(pools), type(uint256).max);
		tokensThree[2].approve(address(pools), type(uint256).max);

        pools.addLiquidity( tokensThree[0], tokensThree[1], 1000 ether, 500 ether, 0, deadline );
        pools.addLiquidity( tokensThree[0], tokensThree[1], 1000 ether, 500 ether, 0, deadline );
        pools.addLiquidity( tokensThree[1], tokensThree[2], 500 ether, 500 ether, 0, deadline );


        uint256 amountOutTwoC = pools.depositSwapWithdraw(tokensThree[0], tokensThree[1], amountIn, minAmountOut, deadline);
        uint256 amountOutTwoD = pools.depositSwapWithdraw(tokensThree[1], tokensThree[2], amountOutTwoC, minAmountOut, deadline);

        // Assert that the amount out from three token swap is the same as the amount out from 2 depositSwapWithdraw swaps
        assertEq(amountOutThree, amountOutTwoD, "The amount out from one three token swap is not the same as the amount out from two equaivalent depositSwapWithdraw swaps");
    }



	// A unit test that validates view functions (getUserLiquidity, getTotalLiquidity, getPoolReserves) with valid data.
	function testViewFunctions() public
    	{
   		vm.startPrank(DEPLOYER);

    	IERC20 token0 = tokens[5];
    	IERC20 token1 = tokens[6];

    	// User liquidity is sqrt(amount0 * amount1) and 1000 ether of each token were initially deposited
    	uint256 userLiquidity = pools.getUserLiquidity(address(DEPLOYER), token0, token1);
    	assertEq(userLiquidity, 500 ether, "User liquidity mismatch");

    	// View total liquidity
    	(bytes32 poolID,) = PoolUtils.poolID(token0, token1);
    	uint256 totalLiquidity = pools.totalLiquidity(poolID);
    	assertEq(totalLiquidity, 1000 ether, "Total liquidity mismatch");

    	// View pool reserves
    	(uint256 reserve0, uint256 reserve1) = pools.getPoolReserves(token0, token1);
    	assertEq(reserve0, 1000 ether, "Reserve0 mismatch");
    	assertEq(reserve1, 1000 ether, "Reserve1 mismatch");
    	}


	// A unit test that checks function failures (addLiquidity, removeLiquidity, swap, depositSwapWithdraw) when the deadline has expired.
	function testExpiredDeadline() public
        {
   		vm.startPrank(DEPLOYER);

        uint256 deadline = block.timestamp - 1; // Set deadline in the past

        // Add Liquidity
        vm.expectRevert("TX EXPIRED");
        pools.addLiquidity( tokens[0], tokens[1], 1000 ether, 1000 ether, 0, deadline );

        // Remove Liquidity
        vm.expectRevert("TX EXPIRED");
        pools.removeLiquidity( tokens[0], tokens[1], 1000 ether, 1000 ether, 0, deadline );

        // Swap
        IERC20[] memory tokensPath = new IERC20[](2);
        tokensPath[0] = tokens[0];
        tokensPath[1] = tokens[1];
        vm.expectRevert("TX EXPIRED");
        pools.swap(tokensPath, 1000 ether, 1 ether, deadline);

        // Deposit Swap Withdraw
        vm.expectRevert("TX EXPIRED");
        pools.depositSwapWithdraw(tokens[0], tokens[1], 1000 ether, 1 ether, deadline);
        }


	// A unit test that verifies correct return values from functions like PoolUtils.poolID, getTotalLiquidity, getPoolReserves, getUserLiquidity after successful operations.
	function testReturnValues() public
        {
   		vm.startPrank(DEPLOYER);

        IERC20 token0 = tokens[0];
        IERC20 token1 = tokens[1];

        bytes32 poolID;
        bool flipped;

        (poolID, flipped) = PoolUtils.poolID(IERC20(address(0x222)), IERC20(address(0x111)));
        assertTrue(flipped, "Expected PoolUtils.poolID to return flipped as true");

    	(poolID,) = PoolUtils.poolID(token0, token1);
        uint256 totalLiquidity = pools.totalLiquidity(poolID);
        assertEq(totalLiquidity, 1000 ether, "Expected totalLiquidity to return 1000 ether");

        uint256 reserve0;
        uint256 reserve1;
        (reserve0, reserve1) = pools.getPoolReserves(token0, token1);
        assertEq(reserve0, 1000 ether, "Expected reserve0 to return 1000 ether");
        assertEq(reserve1, 1000 ether, "Expected reserve1 to return 1000 ether");

        uint256 userLiquidity = pools.getUserLiquidity(address(DEPLOYER), token0, token1);
        assertEq(userLiquidity, 500 ether, "Expected getUserLiquidity to return 500 ether");

        pools.addLiquidity(token0, token1, 500 ether, 500 ether, 0, block.timestamp + 15 minutes);
        vm.warp(block.timestamp + 15 minutes);


        (reserve0, reserve1) = pools.getPoolReserves(token0, token1);
        assertEq(reserve0, 1500 ether, "Expected reserve0 to return 1500 ether");
        assertEq(reserve1, 1500 ether, "Expected reserve1 to return 1500 ether");

		// Tota liquidity was 1000 ether and 50% more was added - so the new total should be 1500 ether
        totalLiquidity = pools.totalLiquidity(poolID);
        assertEq(totalLiquidity, 1500 ether, "Expected totalLiquidity to return 1500 ether");

        userLiquidity = pools.getUserLiquidity(address(DEPLOYER), token0, token1);
        assertEq(userLiquidity, 1000 ether, "Expected getUserLiquidity to return 1000 ether");
        }


	// A unit test that ensures function failures when trying to operate (removeLiquidity, swap, depositSwapWithdraw) with pools that have no liquidity.
	function testFailNoLiquidityOperations() public {
   		vm.startPrank(DEPLOYER);

    	IERC20 tokenA = tokens[9]; // The 10th token in your array which has no liquidity in the pool
    	IERC20 tokenB = tokens[0]; // The first token in your array which has liquidity in the pool

    	// Expect revert on removeLiquidity operation with a pool that has no liquidity
    	vm.expectRevert("Insufficient balance to remove more liquidity than the current balance");
    	pools.removeLiquidity(tokenA, tokenB, 1000 ether, 0, 0, block.timestamp);

    	// Expect revert on swap operation with a pool that has no liquidity
    	vm.expectRevert("Insufficient deposited token balance of initial token");
    	pools.depositSwapWithdraw(tokenA, tokenB, 1000 ether, 0, block.timestamp);
    }


	// Chop off the last two digits of 18 decimal numbers and compare
	function _assertAlmostEqual( uint256 a, uint256 b ) public
		{
		assertEq( a / 100, b / 100 );
		}


	// A unit test that tests addLiquidity return values
	function testAddLiquidityReturnValues() public {
   		vm.startPrank(DEPLOYER);

       	IERC20 token0 = new TestERC20( 18 );
       	IERC20 token1 = new TestERC20( 18 );
       	poolsConfig.whitelistPool(token0, token1);

    	token0.transfer(alice, 1000 ether);
		token0.transfer(bob, 1000 ether);
    	token1.transfer(alice, 1000 ether);
		token1.transfer(bob, 1000 ether);
		vm.stopPrank();

		vm.startPrank(alice);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		vm.stopPrank();

		vm.startPrank(bob);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		vm.stopPrank();

		// Alice adds some liquidity
		uint256 userToken0 = token0.balanceOf( alice );
        uint256 userToken1 = token1.balanceOf( alice );

		vm.prank(alice);
		(uint256 added0, uint256 added1, uint256 addedLiquidity) = pools.addLiquidity( token0, token1, 200 ether, 100 ether, 0, block.timestamp );
		assertEq( Math.sqrt( 200 ether * 100 ether ), addedLiquidity );

		uint256 aliceAdded0 = userToken0 - token0.balanceOf( alice );
        uint256 aliceAdded1 = userToken1 - token1.balanceOf( alice );
        assertEq( aliceAdded0, added0 );
        assertEq( aliceAdded1, added1 );

		userToken0 = token0.balanceOf( bob );
        userToken1 = token1.balanceOf( bob );

		vm.prank(bob);
		(added0, added1, addedLiquidity) = pools.addLiquidity( token0, token1, 250 ether, 100 ether, 0, block.timestamp );

		uint256 bobAdded0 = userToken0 - token0.balanceOf( bob );
        uint256 bobAdded1 = userToken1 - token1.balanceOf( bob );
        assertEq( bobAdded0, added0 );
        assertEq( bobAdded1, added1 );

		uint256 bobLiquidity1 = pools.getUserLiquidity( bob, token0, token1 );
		assertEq( addedLiquidity, bobLiquidity1 );


		userToken0 = token0.balanceOf( bob );
        userToken1 = token1.balanceOf( bob );

		vm.prank(bob);
		(added0, added1, addedLiquidity) = pools.addLiquidity( token0, token1, 200 ether, 150 ether, 0, block.timestamp );

		bobAdded0 = userToken0 - token0.balanceOf( bob );
        bobAdded1 = userToken1 - token1.balanceOf( bob );
        assertEq( bobAdded0, added0 );
        assertEq( bobAdded1, added1 );

		uint256 bobLiquidity2 = pools.getUserLiquidity( bob, token0, token1 );
		assertEq( addedLiquidity, bobLiquidity2 - bobLiquidity1 );
		}


	// A unit test with interleaved liquidity adds, swaps, and liquidity removals from multiple users
	function testMultipleInteractions() public {
   		vm.startPrank(DEPLOYER);

       	IERC20 token0 = new TestERC20( 18 );
       	IERC20 token1 = new TestERC20( 18 );
       	poolsConfig.whitelistPool(token0, token1);

    	token0.transfer(alice, 1000 ether);
		token0.transfer(bob, 1000 ether);
		token0.transfer(charlie, 1000 ether);
    	token1.transfer(alice, 1000 ether);
		token1.transfer(bob, 1000 ether);
		token1.transfer(charlie, 1000 ether);
		vm.stopPrank();

		vm.startPrank(alice);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		vm.stopPrank();

		vm.startPrank(bob);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		vm.stopPrank();

		vm.startPrank(charlie);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		vm.stopPrank();

		// Alice adds some liquidity
		vm.prank(alice);
		pools.addLiquidity( token0, token1, 200 ether, 100 ether, 0, block.timestamp );

		// Bob depositSwapWithdraws 10 ether token0 for token1
		vm.prank(bob);
		uint256 amountOut = pools.depositSwapWithdraw(token0, token1, 10 ether, 1 ether, block.timestamp);
		_assertAlmostEqual( amountOut, 4761904761904761905 );

		(uint256 reserve0, uint256 reserve1) = pools.getPoolReserves(token0,token1);
		_assertAlmostEqual( reserve0, 210000000000000000000 );
		_assertAlmostEqual( reserve1, 95238095238095238095 );

		// Charlie deposits 20 ether token1
		vm.startPrank(charlie);
		pools.deposit(token1, 20 ether);

		// Charlie swaps 20 ether token1 for token0
		IERC20[] memory _tokens = new IERC20[](2);
		_tokens[0] = token1;
		_tokens[1] = token0;
		uint256 charlieToken0 = pools.swap(_tokens, 20 ether, 1 ether, block.timestamp);
		_assertAlmostEqual( charlieToken0, 36446280991735537191 );
		vm.stopPrank();

			{
			(uint256 aliceReserve0, uint256 aliceReserve1) = pools.getPoolReserves(token0,token1);
			_assertAlmostEqual( aliceReserve0, 173553719008264462809 );
			_assertAlmostEqual( aliceReserve1, 115238095238095238095 );
	//		console.log( "aliceReserve0: ", aliceReserve0 );
	//		console.log( "aliceReserve1: ", aliceReserve1 );


			// Bob adds an extra half of the current liquidity
			vm.prank(bob);
			pools.addLiquidity(token0, token1, 86776859504132231404, 57619047619047619047, 0, block.timestamp);

			(reserve0, reserve1) = pools.getPoolReserves(token0,token1);
			_assertAlmostEqual( reserve0, 260330578512396694213 );
			_assertAlmostEqual( reserve1, 172857142857142857142 );
	//		console.log( "reserve0: ", reserve0 );
	//		console.log( "reserve1: ", reserve1 );


			// Charlie adds an extra 25% of the current liquidity
			vm.prank(charlie);
			pools.addLiquidity(token0, token1, 65082644628099173553, 43214285714285714285, 0, block.timestamp);

			(reserve0, reserve1) = pools.getPoolReserves(token0,token1);
			_assertAlmostEqual( reserve0, 325413223140495867766 );
			_assertAlmostEqual( reserve1, 216071428571428571427 );
	//		console.log( "reserve0: ", reserve0 );
	//		console.log( "reserve1: ", reserve1 );


			// Alice removes her liquidity
			uint256 aliceLiquidity = pools.getUserLiquidity( alice, token0, token1 );
			_assertAlmostEqual( aliceLiquidity, 141421356237309504880 );
			(bytes32 poolID,) = PoolUtils.poolID(token0, token1);
			_assertAlmostEqual( pools.totalLiquidity(poolID), 212132034355964257319 + pools.getUserLiquidity( charlie, token0, token1 ) );
	//		console.log( "aliceLiquidity: ", aliceLiquidity );
	//		console.log( "totalLiquidity: ", pools.getTotalLiquidity(token0,token1) );

			vm.prank(alice);
			(uint256 reclaimed0, uint256 reclaimed1) = pools.removeLiquidity(token0, token1, 141421356237309504880, 0, 0, block.timestamp);

			// Alice should have reclaimed the liquidity that was there before bob and charlie added theirs
			_assertAlmostEqual( reclaimed0, aliceReserve0 );
			_assertAlmostEqual( reclaimed1, aliceReserve1 );
			}
//		console.log( "reclaimed0: ", reclaimed0 );
//		console.log( "reclaimed1: ", reclaimed1 );


		// Charlie swaps all his deposited token0 for token 1
		vm.prank(charlie);
		_tokens[0] = token0;
		_tokens[1] = token1;
		amountOut = pools.swap(_tokens, charlieToken0, 1 ether, block.timestamp);
		_assertAlmostEqual( amountOut, 19516129032258064517 );

		(reserve0, reserve1) = pools.getPoolReserves(token0,token1);
		_assertAlmostEqual( reserve0, 188305785123966942148 );
		_assertAlmostEqual( reserve1, 81317204301075268815 );


		// Bob swaps 10 ether token0 for token1
		vm.prank(bob);
		amountOut = pools.depositSwapWithdraw(token0, token1, 10 ether, 1 ether, block.timestamp);
		_assertAlmostEqual( amountOut, 4100596674486396136 );

		(reserve0, reserve1) = pools.getPoolReserves(token0,token1);
		_assertAlmostEqual( reserve0, 188305785123966942148 + 10 ether );
		_assertAlmostEqual( reserve1, 81317204301075268815 - 4100596674486396136 );
	    }


	// A unit test in which alice, bob and charlie interleave multiple add liquidity and remove liquidity calls.
	// No swaps are done, but at the end all liquidity is remove and the users should ensure that they have reclaimed what they originally added.
	function testMultiAddRemoveLiquidity() public {
   		vm.startPrank(DEPLOYER);

       	IERC20 token0 = new TestERC20( 18 );
       	IERC20 token1 = new TestERC20( 18 );
		poolsConfig.whitelistPool(token0, token1);

		// alice, bob and charlie initially have 1000 of each token
    	token0.transfer(alice, 1000 ether);
		token0.transfer(bob, 1000 ether);
		token0.transfer(charlie, 1000 ether);
    	token1.transfer(alice, 1000 ether);
		token1.transfer(bob, 1000 ether);
		token1.transfer(charlie, 1000 ether);
		vm.stopPrank();

		// Approvals for adding liquidity
		vm.startPrank(alice);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		vm.stopPrank();

		vm.startPrank(bob);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		vm.stopPrank();

		vm.startPrank(charlie);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		vm.stopPrank();

		// Multiple liquidity adds and removals
		vm.prank(alice);
		pools.addLiquidity( token0, token1, 200 ether, 100 ether, 0, block.timestamp );

		vm.prank(bob);
		pools.addLiquidity( token0, token1, 400 ether, 200 ether, 0, block.timestamp );

		vm.prank(charlie);
		pools.addLiquidity( token0, token1, 100 ether, 50 ether, 0, block.timestamp );

		uint256 aliceLiquidity = pools.getUserLiquidity( alice, token0, token1 );
		vm.prank(alice);
		pools.removeLiquidity( token0, token1, aliceLiquidity / 2, 0, 0, block.timestamp );

		vm.prank(bob);
		pools.addLiquidity( token0, token1, 600 ether, 300 ether, 0, block.timestamp );

		vm.prank(charlie);
		pools.addLiquidity( token0, token1, 100 ether, 50 ether, 0, block.timestamp );

		uint256 bobLiquidity = pools.getUserLiquidity( bob, token0, token1 );
		vm.prank(bob);
		pools.removeLiquidity( token0, token1, bobLiquidity, 0, 0, block.timestamp );

		vm.prank(alice);
		pools.addLiquidity( token0, token1, 100 ether, 100 ether, 0, block.timestamp );

		vm.prank(bob);
		pools.addLiquidity( token0, token1, 100 ether, 100 ether, 0, block.timestamp );

		vm.prank(charlie);
		pools.addLiquidity( token0, token1, 100 ether, 50 ether, 0, block.timestamp );

		// Remove all liquidity
		aliceLiquidity = pools.getUserLiquidity( alice, token0, token1 );
		vm.prank(alice);
		pools.removeLiquidity( token0, token1, aliceLiquidity, 0, 0, block.timestamp );

		bobLiquidity = pools.getUserLiquidity( bob, token0, token1 );
		vm.prank(bob);
		pools.removeLiquidity( token0, token1, bobLiquidity, 0, 0, block.timestamp );

		uint256 charlieLiquidity = pools.getUserLiquidity( charlie, token0, token1 );
		vm.prank(charlie);
		pools.removeLiquidity( token0, token1, charlieLiquidity, 0, 0, block.timestamp );

		// As there were no swaps the pulled liquidity should result in the original balances
		assertEq( token0.balanceOf(alice), 1000 ether );
		assertEq( token0.balanceOf(bob), 1000 ether );
		assertEq( token0.balanceOf(charlie), 1000 ether );

		assertEq( token1.balanceOf(alice), 1000 ether );
		assertEq( token1.balanceOf(bob), 1000 ether );
		assertEq( token1.balanceOf(charlie), 1000 ether );
	    }


	// Function to check that with multiple users and multiple swaps the total number of tokens on the exchange remains constant and correct addLiquidity values are returned
	function _checkMultipleSwaps( uint8 decimals0, uint8 decimals1, uint256 units0, uint256 units1 ) internal {

   		vm.startPrank(DEPLOYER);
       	IERC20 token0 = new TestERC20( decimals0 );
       	IERC20 token1 = new TestERC20( decimals1 );

		// alice, bob and charlie initially have 1000 of each token
    	token0.transfer(alice, 10000 * units0);
		token0.transfer(bob, 10000 * units0);
		token0.transfer(charlie, 10000 * units0);
    	token1.transfer(alice, 10000 * units1);
		token1.transfer(bob, 10000 * units1);
		token1.transfer(charlie, 10000 * units1);
		vm.stopPrank();

		// Approvals for adding liquidity
		vm.startPrank(alice);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		vm.stopPrank();

		vm.startPrank(bob);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		vm.stopPrank();

		vm.startPrank(charlie);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);
		vm.stopPrank();

		vm.prank(DEPLOYER);
		poolsConfig.whitelistPool(token0, token1);

		// Add the initial liquidity
		vm.startPrank(alice);
		(uint256 added0, uint256 added1,) = pools.addLiquidity( token0, token1, 1000 * units0, 500 * units1, 0, block.timestamp );
		assertEq(added0, 1000 * units0);
		assertEq(added1, 500 * units1);
		(added0, added1,) = pools.addLiquidity( token0, token1, 1000 * units0, 500 * units1, 0, block.timestamp );
		assertEq(added0, 1000 * units0);
		assertEq(added1, 500 * units1);
		vm.stopPrank();

		vm.prank(bob);
		(added0, added1,) = pools.addLiquidity( token0, token1, 1000 * units0, 500 * units1, 0, block.timestamp );
		assertEq(added0, 1000 * units0);
		assertEq(added1, 500 * units1);

		vm.prank(charlie);
		(added0, added1,) = pools.addLiquidity( token0, token1, 1000 * units0, 500 * units1, 0, block.timestamp );
		assertEq(added0, 1000 * units0);
		assertEq(added1, 500 * units1);

		vm.prank(alice);
		pools.deposit( token0, 500 * units0 );

		// Multiple swaps
		{
		IERC20[] memory tokens01 = new IERC20[](2);
		tokens01[0] = token0;
		tokens01[1] = token1;

		IERC20[] memory tokens10 = new IERC20[](2);
		tokens10[0] = token1;
		tokens10[1] = token0;

		vm.prank(alice);
		pools.swap( tokens01, 500 * units0, 0 ether, block.timestamp );

		vm.prank(bob);
		pools.depositSwapWithdraw(token1, token0, 500 * units1, 0 ether, block.timestamp );

		vm.prank(charlie);
		pools.depositSwapWithdraw(token1, token0, 500 * units1, 0 ether, block.timestamp );

		vm.prank(alice);
		pools.swap( tokens10, 100 * units1, 0 ether, block.timestamp );

		vm.prank(bob);
		pools.depositSwapWithdraw(token0, token1, 100 * units0, 0 * units1, block.timestamp );

		vm.prank(charlie);
		pools.depositSwapWithdraw(token0, token1, 100 * units0, 0 * units1, block.timestamp );

		vm.prank(alice);
		pools.swap( tokens01, 10 * units0, 0 * units1, block.timestamp );

		vm.prank(bob);
		pools.depositSwapWithdraw(token1, token0, 10 * units1, 0 * units0, block.timestamp );

		vm.prank(charlie);
		pools.depositSwapWithdraw(token1, token0, 10 * units1, 0 * units0, block.timestamp );
		}

		(uint256 reserve0, uint256 reserve1) = pools.getPoolReserves(token0, token1);

		// After all of the swaps, the amount of each token should be the starting liquidity
		assertEq( reserve0 + pools.getUserDeposit( alice, token0 ) + token0.balanceOf(alice) + token0.balanceOf(bob) + token0.balanceOf(charlie), 30000 * units0 );
		assertEq( reserve1 + pools.getUserDeposit( alice, token1 ) + token1.balanceOf(alice) + token1.balanceOf(bob) + token1.balanceOf(charlie), 30000 * units1 );
	    }


	// Unit test to check that with multiple users and multiple swaps the total number of tokens on the exchange remains constant.
	// Check various decimals to make sure every works as expected
	function testMultipleSwaps() public
		{
		_checkMultipleSwaps( 18, 18, 10**18, 10**18 );
		_checkMultipleSwaps( 6, 18, 10**6, 10**18 );
		_checkMultipleSwaps( 18, 6, 10**18, 10**6 );
		_checkMultipleSwaps( 6, 12, 10**6, 10**12 );
		_checkMultipleSwaps( 12, 6, 10**12, 10**6 );
		}


	function _checkReserves( uint256 a, uint256 b, uint256 c, uint256 d ) public
		{
		vm.startPrank(DEPLOYER);

        // Define the array of tokens to be used in the swap operation
        IERC20[] memory chain = new IERC20[](3);
        chain[0] = new TestERC20(18);
        chain[1] =new TestERC20(18);
        chain[2] = new TestERC20(18);

		chain[0].approve(address(pools),type(uint256).max);
		chain[1].approve(address(pools),type(uint256).max);
		chain[2].approve(address(pools),type(uint256).max);

		poolsConfig.whitelistPool(chain[0], chain[1]);
		poolsConfig.whitelistPool(chain[1], chain[2]);

		pools.addLiquidity( chain[0], chain[1], a, b, 0, block.timestamp );
		pools.addLiquidity( chain[1], chain[2], c, d, 0, block.timestamp );

		(uint256 reserves0, uint256 reserves1) = pools.getPoolReserves( chain[0], chain[1] );
		(uint256 reserves1b, uint256 reserves2) = pools.getPoolReserves( chain[1], chain[2] );

		assertEq( reserves0, a, "incorrect checkReserves a" );
		assertEq( reserves1, b, "incorrect checkReserves b" );
		assertEq( reserves1b, c, "incorrect checkReserves c" );
		assertEq( reserves2, d, "incorrect checkReserves d" );

		vm.stopPrank();
		}


	function testCheckReserves() public
		{
		_checkReserves( 1000 ether, 100 ether, 200 ether, 2000 ether );
		_checkReserves( 1000 ether, 100 ether, 2000 ether, 200 ether );
		_checkReserves( 100 ether, 1000 ether, 200 ether, 2000 ether );
		_checkReserves( 100 ether, 1000 ether, 2000 ether, 200 ether );
		}


	// A unit test that verifies that quote amount out is returning accurate results
	function _testQuoteAmountOut() public
    {
   		vm.startPrank(DEPLOYER);

        // Define the array of tokens to be used in the swap operation
        IERC20[] memory chain = new IERC20[](3);
        chain[0] = new TestERC20(18);
        chain[1] =new TestERC20(18);
        chain[2] = new TestERC20(18);

//        console.log( "chain[0]: ", address(chain[0]) );
//        console.log( "chain[1]: ", address(chain[1]) );
//        console.log( "chain[2]: ", address(chain[2]) );
//
		chain[0].approve(address(pools),type(uint256).max);
		chain[1].approve(address(pools),type(uint256).max);
		chain[2].approve(address(pools),type(uint256).max);

		poolsConfig.whitelistPool(chain[0], chain[1]);
		poolsConfig.whitelistPool(chain[1], chain[2]);

		pools.addLiquidity( chain[0], chain[1], 1000 ether, 500 ether, 0, block.timestamp );
		pools.addLiquidity( chain[1], chain[2], 200 ether, 2000 ether, 0, block.timestamp );

		uint256 amountIn = 100 ether;
		pools.deposit(chain[0], amountIn );

		uint256 estimateOut = pools.quoteAmountOut( chain, amountIn );
        uint256 amountOut = pools.swap(chain, amountIn, 0 ether, block.timestamp);

		assertEq( estimateOut, amountOut, "quoteAmountOut did not return an accurate result" );
		vm.stopPrank();
		}


	// A unit test that verifies that quote amount in is returning accurate results
	function _testQuoteAmountIn() public
    {
   		vm.startPrank(DEPLOYER);

        // Define the array of tokens to be used in the swap operation
        IERC20[] memory chain = new IERC20[](3);
        chain[0] = new TestERC20(18);
        chain[1] =new TestERC20(18);
        chain[2] = new TestERC20(18);

		chain[0].approve(address(pools),type(uint256).max);
		chain[1].approve(address(pools),type(uint256).max);
		chain[2].approve(address(pools),type(uint256).max);

		poolsConfig.whitelistPool(chain[0], chain[1]);
		poolsConfig.whitelistPool(chain[1], chain[2]);

		pools.addLiquidity( chain[0], chain[1], 1000 ether, 500 ether, 0, block.timestamp );
		pools.addLiquidity( chain[1], chain[2], 200 ether, 2000 ether, 0, block.timestamp );

		uint256 targetAmountOut = 100 ether;
		uint256 amountIn = pools.quoteAmountIn( chain, targetAmountOut );

//		console.log( "amountIn: ", amountIn );

		pools.deposit(chain[0], amountIn );

		// Get the actual amountOut for the given amountIn
        uint256 amountOut = pools.swap(chain, amountIn, 0 ether, block.timestamp);

		// Remove the last two digits for integer division inaccuracy
		assertEq( targetAmountOut / 100, amountOut / 100, "quoteAmountIn did not return an accurate result" );
		vm.stopPrank();
		}

	// A unit test that checks the quote amount out for different token orderings
	function testQuoteAmountOut() public
		{
		// Loops to give the three token chains chances to have different ordering to check flipped functionality
		for( uint256 i = 0; i < 10; i++ )
			_testQuoteAmountOut();
		}


	// A unit test that checks the quote amount in for different token orderings
	function testQuoteAmountIn() public
		{
		// Loops to give the three token chains chances to have different ordering to check flipped functionality
		for( uint256 i = 0; i < 10; i++ )
			_testQuoteAmountIn();
		}


	// A unit test that checks the quote amounts with no reserves
	function testQuoteAmountsWithNoReserves() public
		{
        // Define the array of tokens to be used in the swap operation
        IERC20[] memory chain = new IERC20[](3);
        chain[0] = new TestERC20(18);
        chain[1] =new TestERC20(18);
        chain[2] = new TestERC20(18);

		uint256 amountIn = pools.quoteAmountIn( chain, 100 ether );
		assertEq(amountIn, 0);
		uint256 amountOut = pools.quoteAmountOut( chain, 100 ether );
		assertEq(amountOut, 0);
		}


	function _checkNumbersClose( uint256 x, uint256 y, uint8 decimals ) public pure returns (bool)
		{
		if ( x > y )
			{
			uint256 decimalReduction = uint256(PoolMath._reducePrecision( x - y, decimals + 4) );
			return decimalReduction == 0;
			}

		if ( x < y )
			{
			uint256 decimalReduction = uint256(PoolMath._reducePrecision( y -x, decimals + 4) );
			return decimalReduction == 0;
			}

		return true;
		}


	function _checkZapping( uint8 decimals0, uint8 decimals1, uint256 initialLiquidity0, uint256 initialLiquidity1, uint256 zapAmount0, uint256 zapAmount1 ) internal
		{
		vm.startPrank(DEPLOYER);

        IERC20 token0 = new TestERC20(decimals0);
        IERC20 token1 = new TestERC20(decimals1);

		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);

		poolsConfig.whitelistPool(token0, token1);
		pools.addLiquidity( token0, token1, initialLiquidity0 * 10 ** decimals0, initialLiquidity1 * 10 ** decimals1, 0, block.timestamp );

		token0.transfer(alice,zapAmount0 * 10 ** decimals0);
		token1.transfer(alice,zapAmount1 * 10 ** decimals1);

//		console.log( "token0: ", token0.balanceOf(alice ) / 10**18);
//		console.log( "token1: ", token1.balanceOf(alice ) / 10**18);

		vm.stopPrank();

		vm.startPrank(alice);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);

		uint256 reclaimedA;
		uint256 reclaimedB;

		// Avoid stack too deep
			{
			(,, uint256 addedLiquidity) = pools.dualZapInLiquidity( token0, token1, zapAmount0 * 10 ** decimals0, zapAmount1 * 10 ** decimals1, 0, block.timestamp, false );

//			console.log( "token0: ", token0.balanceOf(alice ));
//			console.log( "token1: ", token1.balanceOf(alice ));

			// Expect that we would have used all our tokens for zapping
			assertTrue( _checkNumbersClose( token0.balanceOf(alice), 0, decimals0), "Alice should have zero token0" );
			assertTrue( _checkNumbersClose( token1.balanceOf(alice), 0, decimals1), "Alice should have zero token1" );

			// Remove liquidity
			(reclaimedA, reclaimedB) = pools.removeLiquidity(token0, token1, addedLiquidity, 0, 0, block.timestamp);
			}


		// Swap back and see if things are where we started
		if ( reclaimedA > zapAmount0 * 10**decimals0 )
			pools.depositSwapWithdraw(token0, token1, reclaimedA - zapAmount0 * 10**decimals0, 0, block.timestamp);

		if ( reclaimedB > zapAmount1 * 10**decimals1 )
			pools.depositSwapWithdraw(token1, token0, reclaimedB - zapAmount1 * 10**decimals1, 0, block.timestamp);

		(uint256 reserve0, uint256 reserve1) = pools.getPoolReserves(token0, token1);

		assertTrue( _checkNumbersClose( reserve0, initialLiquidity0 * 10**decimals0, decimals0), "reconstructed initialLiquidity0 incorrect" );
		assertTrue( _checkNumbersClose( reserve1, initialLiquidity1 * 10**decimals1, decimals1), "reconstructed initialLiquidity1 incorrect" );

		assertTrue( _checkNumbersClose( token0.balanceOf(alice), zapAmount0 * 10**decimals0, decimals0), "reconstructed zapAmount0 incorrect" );
		assertTrue( _checkNumbersClose( token1.balanceOf(alice), zapAmount1 * 10**decimals1, decimals1), "reconstructed zapAmount1 incorrect" );


//		console.log( "---------------------------------" );
//		console.log( "zapAmount0: ", zapAmount0 * 10**decimals0 );
//		console.log( "zapAmount1: ", zapAmount1 * 10**decimals1 );
//
//		console.log( "reclaimedA: ", reclaimedA );
//		console.log( "reclaimedB: ", reclaimedB );
//
//		console.log( "initialLiquidity0: ", initialLiquidity0 * 10**decimals0 );
//		console.log( "initialLiquidity1: ", initialLiquidity1 * 10**decimals1 );
//
//		console.log( "reserve0: ", reserve0 );
//		console.log( "reserve1: ", reserve1 );
//
//		console.log( "token0: ", token0.balanceOf(alice) );
//		console.log( "token1: ", token1.balanceOf(alice) );

		vm.stopPrank();
		}

	// A unit test that checks the zapping functionality
	function testZapping() public
		{
		_checkZapping( 18, 18, 800000000000, 500000000000, 100000000000, 100000000000 );
		_checkZapping( 6, 18, 800000000000, 500000000000, 100000000000, 100000000000 );
		_checkZapping( 18, 6, 800000000000, 500000000000, 100000000000, 100000000000 );
		_checkZapping( 18, 6, 800000000000, 500000000000, 100000, 100000000000 );
		_checkZapping( 18, 18, 800000000000, 500000000000, 100000, 100000 );
		_checkZapping( 18, 18, 8000, 50, 100000, 0 );
		_checkZapping( 18, 6, 8000, 50, 1000, 0 );
		_checkZapping( 6, 18, 8000, 50, 0, 1000 );
		_checkZapping( 18, 18, 1000000, 1000000, 1000, 0 );
		_checkZapping( 18, 18, 1000000, 1000000, 0, 1000 );
		_checkZapping( 18, 18, 10000000, 10000000, 2000, 1000 );
		}


	function _checkZappingDust( uint8 decimals0, uint8 decimals1, uint256 initialLiquidity0, uint256 initialLiquidity1, uint256 zapAmount0, uint256 zapAmount1 ) internal
		{
		vm.startPrank(DEPLOYER);

        IERC20 token0 = new TestERC20(decimals0);
        IERC20 token1 = new TestERC20(decimals1);

		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);

		poolsConfig.whitelistPool(token0, token1);
		pools.addLiquidity( token0, token1, initialLiquidity0, initialLiquidity1, 0, block.timestamp );

		token0.transfer(alice,zapAmount0);
		token1.transfer(alice,zapAmount1);

//		console.log( "token0: ", token0.balanceOf(alice ));
//		console.log( "token1: ", token1.balanceOf(alice ));

		vm.stopPrank();

		vm.startPrank(alice);
		token0.approve(address(pools),type(uint256).max);
		token1.approve(address(pools),type(uint256).max);

		uint256 reclaimedA;
		uint256 reclaimedB;

		// Avoid stack too deep
			{
			(,, uint256 addedLiquidity) = pools.dualZapInLiquidity( token0, token1, zapAmount0, zapAmount1, 0, block.timestamp, false );

//			console.log( "token0: ", token0.balanceOf(alice ));
//			console.log( "token1: ", token1.balanceOf(alice ));

			// Expect that we would have used all our tokens for zapping
			assertTrue( _checkNumbersClose( token0.balanceOf(alice), 0, decimals0), "Alice should have zero token0" );
			assertTrue( _checkNumbersClose( token1.balanceOf(alice), 0, decimals1), "Alice should have zero token1" );

			// Remove liquidity
			(reclaimedA, reclaimedB) = pools.removeLiquidity(token0, token1, addedLiquidity, 0, 0, block.timestamp);
			}


		// Swap back and see if things are where we started
		if ( reclaimedA > zapAmount0 )
			pools.depositSwapWithdraw(token0, token1, reclaimedA - zapAmount0, 0, block.timestamp);

		if ( reclaimedB > zapAmount1 )
			pools.depositSwapWithdraw(token1, token0, reclaimedB - zapAmount1, 0, block.timestamp);

		(uint256 reserve0, uint256 reserve1) = pools.getPoolReserves(token0, token1);

		assertTrue( _checkNumbersClose( reserve0, initialLiquidity0, decimals0), "reconstructed initialLiquidity0 incorrect" );
		assertTrue( _checkNumbersClose( reserve1, initialLiquidity1, decimals1), "reconstructed initialLiquidity1 incorrect" );

		assertTrue( _checkNumbersClose( token0.balanceOf(alice), zapAmount0, decimals0), "reconstructed zapAmount0 incorrect" );
		assertTrue( _checkNumbersClose( token1.balanceOf(alice), zapAmount1, decimals1), "reconstructed zapAmount1 incorrect" );

//		console.log( "---------------------------------" );
//		console.log( "zapAmount0: ", zapAmount0 );
//		console.log( "zapAmount1: ", zapAmount1 );
//
//		console.log( "reclaimedA: ", reclaimedA );
//		console.log( "reclaimedB: ", reclaimedB );
//
//		console.log( "initialLiquidity0: ", initialLiquidity0 );
//		console.log( "initialLiquidity1: ", initialLiquidity1 );
//
//		console.log( "reserve0: ", reserve0 );
//		console.log( "reserve1: ", reserve1 );
//
//		console.log( "token0: ", token0.balanceOf(alice) );
//		console.log( "token1: ", token1.balanceOf(alice) );

		vm.stopPrank();
		}

	// A unit test that checks the zapping functionality with dust amounts
	function testZappingDust() public
		{
		_checkZappingDust( 18, 18, 8000, 2000, 101, 101 );

		// This should check the minimum quantity to zap of .000101
		_checkZappingDust( 18, 18, 8000 * 10**6, 2000 * 10**18, 101 * 10 ** 6, 101 * 10 ** 12 );

		// This should check the minimum quantity to zap of .000101
		_checkZappingDust( 18, 18, 800000 ether, 200000 ether, 101 * 10 ** 6, 101 * 10 ** 12 );
		}


	// A unit test that checks the addition of dust liquidity
	function testAddingDustLiquidity() public
		{
		pools.addLiquidity( tokens[0], tokens[1], 101, 101, 0, block.timestamp );

		vm.expectRevert( "The amount of tokenA to add is too small" );
		pools.addLiquidity( tokens[0], tokens[1], 99, 101, 0, block.timestamp );
		}
    }
