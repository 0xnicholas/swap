// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import from "./abstract/PoolDeployer.sol";
import from "Pool.sol";
import from "../../interfaces/IPoolFactory.sol";
import from "../../interfaces/IDeployer.sol";

/// @notice Contract for deploying Exchange Constant Product Pool with configurations.
contract PoolFactory is IPoolFactory, PoolDeployer {
    bytes32 public constant bytecodeHash = keccak256(type(Pool).creationCode);

    bytes private cachedDeployData;

    struct PoolInfo {
        uint8 tokenA;
        uint8 tokenB;
        uint112 reserve0;
        uint112 reserve1;
        uint16 swapFeeAndTwapSupport;
    }

    constructor(address _masterDeployer) PoolDeployer(_masterDeployer) {}

    function deployPool(bytes memory _deployData) external returns (address pool) {
        (address tokenA, address tokenB, uint256 swapFee, bool twapSupport) = abi.decode(_deployData, (address, address, uint256, bool));

        if (tokenA > tokenB) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }

        // Strips any extra data.
        _deployData = abi.encode(tokenA, tokenB, swapFee, twapSupport);

        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;

        bytes32 salt = keccak256(_deployData);

        cachedDeployData = _deployData;

        pool = address(new Pool{salt: salt}());

        cachedDeployData = "";

        _registerPool(pool, tokens, salt);
    }

    // This called in the Pool constructor.
    function getDeployData() external view override returns (bytes memory, IDeployer) {
        return (cachedDeployData, IDeployer(masterDeployer));
    }

    function calculatePoolAddress(
        address token0,
        address token1,
        uint256 swapFee,
        bool twapSupport
    ) external view returns (address) {
        bytes32 salt = keccak256(abi.encode(token0, token1, swapFee, twapSupport));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash));
        return address(uint160(uint256(hash)));
    }

    // @dev tokens MUST be sorted i < j => token[i] < token[j]
    // @dev tokens.length < 256
    function getPoolsForTokens(address poolFactory, address[] calldata tokens)
        external
        view
        returns (PoolInfo[] memory poolInfos, uint256 length)
    {
        PoolFactory factory = PoolFactory(poolFactory);
        uint8 tokenNumber = uint8(tokens.length);
        uint256[] memory poolLength = new uint256[]((tokenNumber * (tokenNumber + 1)) / 2);
        uint256 pairNumber = 0;
        for (uint8 i = 0; i < tokenNumber; i++) {
            for (uint8 j = i + 1; j < tokenNumber; j++) {
                uint256 count = factory.poolsCount(tokens[i], tokens[j]);
                poolLength[pairNumber++] = count;
                length += count;
            }
        }
        poolInfos = new PoolInfo[](length);
        pairNumber = 0;
        uint256 poolNumber = 0;
        for (uint8 i = 0; i < tokenNumber; i++) {
            for (uint8 j = i + 1; j < tokenNumber; j++) {
                address[] memory pools = factory.getPools(tokens[i], tokens[j], 0, poolLength[pairNumber++]);
                for (uint256 k = 0; k < pools.length; k++) {
                    PoolInfo memory poolInfo = poolInfos[poolNumber++];
                    poolInfo.tokenA = i;
                    poolInfo.tokenB = j;
                    Pool pool = ConstantProductPool(pools[k]);
                    (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = pool.getReserves();
                    poolInfo.reserve0 = reserve0;
                    poolInfo.reserve1 = reserve1;
                    poolInfo.swapFeeAndTwapSupport = uint16(pool.swapFee());
                    if (blockTimestampLast != 0) poolInfo.swapFeeAndTwapSupport += 1 << 15;
                }
            }
        }
    }
}