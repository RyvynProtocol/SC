// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../interfaces/IRyvynHandler.sol";
import "../interfaces/ITreasuryManager.sol";

contract RyUSD is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable underlyingToken;
    address public ryvynHandler;
    address public treasuryManager;

    struct MintRecord {
        address user;
        uint256 amount;
        uint256 timestamp;
        uint256 blockNumber;
    }

    MintRecord[] public mintHistory;
    mapping(address => uint256[]) public userMintIndices;

    uint256 public totalMinted;
    uint256 public totalBurned;

    event Deposit(
        address indexed user,
        uint256 amount,
        uint256 indexed mintIndex
    );
    event Withdrawal(address indexed user, uint256 amount);
    event HandlerUpdated(
        address indexed oldHandler,
        address indexed newHandler
    );
    event TreasuryUpdated(
        address indexed oldTreasury,
        address indexed newTreasury
    );

    constructor(
        address _underlyingToken,
        address _initialOwner
    ) ERC20("Ryvyn USD", "ryUSD") Ownable(_initialOwner) {
        require(_underlyingToken != address(0), "Invalid token");
        underlyingToken = IERC20(_underlyingToken);
    }

    // --- CONFIGURATION ---
    function setHandler(address _handler) external onlyOwner {
        emit HandlerUpdated(ryvynHandler, _handler);
        ryvynHandler = _handler;
    }

    function setTreasury(address _treasury) external onlyOwner {
        emit TreasuryUpdated(treasuryManager, _treasury);
        treasuryManager = _treasury;
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    // --- USER ACTIONS ---
    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Zero amount");

        underlyingToken.safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
        uint256 mintIndex = mintHistory.length;
        mintHistory.push(
            MintRecord({
                user: msg.sender,
                amount: amount,
                timestamp: block.timestamp,
                blockNumber: block.number
            })
        );
        userMintIndices[msg.sender].push(mintIndex);

        totalMinted += amount;

        if (treasuryManager != address(0)) {
            underlyingToken.forceApprove(treasuryManager, amount);
            ITreasuryManager(treasuryManager).onMint(amount);
        }

        emit Deposit(msg.sender, amount, mintIndex);
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        _burn(msg.sender, amount);
        totalBurned += amount;

        if (treasuryManager != address(0)) {
            ITreasuryManager(treasuryManager).onRedeem(msg.sender, amount);
        } else {
            underlyingToken.safeTransfer(msg.sender, amount);
        }

        emit Withdrawal(msg.sender, amount);
    }

    // --- VIEW FUNCTIONS ---
    function getMintHistoryLength() external view returns (uint256) {
        return mintHistory.length;
    }

    function getMintRecord(
        uint256 index
    ) external view returns (MintRecord memory) {
        require(index < mintHistory.length, "Invalid index");
        return mintHistory[index];
    }

    function getUserMintCount(address user) external view returns (uint256) {
        return userMintIndices[user].length;
    }

    function getUserMintHistory(
        address user
    ) external view returns (MintRecord[] memory) {
        uint256[] memory indices = userMintIndices[user];
        MintRecord[] memory records = new MintRecord[](indices.length);
        for (uint256 i = 0; i < indices.length; i++) {
            records[i] = mintHistory[indices[i]];
        }
        return records;
    }

    function getStats()
        external
        view
        returns (
            uint256 _totalMinted,
            uint256 _totalBurned,
            uint256 _totalSupply,
            uint256 _mintCount
        )
    {
        return (totalMinted, totalBurned, totalSupply(), mintHistory.length);
    }

    // --- HOOKS ---
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        super._update(from, to, value);

        if (
            ryvynHandler != address(0) && from != address(0) && to != address(0)
        ) {
            IRyvynHandler(ryvynHandler).handleTransfer(from, to, value);
        }
    }
}
