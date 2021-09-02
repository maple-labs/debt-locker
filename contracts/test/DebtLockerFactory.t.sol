// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { DSTest } from "../../modules/ds-test/src/test.sol";
import { ERC20 }  from "../../modules/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import { IDebtLocker } from "../interfaces/IDebtLocker.sol";

import { DebtLockerFactory } from "../DebtLockerFactory.sol";

import { Pool } from "./accounts/Pool.sol";

contract MockToken is ERC20 {

    constructor (string memory name, string memory symbol) ERC20(name, symbol) public {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

}

contract MockLoan {

    address public liquidityAsset;

    constructor(address _liquidityAsset) public {
        liquidityAsset = _liquidityAsset;
    }

    function claim() external {}

    function triggerDefault() external {}

}

contract DebtLockerFactoryTest is DSTest {

    function test_newLocker() external {
        DebtLockerFactory factory = new DebtLockerFactory();
        MockToken         token   = new MockToken("TKN", "TKN");
        Pool              pool    = new Pool();
        Pool              notPool = new Pool();

        MockLoan loan = new MockLoan(address(token));

        IDebtLocker locker = IDebtLocker(pool.debtLockerFactory_newLocker(address(factory), address(loan)));

        // Validate the storage of factory.
        assertEq(factory.owner(address(locker)), address(pool), "Invalid owner");
        assertTrue(factory.isLocker(address(locker)),            "Invalid isLocker");

        // Validate the storage of locker.
        assertEq(address(locker.loan()),           address(loan),  "Incorrect loan address");
        assertEq(locker.pool(),                    address(pool),  "Incorrect pool address");
        assertEq(address(locker.liquidityAsset()), address(token), "Incorrect address of liquidity asset");

        // Assert that only the DebtLocker owner (pool) can trigger default
        assertTrue(!notPool.try_debtLocker_triggerDefault(address(locker)), "Trigger Default succeeded from notPool");
        assertTrue(    pool.try_debtLocker_triggerDefault(address(locker)), "Trigger Default failed from pool");
    }

}
