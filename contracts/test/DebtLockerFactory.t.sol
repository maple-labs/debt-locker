// // SPDX-License-Identifier: AGPL-3.0-or-later
// pragma solidity ^0.8.7;

// import { TestUtils } from "../../modules/contract-test-utils/contracts/test.sol";
// import { ERC20 }     from "../../modules/erc20/src/ERC20.sol";

// import { IDebtLocker } from "../interfaces/IDebtLocker.sol";

// import { DebtLockerFactory } from "../DebtLockerFactory.sol";

// import { Pool } from "./accounts/Pool.sol";

// contract MockToken is ERC20 {

//     constructor (string memory name, string memory symbol) ERC20(name, symbol, uint8(18)) {}

//     function mint(address account, uint256 amount) external {
//         _mint(account, amount);
//     }

// }

// contract MockMapleLoan {

//     uint256 public principalRequested;

//     constructor(uint256 principalRequested_) {
//         principalRequested = principalRequested_;
//     }

// }

// contract DebtLockerFactoryTest is TestUtils {

//     function test_newLocker() external {
//         DebtLockerFactory factory = new DebtLockerFactory();
//         Pool              pool    = new Pool();

//         MockMapleLoan loan = new MockMapleLoan(uint256(1_000_000));

//         IDebtLocker locker = IDebtLocker(pool.debtLockerFactory_newLocker(address(factory), address(loan)));

//         // Validate the storage of factory.
//         assertEq(factory.owner(address(locker)), address(pool), "Invalid owner");
//         assertTrue(factory.isLocker(address(locker)),           "Invalid isLocker");

//         // Validate the storage of locker.
//         assertEq(locker.factory(), address(factory), "Incorrect factory address");
//         assertEq(locker.loan(),    address(loan),    "Incorrect loan address");
//         assertEq(locker.pool(),     address(pool),   "Incorrect pool address");

//         assertEq(locker.principalRemainingAtLastClaim(), uint256(1_000_000), "Incorrect principal remaining at last claim");
//     }

// }
