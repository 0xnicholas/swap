// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "../../lib/solmate/tokens/ERC20.sol";
import {ReentrancyGuard} from "../../lib/solmate/utils/ReentrancyGuard.sol";
import {FixedPointMathLib as Math} from "../../lib/solmate/utils/FixedPointMathLib.sol";

import {IStablePool} from "./interfaces/IStablePool.sol";
import {IStablePoolFactory} from "./interfaces/IStablePoolFactory.sol";
import {IDeployer} from "./interfaces/IDeployer.sol";

error ZeroAddress();
error IdenticalAddress();
error InvalidSwapFee();
error InsufficientLiquidityMinted();
error InvalidAmounts();
error InvalidInputToken();
error PoolUninitialized();
error InvalidOutputToken();

contract StablePool is IStablePool, ERC20, ReentrancyGuard {

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

    uint256 internal reserve0;
    uint256 internal reserve1;
    
    uint256 public immutable decimals0;
    uint256 public immutable decimals1;

    bytes32 public constant override poolIdentifier = "Swap:StablePool";

    constructor() ERC20("Swap Stable LP Token", "SCPLP", 18) {
        //factory = msg.sender
        (bytes memory _deployerData, IDeployer _deployer) = IStablePoolFactory(msg.sender).getDeployData();

        (address _token0, address _token1, uint256 _swapFee) = abi.decode(
            _deployerData, (address, address, uint256)
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

        decimals0 = uint256(10)**(ERC20(_token0).decimals());
        decimals1 = uint256(10)**(ERC20(_token1).decimals());

        poolFee = _deployer.poolFee();
        poolFeeTo = _deployer.poolFeeTo();

        deployer = _deployer;
        
    }

    function mint(bytes calldata data) public override nonReentrant returns (uint256 liquidity) {
        
        address recipient = abi.decode(data, (address));
        (uint256 _reserve0, uint256 _reserve1) = _getReserves();
        (uint256 balance0, uint256 balance1) = _balance();

        uint256 newLiq = _computeLiquidity(balance0, balance1);
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        (uint256 fee0, uint256 fee1) = _nonOptimalMintFee(amount0, amount1, _reserve0, _reserve1);
        
        _reserve0 += uint112(fee0);
        _reserve1 += uint112(fee1);

        (uint256 _totalSupply, uint256 oldLiq) = _mintFee(_reserve0, _reserve1);

        if (_totalSupply == 0) {
            if (amount0 == 0 || amount1 == 0) revert InvalidAmounts();
            liquidity = newLiq - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = ((newLiq - oldLiq) * _totalSupply) / oldLiq;
        }

        if (liquidity == 0) revert InsufficientLiquidityMinted();

        _mint(recipient, liquidity);

        _updateReserves();

        kLast = newLiq;
        emit Mint(msg.sender, amount0, amount1, recipient);
    }

    function burn(bytes calldata data) public override nonReentrant() returns (IStablePool.TokenAmount[] memory withdrawnAmounts) {
        address recipient = abi.decode(data, (address));
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 liquidity = balanceOf[address(this)];

        (uint256 _totalSupply, ) = _mintFee(balance0, balance1);

        uint256 amount0 = (liquidity * balance0) / _totalSupply;
        uint256 amount1 = (liquidity * balance1) / _totalSupply;

        _burn(address(this), liquidity);
        _transfer(token0, amount0, recipient);
        _transfer(token1, amount1, recipient);

        _updateReserves();

        withdrawnAmounts = new TokenAmount[](2);
        withdrawnAmounts[0] = TokenAmount({token: token0, amount: amount0});
        withdrawnAmounts[1] = TokenAmount({token: token1, amount: amount1});

        kLast = _computeLiquidity(balance0 - amount0, balance1 - amount1);

        emit Burn(msg.sender, amount0, amount1, recipient);
    }

    function burnSingle(bytes calldata data) public override nonReentrant returns (uint256 amountOut) {
        (address tokenOut, address recipient) = abi.decode(data, (address, address));
        (uint256 _reserve0, uint256 _reserve1) = _getReserves();
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 liquidity = balanceOf[address(this)];

        (uint256 _totalSupply, ) = _mintFee(balance0, balance1);

        uint256 amount0 = (liquidity * balance0) / _totalSupply;
        uint256 amount1 = (liquidity * balance1) / _totalSupply;

        kLast = _computeLiquidity(balance0 - amount0, balance1 - amount1);
        _burn(address(this), liquidity);

        unchecked {
            if (tokenOut == token1) {
                amount1 += _getAmountOut(amount0, _reserve0 - amount0, _reserve1 - amount1, true);
                _transfer(token1, amount1, recipient);
                amountOut = amount1;
                amount0 = 0;
            } else {
                if (tokenOut != token0) revert InvalidOutputToken();
                amount0 += _getAmountOut(amount1, _reserve0 - amount0, _reserve1 - amount1, false);
                _transfer(token0, amount0, recipient);
                amountOut = amount0;
                amount1 = 0;
            }
        }

        _updateReserves();

        emit Burn(msg.sender, amount0, amount1, recipient);
    }

    function swap(bytes calldata data) public override nonReentrant returns (uint256 amountOut) {
        (address tokenIn, address recipient) = abi.decode(data, (address, address));
        (uint256 _reserve0, uint256 _reserve1, uint256 balance0, uint256 balance1) = _getReservesAndBalances();
        uint256 amountIn;
        address tokenOut;

        if (tokenIn == token0) {
            tokenOut = token1;
            unchecked {
                amountIn = balance0 - _reserve0;
            }
            amountOut = _getAmountOut(amountIn, _reserve0, _reserve1, true);
        } else {
            if (tokenIn != token1) revert InvalidInputToken();
            tokenOut = token0;
            unchecked {
                amountIn = balance1 - _reserve1;
            }
            amountOut = _getAmountOut(amountIn, _reserve0, _reserve1, false);
        }
        _transfer(tokenOut, amountOut, recipient);
        _updateReserves();
        emit Swap(recipient, tokenIn, tokenOut, amountIn, amountOut);
    }



    function getReserves() public view returns (uint256 _reserve0, uint256 _reserve1) {
        return _getReserves();
    }

    function _computeLiquidity(uint256 _reserve0, uint256 _reserve1) internal view returns (uint256 liquidity) {
        unchecked {
            uint256 adjustedReserve0 = (_reserve0 * 1e12) / decimals0;
            uint256 adjustedReserve1 = (_reserve1 * 1e12) / decimals1;
            liquidity = _computeLiquidityFromAdjustedBalances(adjustedReserve0, adjustedReserve1);
        }
    }

    function _computeLiquidityFromAdjustedBalances(uint256 x, uint256 y) internal pure returns (uint256 computed) {
        return Math.sqrt(Math.sqrt(_k(x, y)));
    }

    function _k(uint256 x, uint256 y) internal pure returns (uint256) {
        uint256 _a = (x * y) / 1e12;
        uint256 _b = ((x * x) / 1e12 + (y * y) / 1e12);
        return ((_a * _b) / 1e12); // x3y+y3x >= k
    }

    function _f(uint256 x0, uint256 y) internal pure returns (uint256) {
        return (x0 * ((((y * y) / 1e12) * y) / 1e12)) / 1e12 + (((((x0 * x0) / 1e12) * x0) / 1e12) * y) / 1e12;
    }

    function _d(uint256 x0, uint256 y) internal pure returns (uint256) {
        return (3 * x0 * ((y * y) / 1e12)) / 1e12 + ((((x0 * x0) / 1e12) * x0) / 1e12);
    }

    function _get_y(
        uint256 x0,
        uint256 xy,
        uint256 y
    ) internal pure returns (uint256) {
        for (uint256 i = 0; i < 255; i++) {
            uint256 y_prev = y;
            uint256 k = _f(x0, y);
            if (k < xy) {
                uint256 dy = ((xy - k) * 1e12) / _d(x0, y);
                y = y + dy;
            } else {
                uint256 dy = ((k - xy) * 1e12) / _d(x0, y);
                y = y - dy;
            }
            if (y > y_prev) {
                if (y - y_prev <= 1) {
                    return y;
                }
            } else {
                if (y_prev - y <= 1) {
                    return y;
                }
            }
        }
        return y;
    }

    function _getAmountOut(
        uint256 amountIn,
        uint256 _reserve0,
        uint256 _reserve1,
        bool token0In
    ) internal view returns (uint256 dy) {
        unchecked {
            uint256 adjustedReserve0 = (_reserve0 * 1e12) / decimals0;
            uint256 adjustedReserve1 = (_reserve1 * 1e12) / decimals1;
            uint256 feeDeductedAmountIn = amountIn - (amountIn * swapFee) / MAX_FEE;
            uint256 xy = _k(adjustedReserve0, adjustedReserve1);
            if (token0In) {
                uint256 x0 = adjustedReserve0 + ((feeDeductedAmountIn * 1e12) / decimals0);
                uint256 y = _get_y(x0, xy, adjustedReserve1);
                dy = adjustedReserve1 - y;
                dy = (dy * decimals1) / 1e12;
            } else {
                uint256 x0 = adjustedReserve1 + ((feeDeductedAmountIn * 1e12) / decimals1);
                uint256 y = _get_y(x0, xy, adjustedReserve0);
                dy = adjustedReserve0 - y;
                dy = (dy * decimals0) / 1e12;
            }
        }
    }

    function getAmountOut(bytes calldata data) public view override returns (uint256 finalAmountOut) {
        (address tokenIn, uint256 amountIn) = abi.decode(data, (address, uint256));
        (uint256 _reserve0, uint256 _reserve1) = _getReserves();

        if (tokenIn == token0) {
            finalAmountOut =  _getAmountOut(amountIn, _reserve0, _reserve1, true);
        } else {
            if (tokenIn != token1) revert InvalidInputToken();
            finalAmountOut = _getAmountOut(amountIn, _reserve0, _reserve1, false);
        }
    }

    function _getReservesAndBalances()
        internal
        view
        returns (
            uint256 _reserve0,
            uint256 _reserve1,
            uint256 balance0,
            uint256 balance1
        )
    {
        (_reserve0, _reserve1) = (reserve0, reserve1);
        balance0 = ERC20(token0).balanceOf(address(this));
        balance1 = ERC20(token1).balanceOf(address(this));
    }


    function _balance() internal view returns (uint256 balance0, uint256 balance1) {
        //no vault
        balance0 = ERC20(token0).balanceOf(address(this));
        balance1 = ERC20(token1).balanceOf(address(this));
    }

    function _transfer(
        address token,
        uint256 shares,
        address to
    ) internal {
        ERC20(token).transfer(to, shares);
    }


    function _updateReserves() internal {
        (uint256 _reserve0, uint256 _reserve1) = _balance();
        reserve0 = _reserve0;
        reserve1 = _reserve1;
        emit Sync(_reserve0, _reserve1);
    }

    function _mintFee(uint256 _reserve0, uint256 _reserve1) internal returns (uint256 _totalSupply, uint256 computed) {
        _totalSupply = totalSupply;
        uint256 _kLast = kLast;
        if (_kLast != 0) {
            computed = _computeLiquidity(_reserve0, _reserve1);
            if (computed > _kLast) {
                // `barFee` % of increase in liquidity.
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

    function _getReserves() internal view returns (uint256 _reserve0, uint256 _reserve1) {
        (_reserve0, _reserve1) = (reserve0, reserve1);
    }

    function getNativeReserves() public view returns (uint256 _nativeReserve0, uint256 _nativeReserve1) {
        return _getReserves();
    }

    function getAssets() public view returns (address[] memory assets) {
        assets = new address[](2);
        assets[0] = token0;
        assets[1] = token1;
    }

    function flashSwap(bytes calldata) external pure override returns (uint256) {
        revert();
    }

    function getAmountIn(bytes calldata) external pure override returns (uint256) {
        revert();
    }
}