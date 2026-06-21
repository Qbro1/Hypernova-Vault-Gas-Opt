# Hypernova-Vault-Gas-Opt

This refactor addresses critical architectural inefficiencies in the `Vault.sol` contract. By optimizing EVM state storage and removing redundant external calls, the operational gas cost is significantly reduced by approximately **~7,000 gas per payout execution**.

##  Storage Slot Packing (Optimized `SLOAD`)
###  Previous State (Unoptimized)
```solidity
bool public paused; // Slot 0
uint256 public maxWithdrawalLimit; // Slot 1
uint256 public profitSplit; // Slot 2

```
Each payout call executed three separate cold SLOAD operations, fetching data from three different 256-bit memory slots.
###  Refactored State (Optimized)
```solidity
bool public paused; // 8 bits
uint16 public profitSplit; // 16 bits (Max 10,000 fits perfectly)
uint232 public maxWithdrawalLimit; // 232 bits (Safe up to ~2.6e69)

```
**Impact:** Variables are tightly packed into a **single 256-bit slot**. The EVM fetches all three variables in a single SLOAD operation, saving ~4,200 gas per transaction and lowering the deployment cost. A safety bound check (LimitExceedsUint232) was added to setters/constructors to ensure memory safety.
##  Redundant External Calls (STATICCALL removal)
###  Previous Logic (Unoptimized)
```solidity
if (traderAmount > SafeTransferLib.balanceOf(USDC, address(this))) revert InsufficientBalance();
SafeTransferLib.safeTransfer(USDC, _trader, traderAmount);

```
The contract paid for a STATICCALL to query the USDC token balance right before doing a transfer.
###  Refactored Logic (Optimized)
```solidity
SafeTransferLib.safeTransfer(USDC, _trader, traderAmount);

```
**Impact:** SafeTransferLib (Solady) intrinsically handles execution reverting if the contract possesses an insufficient token balance. Pre-checking the balance is technically redundant and needlessly consumes execution gas. The balanceOf query was deleted entirely, saving an additional ~2,600+ gas per withdrawal. The redundant InsufficientBalance error type was also scrubbed from the codebase.
