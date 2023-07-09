// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.12;

import "../openzeppelin/access/Ownable.sol";
import "../openzeppelin/utils/structs/EnumerableSet.sol";
import "./interfaces/IPoolsConfig.sol";
import "./PoolUtils.sol";


// Contract owned by the DAO and only modifiable by the DAO
contract PoolsConfig is IPoolsConfig, Ownable
    {
    event eWhitelistPool(IERC20 indexed token0, IERC20 indexed token1, bytes32 indexed poolID);
    event eUnwhitelistPool(IERC20 indexed token0, IERC20 indexed token1, bytes32 indexed poolID);
	event eMaximumWhitelistedPoolsChanged(uint256 newValue);

	struct TokenPair
		{
		// Note that these will be ordered as specified in whitelistPool() - rather than ordered such that address(token0) < address(token1) as standard in Pools.sol
		IERC20 token0;
		IERC20 token1;
		}

    using EnumerableSet for EnumerableSet.Bytes32Set;


	// Keeps track of what pools have been whitelisted
	EnumerableSet.Bytes32Set private _whitelist;

	// A mapping from poolIDs to the underlying TokenPair
	mapping(bytes32=>TokenPair) public underlyingPoolTokens;

	// The maximum number of pools that can be whitelisted at any one time.
	// If the maximum number of pools is reached, some tokens will need to be delisted before new ones can be whitelisted
	// Range: 20 to 100 with an adjustment of 10
	uint256 public maximumWhitelistedPools = 50;

	// A special pool that represents staked SALT that is not associated with any particular pool.
    bytes32 public constant STAKED_SALT = bytes32(0);



	// Whitelist a given pair of tokens
	function whitelistPool( IERC20 token0, IERC20 token1 ) public onlyOwner
		{
		require( _whitelist.length() < maximumWhitelistedPools, "Maximum number of whitelisted pools already reached" );
		require(token0 != token1, "token0 and token1 cannot be the same token");

		(bytes32 poolID, ) = PoolUtils.poolID(token0, token1);

		underlyingPoolTokens[poolID] = TokenPair(token0, token1);

		if ( _whitelist.add(poolID) )
			emit eWhitelistPool(token0, token1, poolID);
		}


	function unwhitelistPool( IERC20 token0, IERC20 token1 ) public onlyOwner
		{
		(bytes32 poolID, ) = PoolUtils.poolID(token0,token1);

		if ( _whitelist.remove(poolID) )
			emit eUnwhitelistPool(token0, token1, poolID);
		}


	function changeMaximumWhitelistedPools(bool increase) public onlyOwner
        {
        if (increase)
            {
            if (maximumWhitelistedPools < 100)
                maximumWhitelistedPools = maximumWhitelistedPools + 10;
            }
        else
            {
            if (maximumWhitelistedPools > 20)
                maximumWhitelistedPools = maximumWhitelistedPools - 10;
            }

        emit eMaximumWhitelistedPoolsChanged(maximumWhitelistedPools);
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


	function underlyingTokenPair( bytes32 poolID ) public view returns (IERC20 token0, IERC20 token1)
		{
		TokenPair memory pair = underlyingPoolTokens[poolID];
		require(address(pair.token0) != address(0) && address(pair.token1) != address(0), "This poolID does not exist");

		return (pair.token0, pair.token1);
		}
    }