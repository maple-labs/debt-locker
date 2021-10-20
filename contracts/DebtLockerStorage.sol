// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { IDebtLockerStorage } from "./interfaces/IDebtLockerStorage.sol";

/// @title DebtLockerStorage maps the storage layout of a DebtLocker.
contract DebtLockerStorage is IDebtLockerStorage {

    address public override loan;
    address public override pool;
    address public override liquidator;

    uint256 public override allowedSlippage;
    uint256 public override amountRecovered;
    uint256 public override minRatio;
    uint256 public override principalRemainingAtLastClaim;

    bool public override repossessed;
}