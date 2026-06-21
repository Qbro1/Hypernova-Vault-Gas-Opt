// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity ^0.8.13;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @title Vault
/// @notice Holds USDC and handles profit splitting for trader withdrawals
/// @dev Only the TradingAccounts contract can initiate withdrawals. Owner can configure profit split and withdraw protocol fees.
contract Vault is Ownable {
    // ============ Errors ============

    /// @notice Thrown when contract is paused
    error Paused();

    /// @notice Thrown when caller is not the TradingAccounts contract
    error NotTradingAccounts();

    /// @notice Thrown when withdrawal amount exceeds the maximum limit
    error ExceedsMaxWithdrawal();

    /// @notice Thrown when a zero address is provided
    error ZeroAddress();

    /// @notice Thrown when a zero amount is provided
    error ZeroAmount();

    /// @notice Thrown when profit split is invalid
    error InvalidProfitSplit();

    /// @notice Thrown when profitSplit + bonusBps exceeds BPS_DENOMINATOR
    error InvalidBonusSplit();

    /// @notice Thrown when new limit exceeds uint232 capacity
    error LimitExceedsUint232();

    // ============ Events ============

    event PayoutProcessed(address indexed trader, uint256 traderAmount, uint256 protocolAmount);
    event MaxWithdrawalLimitUpdated(uint256 newLimit);
    event PausedStateChanged(bool isPaused);
    event ProfitSplitUpdated(uint256 profitSplit);

    // ============ Constants ============

    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ============ Immutables ============

    address public immutable USDC;
    address public immutable TRADING_ACCOUNTS;
    uint256 public immutable MIN_PROFIT_SPLIT;

    // ============ State ============
    
    // VARIABLES PACKED INTO A SINGLE 256-BIT SLOT (Saved 2 SLOADs)
    bool public paused; // 8 bits
    uint16 public profitSplit; // 16 bits
    uint232 public maxWithdrawalLimit; // 232 bits

    // ============ Constructor ============

    constructor(
        address _owner,
        address _tradingAccounts,
        address _usdc,
        uint256 _maxWithdrawalLimit,
        uint256 _profitSplit,
        uint256 _minProfitSplit
    ) {
        if (_owner == address(0)) revert ZeroAddress();
        if (_tradingAccounts == address(0)) revert ZeroAddress();
        if (_usdc == address(0)) revert ZeroAddress();
        if (_minProfitSplit == 0 || _minProfitSplit > BPS_DENOMINATOR) revert InvalidProfitSplit();
        if (_profitSplit < _minProfitSplit || _profitSplit > BPS_DENOMINATOR) revert InvalidProfitSplit();
        if (_maxWithdrawalLimit > type(uint232).max) revert LimitExceedsUint232();
        
        _initializeOwner(_owner);
        MIN_PROFIT_SPLIT = _minProfitSplit;
        TRADING_ACCOUNTS = _tradingAccounts;
        USDC = _usdc;
        
        maxWithdrawalLimit = uint232(_maxWithdrawalLimit);
        profitSplit = uint16(_profitSplit);
    }

    // ============ Modifiers ============

    modifier whenNotPaused() {
        if (paused) revert Paused();
        _;
    }

    modifier onlyTradingAccounts() {
        if (msg.sender != TRADING_ACCOUNTS) revert NotTradingAccounts();
        _;
    }

    // ============ Owner Functions ============

    function pause() external onlyOwner {
        paused = true;
        emit PausedStateChanged(true);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit PausedStateChanged(false);
    }

    function setMaxWithdrawalLimit(uint256 _newLimit) external onlyOwner {
        if (_newLimit > type(uint232).max) revert LimitExceedsUint232();
        maxWithdrawalLimit = uint232(_newLimit);
        emit MaxWithdrawalLimitUpdated(_newLimit);
    }

    function setProfitSplit(uint256 _profitSplit) external onlyOwner {
        if (_profitSplit < MIN_PROFIT_SPLIT || _profitSplit > BPS_DENOMINATOR) revert InvalidProfitSplit();
        profitSplit = uint16(_profitSplit);
        emit ProfitSplitUpdated(_profitSplit);
    }

    function ownerWithdraw(uint256 _amount) external onlyOwner {
        if (_amount == 0) revert ZeroAmount();
        // Redundant balanceOf check removed. SafeTransferLib naturally reverts on insufficient balance.
        SafeTransferLib.safeTransfer(USDC, owner(), _amount);
    }

    // ============ TradingAccounts Functions ============

    function processPayout(address _trader, uint256 _amount, uint256 _bonusBps)
        external
        onlyTradingAccounts
        whenNotPaused
    {
        if (_trader == address(0)) revert ZeroAddress();
        if (_amount > maxWithdrawalLimit) revert ExceedsMaxWithdrawal();

        uint256 totalSplit = profitSplit + _bonusBps;
        if (totalSplit > BPS_DENOMINATOR) totalSplit = BPS_DENOMINATOR;

        uint256 traderAmount = (_amount * totalSplit) / BPS_DENOMINATOR;

        // Redundant balanceOf check removed. SafeTransferLib naturally reverts on insufficient balance.
        SafeTransferLib.safeTransfer(USDC, _trader, traderAmount);

        emit PayoutProcessed(_trader, traderAmount, _amount - traderAmount);
    }
}