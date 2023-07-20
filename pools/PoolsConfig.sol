// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.12;

import "../openzeppelin/access/Ownable.sol";
import "../openzeppelin/utils/structs/EnumerableSet.sol";
import "./interfaces/IPoolsConfig.sol";
import "./PoolUtils.sol";
import "../arbitrage/interfaces/IArbitrageSearch.sol";


// Contract owned by the DAO and only modifiable by the DAO
contract PoolsConfig is IPoolsConfig, Ownable
    {
    event eWhitelistPool(IERC20 indexed tokenA, IERC20 indexed tokenB, bytes32 indexed poolID);
    event eUnwhitelistPool(IERC20 indexed tokenA, IERC20 indexed tokenB, bytes32 indexed poolID);

	struct TokenPair
		{
		// Note that these will be ordered as specified in whitelistPool() - rather than ordered such that address(tokenA) < address(tokenB) as with the reserves in Pools.sol
		IERC20 tokenA;
		IERC20 tokenB;
		}

    using EnumerableSet for EnumerableSet.Bytes32Set;


	// For finding profitable arbitrage paths
	IArbitrageSearch public arbitrageSearch;

	// Keeps track of what pools have been whitelisted
	EnumerableSet.Bytes32Set private _whitelist;

	// A mapping from poolIDs to the underlying TokenPair
	mapping(bytes32=>TokenPair) public underlyingPoolTokens;


	// The maximum number of pools that can be whitelisted at any one time.
	// If the maximum number of pools is reached, some tokens will need to be delisted before new ones can be whitelisted
	// Range: 20 to 100 with an adjustment of 10
	uint256 public maximumWhitelistedPools = 50;

	// The percent of arbitrage profit that is sent to the DAO when arbitrage() is called with the exchange by the ArbitrageSearch contract
	// Range: 20% to 50% with an adjustment of 5%
	uint256 public daoPercentShareInternalArbitrage = 30;

	// The percent of arbitrage profit that is sent to the DAO when arbitrage() is called from outside of the exchange
	// Range: 50% to 95% with an adjustment of 5%
	uint256 public daoPercentShareExternalArbitrage = 80;

	// A special pool that represents staked SALT that is not associated with any particular pool.
    bytes32 public constant STAKED_SALT = bytes32(0);



	// Whitelist a given pair of tokens
	function whitelistPool( IERC20 tokenA, IERC20 tokenB ) public onlyOwner
		{
		require( _whitelist.length() < maximumWhitelistedPools, "Maximum number of whitelisted pools already reached" );
		require(tokenA != tokenB, "tokenA and tokenB cannot be the same token");

		(bytes32 poolID, ) = PoolUtils.poolID(tokenA, tokenB);

		underlyingPoolTokens[poolID] = TokenPair(tokenA, tokenB);

		if ( _whitelist.add(poolID) )
			emit eWhitelistPool(tokenA, tokenB, poolID);
		}


	function unwhitelistPool( IERC20 tokenA, IERC20 tokenB ) public onlyOwner
		{
		(bytes32 poolID, ) = PoolUtils.poolID(tokenA,tokenB);

		if ( _whitelist.remove(poolID) )
			emit eUnwhitelistPool(tokenA, tokenB, poolID);
		}


	function setArbitrageSearch( IArbitrageSearch _arbitrageSearch ) public onlyOwner
		{
		require( address(_arbitrageSearch) != address(0), "_arbitrageSearch cannot be address(0)" );

		arbitrageSearch = _arbitrageSearch;
		}


	function changeMaximumWhitelistedPools(bool increase) public onlyOwner
        {
        if (increase)
            {
            if (maximumWhitelistedPools < 100)
                maximumWhitelistedPools += 10;
            }
        else
            {
            if (maximumWhitelistedPools > 20)
                maximumWhitelistedPools -= 10;
            }
        }


	function changeDaoPercentShareInternalArbitrage(bool increase) public onlyOwner
        {
        if (increase)
            {
            if (daoPercentShareInternalArbitrage < 50)
                daoPercentShareInternalArbitrage += 5;
            }
        else
            {
            if (daoPercentShareInternalArbitrage > 20)
                daoPercentShareInternalArbitrage -= 5;
            }
        }


	function changeDaoPercentShareExternalArbitrage(bool increase) public onlyOwner
        {
        if (increase)
            {
            if (daoPercentShareExternalArbitrage < 95)
                daoPercentShareExternalArbitrage += 5;
            }
        else
            {
            if (daoPercentShareExternalArbitrage > 50)
                daoPercentShareExternalArbitrage -= 5;
            }
        }


	// ===== VIEWS =====

	function numberOfWhitelistedPools() public view returns (uint256)
		{
		return _whitelist.length();
		}


	// Return the poolID at the given index
	function whitelistedPoolAtIndex( uint256 index ) public view returns (bytes32)
		{
		return _whitelist.at( index );
		}


	function isWhitelisted( bytes32 poolID ) public view returns (bool)
		{
		if ( poolID == STAKED_SALT )
			return true;

		return _whitelist.contains( poolID );
		}


	// Return an array of the currently whitelisted poolIDs
	function whitelistedPools() public view returns (bytes32[] memory)
		{
		bytes32[] memory whitelistAddresses = _whitelist.values();

		bytes32[] memory pools = new bytes32[]( whitelistAddresses.length );

		for( uint256 i = 0; i < pools.length; i++ )
			pools[i] = whitelistAddresses[i];

		return pools;
		}


	function underlyingTokenPair( bytes32 poolID ) public view returns (IERC20 tokenA, IERC20 tokenB)
		{
		TokenPair memory pair = underlyingPoolTokens[poolID];
		require(address(pair.tokenA) != address(0) && address(pair.tokenB) != address(0), "This poolID does not exist");

		return (pair.tokenA, pair.tokenB);
		}


	// Returns true if the token has been whitelisted (meaning it has been pooled with either WBTC and WETH)
	function tokenHasBeenWhitelisted( IERC20 token, IERC20 wbtc, IERC20 weth ) public view returns (bool)
		{
		// See if the token has been whitelisted with either WBTC or WETH, as all whitelisted tokens are pooled with both WBTC and WETH
		(bytes32 poolID1,) = PoolUtils.poolID( token, wbtc );
		(bytes32 poolID2,) = PoolUtils.poolID( token, weth );

		if ( isWhitelisted(poolID1) || isWhitelisted(poolID2) )
			return true;

		return false;
		}
	}