// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { IDebtLockerV4Migrator } from "./interfaces/IDebtLockerV4Migrator.sol";

import { DebtLockerStorage } from "./DebtLockerStorage.sol";

/// @title DebtLockerV4Migrator is intended to initialize the storage of a DebtLocker proxy.
contract DebtLockerV4Migrator is IDebtLockerV4Migrator, DebtLockerStorage {

    function encodeArguments(address migrator_) external pure override returns (bytes memory encodedArguments_) {
        return abi.encode(migrator_);
    }

    function decodeArguments(bytes calldata encodedArguments_) public pure override returns (address migrator_) {
        ( migrator_ ) = abi.decode(encodedArguments_, (address));
    }

    fallback() external {

        // Taking the migrator_ address as argument for now, but ideally this would be hardcoded in the debtLocker migrator registered in the factory
        ( address migrator_ ) = decodeArguments(msg.data);

        _migrator = migrator_;
    }

}
