// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

/// @title DebtLockerInitializer is intended to initialize the storage of a DebtLocker proxy.
interface IDebtLockerInitializer {

    function encodeArguments(address loan_, address pool_) external pure returns (bytes memory encodedArguments_);

    function decodeArguments(bytes calldata encodedArguments_) external pure returns (address loan_, address pool_);

}
