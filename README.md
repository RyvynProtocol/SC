# Ryvyn Protocol

**Ryvyn Protocol** is a decentralized yield-bearing stablecoin protocol built on Ethereum. Users can deposit USDC to mint ryUSD (Ryvyn USD) and earn passive yield through ryBOND rewards.

## Overview

Ryvyn Protocol provides a sustainable yield mechanism through:

- **ryUSD**: A 1:1 USDC-backed stablecoin with 6 decimals
- **ryBOND**: A yield reward token with built-in vesting (7 days by default)
- **Treasury Management**: Automated allocation of deposited funds across multiple yield strategies
- **Dynamic Rewards**: Activity-based reward distribution using token bucket mechanics

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Actions                            │
│              (deposit USDC / withdraw / transfer)               │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                           ryUSD                                 │
│                (ERC20 Stablecoin - 1:1 USDC)                   │
└──────────────┬─────────────────────────────────┬────────────────┘
               │                                 │
               ▼                                 ▼
┌──────────────────────────┐      ┌──────────────────────────────┐
│     TreasuryManager      │      │       RyvynHandler           │
│   (Fund Allocation)      │      │    (Reward Calculation)      │
│                          │      │                              │
│  ┌──────────────────┐   │      │   ┌─────────────────────┐    │
│  │   Strategies:    │   │      │   │   Token Buckets     │    │
│  │ • USDY          │   │      │   │   (Age Tracking)    │    │
│  │ • OUSG          │   │      │   └─────────────────────┘    │
│  │ • Lending       │   │      │              │               │
│  │ • Reserve       │   │      │              ▼               │
│  └──────────────────┘   │      │   ┌─────────────────────┐    │
└──────────────────────────┘      │   │   YieldManager      │    │
               │                  │   │ (Dynamic Rewards)   │    │
               │                  │   └─────────────────────┘    │
               │                  └──────────────┬───────────────┘
               │                                 │
               ▼                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                          ryBOND                                 │
│                 (Vested Yield Rewards)                         │
│              - Locked → Vested → Claimable                     │
└─────────────────────────────────────────────────────────────────┘
```

## Core Contracts

| Contract              | Description                                                              |
| --------------------- | ------------------------------------------------------------------------ |
| `ryUSD.sol`           | ERC20 stablecoin, 1:1 backed by USDC with deposit/withdraw functionality |
| `ryBOND.sol`          | Yield reward contract with linear vesting mechanism                      |
| `RyvynHandler.sol`    | Core logic for token bucket tracking and reward calculations             |
| `TreasuryManager.sol` | Manages fund allocation across yield strategies                          |
| `YieldManager.sol`    | Handles yield pool and calculates dynamic reward rates                   |

## Features

### 🔐 Secure Deposits

- Deposit USDC to mint ryUSD (1:1 ratio)
- USDC is automatically allocated to yield-generating strategies

### 💰 Yield Generation

- Treasury funds are distributed across multiple strategies:
  - **40%** → USDY (Ondo Finance)
  - **30%** → OUSG (Ondo Finance)
  - **20%** → Lending protocols
  - **10%** → Reserve wallet

### 🎁 Reward Distribution

- Earn ryBOND tokens based on holding time and transfer activity
- Dynamic reward rates based on 7-day moving average volume
- Token bucket system tracks "age" of holdings for fair reward distribution

### ⏳ Vesting Mechanism

- ryBOND rewards vest linearly over 7 days (configurable)
- Claim vested rewards anytime after vesting period

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/) installed

### Installation

```shell
git clone <repository-url>
cd SC
forge install
```

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Format

```shell
forge fmt
```

### Deploy

**Network: Mantle Testnet Sepolia**

| Parameter | Value                            |
| --------- | -------------------------------- |
| RPC URL   | `https://rpc.sepolia.mantle.xyz` |
| Chain ID  | `5003`                           |
| Explorer  | `https://sepolia.mantlescan.xyz` |

```shell
forge script script/Deploy.s.sol:DeployScript --rpc-url https://rpc.sepolia.mantle.xyz --private-key <your_private_key> --broadcast
```

Or using environment variables:

```shell
export RPC_URL=https://rpc.sepolia.mantle.xyz
export PRIVATE_KEY=<your_private_key>

forge script script/Deploy.s.sol:DeployScript --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

## Project Structure

```
src/
├── core/
│   ├── ryUSD.sol           # Stablecoin contract
│   ├── ryBOND.sol          # Yield reward contract
│   └── RyvynHandler.sol    # Core handler logic
├── treasury/
│   ├── TreasuryManager.sol # Fund allocation
│   └── YieldManager.sol    # Yield pool management
├── interfaces/             # Contract interfaces
├── logic/
│   └── TokenBucketLib.sol  # Token bucket library
└── mocks/                  # Mock contracts for testing

script/
├── Deploy.s.sol            # Main deployment script
├── UpgradeHandler.s.sol    # Handler upgrade script
├── UpgradeRyBOND.s.sol     # ryBOND upgrade script
└── ...

test/
└── *.t.sol                 # Test files
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Security

⚠️ **Warning**: This protocol is under active development. Use at your own risk. Smart contracts have not been audited.

---

Built with ❤️ using [Foundry](https://book.getfoundry.sh/)
