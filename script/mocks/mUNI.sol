// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "lib/v4-periphery/lib/v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockUNI is ERC20 {
    constructor() ERC20("Mock UNI", "mUNI") {
        _mint(msg.sender, 1000000 * (10 ** uint256(decimals()))); // Mint 1 million mock UNI to deployer
    }
}
