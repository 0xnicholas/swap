// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import "@forge-std/console.sol";
import "@forge-std/Script.sol";
import "../../../src/xp2/_tmp0/Pool.sol";
import "../../../src/xp2/_tmp0/Manager.sol";
import "../../../test/forge/xp2/_tmp0/ERC20Mintable.sol";

contract DeployDevelopment is Script {
    function run() public {
        uint256 wethBalance = 1 ether;
        uint256 usdcBalance = 5042 ether;
        int24 currentTick = 85176;
        uint160 currentSqrtP = 5602277097478614198912276234240;

        vm.startBroadcast();
        ERC20Mintable token0 = new ERC20Mintable("Wrapped Ether", "WETH", 18);
        ERC20Mintable token1 = new ERC20Mintable("USD Coin", "USDC", 18);

        Pool pool = new Pool(
            address(token0),
            address(token1),
            currentSqrtP,
            currentTick
        );

        Manager manager = new Manager();

        token0.mint(msg.sender, wethBalance);
        token1.mint(msg.sender, usdcBalance);

        vm.stopBroadcast();

        console.log("WETH address", address(token0));
        console.log("USDC address", address(token1));
        console.log("Pool address", address(pool));
        console.log("Manager address", address(manager));
    }
}