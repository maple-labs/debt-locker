// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { DSTest } from "../../modules/ds-test/src/test.sol";
import { ERC20 }  from "../../modules/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import { IDebtLocker } from "../interfaces/IDebtLocker.sol";

import { DebtLockerFactory } from "../DebtLockerFactory.sol";

import { DebtLockerOwner } from "./accounts/DebtLockerOwner.sol";

contract MintableToken is ERC20 {

    constructor (string memory name, string memory symbol) ERC20(name, symbol) public {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

}

// NOTE: Loan exists to prevent circular dependency tree.
contract Loan {

    address public liquidityAsset;

    constructor(address _liquidityAsset) public {
        liquidityAsset = _liquidityAsset;
    }

    function claim() external {}

    function triggerDefault() external {}

}

contract DebtLockerFactoryTest is DSTest {

    function test_newLocker() external {
        DebtLockerFactory factory  = new DebtLockerFactory();
        MintableToken     token    = new MintableToken("TKN", "TKN");
        DebtLockerOwner   owner    = new DebtLockerOwner();
        DebtLockerOwner   nonOwner = new DebtLockerOwner();
        Loan              loan     = new Loan(address(token));

        IDebtLocker locker = IDebtLocker(owner.debtLockerFactory_newLocker(address(factory), address(loan)));

        // Validate the storage of factory.
        assertEq(factory.owner(address(locker)), address(owner), "Invalid owner");
        assertTrue(factory.isLocker(address(locker)),            "Invalid isLocker");

        // Validate the storage of locker.
        assertEq(address(locker.loan()),           address(loan),  "Incorrect loan address");
        assertEq(locker.pool(),                    address(owner), "Incorrect pool address");
        assertEq(address(locker.liquidityAsset()), address(token), "Incorrect address of liquidity asset");

        // Assert that only the DebtLocker owner can trigger default
        assertTrue(!nonOwner.try_debtLocker_triggerDefault(address(locker)), "Trigger Default succeeded from nonOwner");
        assertTrue(    owner.try_debtLocker_triggerDefault(address(locker)), "Trigger Default failed from owner");
    }

}
