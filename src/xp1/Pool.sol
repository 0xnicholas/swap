// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "../../lib/solmate/tokens/ERC20.sol";
import {ReentrancyGuard} from "../../lib/solmate/utils/ReentrancyGuard.sol";
import {FixedPointMathLib as Math} from "../../lib/solmate/utils/FixedPointMathLib.sol";

import {IPool} from "./interfaces/IPool.sol";
import {IPoolFactory} from "./interfaces/IPoolFactory.sol";
import {IDeployer} from "./interfaces/IDeployer.sol";

error ZeroAddress();
error IdenticalAddress();
error InvalidSwapFee();
error InvalidAmounts();
error InsufficientLiquidityMinted();
error InvalidOutputToken();
error InvalidInputToken();
error PoolUninitialized();
error InsufficientAmountIn();
error Overflow();

/// @notice exchange pool template with constant product formula for swapping between an ERC-20 token pair.
contract Pool is IPool, ERC20, ReentrancyGuard {

    event Mint(address indexed sender, uint256 amount0, uint256 amount1, address indexed recipient);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed recipient);
    event Sync(uint256 reserve0, uint256 reserve1);

    uint256 internal constant MINIMUM_LIQUIDITY = 1000;

    uint8 internal constant PRECISION = 112;
    uint256 internal constant MAX_FEE = 10000; // 100%
    uint256 public immutable swapFee;
    uint256 internal immutable MAX_FEE_MINUS_SWAP_FEE;

    // address public immutable factory;
    // IVault public immutable vault;
    IDeployer public immutable deployer;

    address public immutable token0;
    address public immutable token1;
    
    uint256 public poolFee;
    address public poolFeeTo;
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast;

    uint112 internal reserve0;
    uint112 internal reserve1;
    uint32 internal blockTimestampLast;

    bytes32 public constant override poolIdentifier = "Swap:ConstantProduct";

    constructor() ERC20("Swap Constant Product LP Token", "SCPLP", 18) {
        //factory = msg.sender
        (bytes memory _deployerData, IDeployer _deployer) = IPoolFactory(msg.sender).getDeployData();

        (address _token0, address _token1, uint256 _swapFee, bool _twapSupport) = abi.decode(
            _deployerData, (address, address, uint256, bool)
        );

        if (_token0 == address(0)) revert ZeroAddress();
        if (_token0 == _token1) revert IdenticalAddress();
        if (_swapFee > MAX_FEE) revert InvalidSwapFee();

        token0 = _token0;
        token1 = _token1;
        swapFee = _swapFee;

        unchecked {
            MAX_FEE_MINUS_SWAP_FEE = MAX_FEE - _swapFee;
        }

        poolFee = _deployer.poolFee();
        poolFeeTo = _deployer.poolFeeTo();
        
        // IVault ERC-4626 ...

        deployer = _deployer;
        
        //twap support
        if (_twapSupport) blockTimestampLast = uint32(block.timestamp);
    }

    /// @dev mints LP tokens
    function mint(bytes calldata data) public override nonReentrant returns (uint256 liquidity) {
        // to
        address recipient = abi.decode(data, (address));
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves();
        (uint256 balance0, uint256 balance1) = _balance();

        uint256 computed = Math.sqrt(balance0 * balance1);
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        (uint256 fee0, uint256 fee1) = _nonOptimalMintFee(amount0, amount1, _reserve0, _reserve1);
        _reserve0 += uint112(fee0);
        _reserve1 += uint112(fee1);

        (uint256 _totalSupply, uint256 k) = _mintFee(_reserve0, _reserve1);

        if (_totalSupply == 0) {
            if (amount0 == 0 || amount1 == 0) revert InvalidAmounts();
            liquidity = computed - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            uint256 kIncrease;
            unchecked {
                kIncrease = computed - k;
            }
            liquidity = (kIncrease * _totalSupply) / k;
        }
        if (liquidity == 0) revert InsufficientLiquidityMinted();
        _mint(recipient, liquidity);
        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        kLast = computed;
        emit Mint(msg.sender, amount0, amount1, recipient);
    }

    /// @dev Burns LP tokens sent to this contract.
    function burn(bytes calldata data) public override nonReentrant returns (IPool.TokenAmount[] memory withdrawnAmounts) {
        address recipient = abi.decode(data, (address));
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves();
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 liquidity = balanceOf[address(this)];

        (uint256 _totalSupply, ) = _mintFee(_reserve0, _reserve1);

        uint256 amount0 = (liquidity * balance0) / _totalSupply;
        uint256 amount1 = (liquidity * balance1) / _totalSupply;

        _burn(address(this), liquidity);
        _transfer(token0, amount0, recipient);
        _transfer(token1, amount1, recipient);

        unchecked {
            balance0 -= amount0;
            balance1 -= amount1;
        }

        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        kLast = Math.sqrt(balance0 * balance1);

        withdrawnAmounts = new TokenAmount[](2);
        withdrawnAmounts[0] = TokenAmount({token: address(token0), amount: amount0});
        withdrawnAmounts[1] = TokenAmount({token: address(token1), amount: amount1});
        emit Burn(msg.sender, amount0, amount1, recipient);
    }

    /// @dev Burns LP tokens sent to this contract and swaps one of the output tokens for another
    /// - i.e., the user gets a single token out by burning LP tokens.
    function burnSingle(bytes calldata data) public override nonReentrant returns (uint256 amountOut) {
        (address tokenOut, address recipient) = abi.decode(data, (address, address));
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves();
        uint256 liquidity = balanceOf[address(this)];

        (uint256 _totalSupply, ) = _mintFee(_reserve0, _reserve1);

        uint256 amount0 = (liquidity * _reserve0) / _totalSupply;
        uint256 amount1 = (liquidity * _reserve1) / _totalSupply;

        kLast = Math.sqrt((_reserve0 - amount0) * (_reserve1 - amount1));

        _burn(address(this), liquidity);

        // Swap one token for another
        unchecked {
            if (tokenOut == token1) {
                // Swap `token0` for `token1`
                // - calculate `amountOut` as if the user first withdrew balanced liquidity and then swapped `token0` for `token1`.
                amount1 += _getAmountOut(amount0, _reserve0 - amount0, _reserve1 - amount1);
                _transfer(token1, amount1, recipient);
                amountOut = amount1;
                amount0 = 0;
            } else {
                // Swap `token1` for `token0`.
                if (tokenOut != token0) revert InvalidOutputToken();
                amount0 += _getAmountOut(amount1, _reserve1 - amount1, _reserve0 - amount0);
                _transfer(token0, amount0, recipient);
                amountOut = amount0;
                amount1 = 0;
            }
        }

        (uint256 balance0, uint256 balance1) = _balance();
        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);

        emit Burn(msg.sender, amount0, amount1, recipient);
    }

    /// @dev Swaps one token for another. The router must prefund this contract and ensure there isn't too much slippage.
    function swap(bytes calldata data) public override nonReentrant returns (uint256 amountOut) {
        (address tokenIn, address recipient) = abi.decode(data, (address, address));
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = _getReserves();
        if (_reserve0 == 0) revert PoolUninitialized();
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 amountIn;
        address tokenOut;
        unchecked {
            if (tokenIn == token0) {
                tokenOut = token1;
                amountIn = balance0 - _reserve0;
                amountOut = _getAmountOut(amountIn, _reserve0, _reserve1);
                balance1 -= amountOut;
            } else {
                if (tokenIn != token1) revert InvalidInputToken();
                tokenOut = token0;
                amountIn = balance1 - reserve1;
                amountOut = _getAmountOut(amountIn, _reserve1, _reserve0);
                balance0 -= amountOut;
            }
        }
        _transfer(tokenOut, amountOut, recipient);
        _update(balance0, balance1, _reserve0, _reserve1, _blockTimestampLast);
        emit Swap(recipient, tokenIn, tokenOut, amountIn, amountOut);
    }

    function flashSwap(bytes calldata data) public override nonReentrant returns (uint256 amountOut) {
        
    }


    function _getReserves() internal view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _balance() internal view returns (uint256 balance0, uint256 balance1) {
        //no vault
        balance0 = ERC20(token0).balanceOf(address(this));
        balance1 = ERC20(token1).balanceOf(address(this));
    }

    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1,
        uint32 _blockTimestampLast
    ) internal {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) revert Overflow();
        if (_blockTimestampLast == 0) {
            // TWAP support is disabled for gas efficiency.
            reserve0 = uint112(balance0);
            reserve1 = uint112(balance1);
        } else {
            uint32 blockTimestamp = uint32(block.timestamp);
            if (blockTimestamp != _blockTimestampLast && _reserve0 != 0 && _reserve1 != 0) {
                unchecked {
                    uint32 timeElapsed = blockTimestamp - _blockTimestampLast;
                    uint256 price0 = (uint256(_reserve1) << PRECISION) / _reserve0;
                    price0CumulativeLast += price0 * timeElapsed;
                    uint256 price1 = (uint256(_reserve0) << PRECISION) / _reserve1;
                    price1CumulativeLast += price1 * timeElapsed;
                }
            }
            reserve0 = uint112(balance0);
            reserve1 = uint112(balance1);
            blockTimestampLast = blockTimestamp;
        }
        emit Sync(balance0, balance1);
    }

    function _nonOptimalMintFee(uint256 _amount0, uint256 _amount1, uint256 _reserve0, uint256 _reserve1) 
        internal view returns (uint256 token0Fee, uint256 token1Fee) {
        if (_reserve0 == 0 || _reserve1 == 0) return (0, 0);
        uint256 amount1Optimal = (_amount0 * _reserve1) / _reserve0;
        if (amount1Optimal <= _amount1) {
            token1Fee = (swapFee * (_amount1 - amount1Optimal)) / (2 * MAX_FEE);
        } else {
            uint256 amount0Optimal = (_amount1 * _reserve0) / _reserve1;
            token0Fee = (swapFee * (_amount0 - amount0Optimal)) / (2 * MAX_FEE);
        }
    }

    function _mintFee(uint112 _reserve0, uint112 _reserve1) internal returns (uint256 _totalSupply, uint256 computed) {
        _totalSupply = totalSupply;
        uint256 _kLast = kLast;

        if (_kLast != 0) {
            computed = Math.sqrt(uint256(_reserve0) * _reserve1);
            if (computed > _kLast) {
                // poolFee, % of increase in liquidity.
                uint256 _poolFee = poolFee;
                uint256 numerator = _totalSupply * (computed - _kLast) * _poolFee;
                uint256 denominator = (MAX_FEE - _poolFee) * computed + _poolFee * _kLast;
                uint256 liquidity = numerator / denominator;

                if (liquidity != 0) {
                    _mint(poolFeeTo, liquidity);
                    _totalSupply += liquidity;
                }
            }
        }
    }

    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveAmountIn,
        uint256 reserveAmountOut
    ) internal view returns (uint256 amountOut) {
        uint256 amountInWithFee = amountIn * MAX_FEE_MINUS_SWAP_FEE;
        amountOut = (amountInWithFee * reserveAmountOut) / (reserveAmountIn * MAX_FEE + amountInWithFee);
    }

    function _getAmountIn(
        uint256 amountOut,
        uint256 reserveAmountIn,
        uint256 reserveAmountOut
    ) internal view returns (uint256 amountIn) {
        amountIn = (reserveAmountIn * amountOut * MAX_FEE) / ((reserveAmountOut - amountOut) * MAX_FEE_MINUS_SWAP_FEE) + 1;
    }

    function _transfer(
        address token,
        uint256 shares,
        address to
    ) internal {
        ERC20(token).transfer(to, shares);
    }

    /* --- public view --- */
    function getAssets() public view override returns (address[] memory assets) {
        assets = new address[](2);
        assets[0] = token0;
        assets[1] = token1;
    }

    function getAmountOut(bytes calldata data) public view override returns (uint256 finalAmountOut) {
        (address tokenIn, uint256 amountIn) = abi.decode(data, (address, uint256));
        (uint112 _reserve0, uint112 _reserve1, ) = _getReserves();
        if (tokenIn == token0) {
            finalAmountOut = _getAmountOut(amountIn, _reserve0, _reserve1);
        } else {
            if (tokenIn != token1) revert InvalidInputToken();
            finalAmountOut = _getAmountOut(amountIn, _reserve1, _reserve0);
        }
    }

    function getAmountIn(bytes calldata data) public view override returns (uint256 finalAmountIn) {
        (address tokenOut, uint256 amountOut) = abi.decode(data, (address, uint256));
        (uint112 _reserve0, uint112 _reserve1, ) = _getReserves();
        if (tokenOut == token1) {
            finalAmountIn = _getAmountIn(amountOut, _reserve0, _reserve1);
        } else {
            if (tokenOut != token0) revert InvalidOutputToken();
            finalAmountIn = _getAmountIn(amountOut, _reserve1, _reserve0);
        }
    }

    function getReserves()
        public
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        )
    {
        return _getReserves();
    }

}