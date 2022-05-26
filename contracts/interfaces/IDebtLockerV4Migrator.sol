// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

/// @title DebtLockerInitializer is intended to initialize the storage of a DebtLocker proxy.
interface IDebtLockerV4Migrator {

    function encodeArguments(address migrator_) external pure returns (bytes memory encodedArguments_);

    function decodeArguments(bytes calldata encodedArguments_) external pure returns (address migrator_);

}
