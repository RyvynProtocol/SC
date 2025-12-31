// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockVault is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;

    // --- VARIABLES ----
    string public name;
    uint256 public totalDeposits;
    uint256 public totalYieldGenerated;

    // --- EVENTS ----
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event YieldInjected(uint256 amount);

    // --- ERRORS ----
    error InvalidAddress();
    error InvalidAmount();
    error InsufficientBalance();

    // --- CONSTRUCTOR ----
    constructor(
        address _asset,
        string memory _name,
        address _owner
    ) Ownable(_owner) {
        if (_asset == address(0)) revert InvalidAddress();
        asset = IERC20(_asset);
        name = _name;
    }

    // --- CORE FUNCTIONS ----
    function deposit(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();

        asset.safeTransferFrom(msg.sender, address(this), amount);
        totalDeposits += amount;

        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external onlyOwner {
        if (amount == 0) revert InvalidAmount();

        uint256 currentBalance = asset.balanceOf(address(this));
        if (amount > currentBalance) revert InsufficientBalance();

        if (amount >= totalDeposits) {
            totalDeposits = 0;
        } else {
            totalDeposits -= amount;
        }

        asset.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    // --- SIMULATION FUNCTIONS ---

    function injectYield(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();

        asset.safeTransferFrom(msg.sender, address(this), amount);

        totalYieldGenerated += amount;
        emit YieldInjected(amount);
    }

    // --- VIEW FUNCTIONS ---
    function getBalance() external view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function getAvailableYield() external view returns (uint256) {
        uint256 currentBalance = asset.balanceOf(address(this));
        if (currentBalance > totalDeposits) {
            return currentBalance - totalDeposits;
        }
        return 0;
    }

    function getVaultInfo()
        external
        view
        returns (
            string memory _name,
            uint256 _principal,
            uint256 _lifetimeYield,
            uint256 _currentBalance,
            uint256 _apyEstimate
        )
    {
        return (
            name,
            totalDeposits,
            totalYieldGenerated,
            asset.balanceOf(address(this)),
            500
        );
    }
}
