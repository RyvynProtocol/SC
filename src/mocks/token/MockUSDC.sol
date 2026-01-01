// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockUSDC is ERC20, Ownable {
    uint256 private constant DECIMAL_FACTOR = 1e6; // 1*10**6
    uint256 public constant MAX_PUBLIC_MINT_PER_USER = 100_000 * DECIMAL_FACTOR; // 100.000 mUSDC per user
    mapping(address => uint256) public userMintedAmount;

    constructor(
        address initialOwner
    ) ERC20("Mock USDC", "mUSDC") Ownable(initialOwner) {
        _mint(msg.sender, 1_000_000 * DECIMAL_FACTOR);
    }

    function mintPublic(address to, uint256 amount) external {
        uint256 mintedAmount = userMintedAmount[msg.sender];
        require(
            mintedAmount + amount <= MAX_PUBLIC_MINT_PER_USER,
            "MockUSDC: You have exceeded the public minting quota"
        );

        userMintedAmount[msg.sender] = mintedAmount + amount;
        _mint(to, amount);
    }

    function mintAdmin(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
