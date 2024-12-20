// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.27;

import "@solmate/tokens/ERC20.sol";

contract ERC20Mintable is ERC20 {
    constructor(string memory name_, string memory symbol_, uint8 decimals_)
        ERC20(name_, symbol_, decimals_)
    {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}