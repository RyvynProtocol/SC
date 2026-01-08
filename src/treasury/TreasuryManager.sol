// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "src/interfaces/IMockVault.sol";
import "src/interfaces/IYieldManager.sol";

contract TreasuryManager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // -- VARIABLES ---
    IERC20 public immutable usdc;
    address public strategyUSDY;
    address public strategyOUSG;
    address public strategyLending;
    address public reserveWallet;
    address public ryUSD;
    address public yieldManager;

    uint256 private constant BASIS_POINTS = 10000;

    uint256 private constant ALLOCATION_ONDO = 4000;
    uint256 private constant ALLOCATION_OUSG = 3500;
    uint256 private constant ALLOCATION_LENDING = 2000;
    uint256 private constant ALLOCATION_RESERVE = 500;

    uint256 public hotWalletThreshold = 500;

    uint256 public hotWalletBalance;
    uint256 public totalDeposited;
    uint256 public totalAllocated;

    // --- EVENTS ---
    event Deposited(address indexed from, uint256 amount);
    event Redeemed(address indexed to, uint256 amount);
    event Allocated(
        uint256 total,
        uint256 usdy,
        uint256 ousg,
        uint256 lending,
        uint256 reserve
    );
    event HotWalletRefilled(uint256 amount);
    event StrategyUpdated(
        string strategyName,
        address oldAddress,
        address newAddress
    );
    event YieldHarvested(
        string indexed strategy,
        uint256 amount,
        uint256 timestamp
    );
    event YieldForwarded(address indexed yieldManager, uint256 amount);

    // --- ERROR ----
    error InvalidAddress();
    error InsufficientLiquidity();

    // --- CONSTRUCTOR ---
    constructor(
        address _usdc,
        address _usdy,
        address _ousg,
        address _lending,
        address _reserve,
        address _owner
    ) Ownable(_owner) {
        if (_usdc == address(0)) revert InvalidAddress();
        usdc = IERC20(_usdc);
        strategyUSDY = _usdy;
        strategyOUSG = _ousg;
        strategyLending = _lending;
        reserveWallet = _reserve;
    }

    // --- MODIFIERS ---
    modifier onlyRyUSD() {
        require(msg.sender == ryUSD, "Only ryUSD can call");
        _;
    }

    // --- ADMIN FUNCTIONS ---
    function setRyUSD(address _ryUSD) external onlyOwner {
        if (_ryUSD == address(0)) revert InvalidAddress();
        ryUSD = _ryUSD;
    }

    function setStrategyUSDY(address _strategy) external onlyOwner {
        emit StrategyUpdated("USDY", strategyUSDY, _strategy);
        strategyUSDY = _strategy;
    }

    function setStrategyOUSG(address _strategy) external onlyOwner {
        emit StrategyUpdated("OUSG", strategyOUSG, _strategy);
        strategyOUSG = _strategy;
    }

    function setStrategyLending(address _strategy) external onlyOwner {
        emit StrategyUpdated("Lending", strategyLending, _strategy);
        strategyLending = _strategy;
    }

    function setReserveWallet(address _reserve) external onlyOwner {
        emit StrategyUpdated("Reserve", reserveWallet, _reserve);
        reserveWallet = _reserve;
    }

    function setYieldManager(address _yieldManager) external onlyOwner {
        if (_yieldManager == address(0)) revert InvalidAddress();
        yieldManager = _yieldManager;
    }

    function allocate() external onlyOwner {
        _allocate(totalDeposited);
    }

    function refillHotWallet(uint256 amount) external onlyOwner {
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        hotWalletBalance += amount;
        emit HotWalletRefilled(amount);
    }

    // --- CORE FUNCTIONS ---
    function onMint(uint256 amount) external onlyRyUSD nonReentrant {
        usdc.safeTransferFrom(msg.sender, address(this), amount);

        totalDeposited += amount;
        hotWalletBalance += amount;

        emit Deposited(msg.sender, amount);
        _checkAndAllocate();
    }

    function _checkAndAllocate() internal {
        uint256 threshold = (totalDeposited * hotWalletThreshold) /
            BASIS_POINTS;
        if (hotWalletBalance > threshold * 2) {
            uint256 excess = hotWalletBalance - threshold;
            _allocate(excess);
        }
    }

    function _allocate(uint256 amount) internal {
        if (amount == 0) return;
        uint256 toUSDY = (amount * ALLOCATION_ONDO) / BASIS_POINTS;
        uint256 toOUSG = (amount * ALLOCATION_OUSG) / BASIS_POINTS;
        uint256 toLending = (amount * ALLOCATION_LENDING) / BASIS_POINTS;
        uint256 toReserve = amount - toUSDY - toOUSG - toLending;

        if (toUSDY > 0 && strategyUSDY != address(0)) {
            usdc.forceApprove(strategyUSDY, toUSDY);
            IMockVault(strategyUSDY).deposit(toUSDY);
        }

        if (toOUSG > 0 && strategyOUSG != address(0)) {
            usdc.forceApprove(strategyOUSG, toOUSG);
            IMockVault(strategyOUSG).deposit(toOUSG);
        }

        if (toLending > 0 && strategyLending != address(0)) {
            usdc.forceApprove(strategyLending, toLending);
            IMockVault(strategyLending).deposit(toLending);
        }

        if (toReserve > 0 && reserveWallet != address(0)) {
            usdc.safeTransfer(reserveWallet, toReserve);
        }

        hotWalletBalance -= amount;
        totalAllocated += amount;

        emit Allocated(totalAllocated, toUSDY, toOUSG, toLending, toReserve);
    }

    function onRedeem(
        address to,
        uint256 amount
    ) external onlyRyUSD nonReentrant {
        if (to == address(0)) revert InvalidAddress();
        if (hotWalletBalance < amount) revert InsufficientLiquidity();

        totalDeposited -= amount;

        unchecked {
            hotWalletBalance -= amount;
        }

        usdc.safeTransfer(to, amount);
        _checkAndRefillHotWallet();
    }

    function _checkAndRefillHotWallet() internal {
        uint256 threshold = (totalDeposited * hotWalletThreshold) /
            BASIS_POINTS;
        if (hotWalletBalance < threshold && totalDeposited > 0) {
            // TODO: auto-withdraw dari lending strategy
            emit HotWalletRefilled(0);
        }
    }

    // --- VIEW FUNCTIONS ---
    function getHotWalletBalance() external view returns (uint256) {
        return hotWalletBalance;
    }

    function getAllocationInfo()
        external
        view
        returns (
            uint256 _totalDeposited,
            uint256 _totalAllocated,
            uint256 _hotWallet
        )
    {
        return (totalDeposited, totalAllocated, hotWalletBalance);
    }

    function getStrategies()
        external
        view
        returns (
            address _usdy,
            address _ousg,
            address _lending,
            address _reserve
        )
    {
        return (strategyUSDY, strategyOUSG, strategyLending, reserveWallet);
    }

    function canRedeem(uint256 amount) external view returns (bool) {
        return hotWalletBalance >= amount;
    }

    function harvestAllYield() external onlyOwner {
        uint256 totalYield = 0;

        if (strategyUSDY != address(0)) {
            uint256 usdyYield = _harvestVaultYield(strategyUSDY, "USDY");
            totalYield += usdyYield;
        }

        if (strategyOUSG != address(0)) {
            uint256 ousgYield = _harvestVaultYield(strategyOUSG, "OUSG");
            totalYield += ousgYield;
        }

        if (strategyLending != address(0)) {
            uint256 lendingYield = _harvestVaultYield(
                strategyLending,
                "Lending"
            );
            totalYield += lendingYield;
        }

        // Forward total yield to YieldManager
        if (totalYield > 0 && yieldManager != address(0)) {
            usdc.forceApprove(yieldManager, totalYield);
            emit YieldForwarded(yieldManager, totalYield);
        }
    }

    function _harvestVaultYield(
        address vault,
        string memory strategyName
    ) internal returns (uint256 yieldAmount) {
        uint256 availableYield = IMockVault(vault).getAvailableYield();

        if (availableYield > 0) {
            IMockVault(vault).withdraw(availableYield);

            emit YieldHarvested(strategyName, availableYield, block.timestamp);
            return availableYield;
        }

        return 0;
    }
}
