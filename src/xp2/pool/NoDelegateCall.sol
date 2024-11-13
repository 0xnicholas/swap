// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

abstract contract NoDelegateCall {
    /// @dev The original address of this contract
    address private immutable original;

    constructor() {
        original = address(this);
    }

    function checkNotDelegateCall() private view {
        require(address(this) == original);
    }

    modifier noDelegateCall() {
        checkNotDelegateCall();
        _;
    }
}