// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { TestUtils }   from "../../modules/contract-test-utils/contracts/test.sol";
import { MockERC20 }   from "../../modules/erc20/src/test/mocks/MockERC20.sol";

import { DebtLockerFactory, DebtLocker, IDebtLockerFactory } from "../DebtLockerFactory.sol";

import { MockLoan, MockPool } from "./mocks/Mocks.sol";

contract DebtLockerTest is TestUtils {

    MockLoan          loan;
    MockPool          pool;
    DebtLockerFactory dlFactory;
    MockERC20         fundsAsset;
    MockERC20         collateralAsset;

    uint256 internal constant MAX_TOKEN_AMOUNT = 1e12 * 1e18;

    function setUp() public {
        dlFactory       = new DebtLockerFactory();
        pool            = new MockPool(address(dlFactory));
        fundsAsset      = new MockERC20("Funds Asset",      "FA", 18);
        collateralAsset = new MockERC20("Collateral Asset", "CA", 18);
    }

    function test_claim(uint256 principalRequested_, uint256 endingPrincipal_, uint256 claimableFunds_, uint256 noOfPayments_, uint256 interestRate_) public {

        principalRequested_ = constrictToRange(principalRequested_, 1_000_000, MAX_TOKEN_AMOUNT);
        endingPrincipal_    = constrictToRange(endingPrincipal_,    0,         principalRequested_);
        noOfPayments_       = constrictToRange(noOfPayments_,       1,         10);
        interestRate_       = constrictToRange(interestRate_,       1,         10_000);  // 0.01% to 100%

        uint256 interestAmount = (principalRequested_ * interestRate_ / 10_000);  // Mock interest amount

        claimableFunds_ = constrictToRange(claimableFunds_, interestAmount, principalRequested_ + interestAmount);
        
        // Create the loan 
        loan = new MockLoan(principalRequested_, claimableFunds_, principalRequested_, address(fundsAsset), address(collateralAsset));
        
        // Mint funds directly to loan.
        fundsAsset.mint(address(loan), claimableFunds_);

        uint256 principalPortion;

        if (claimableFunds_ > interestAmount) {
            principalPortion = claimableFunds_ - interestAmount;
        }

        loan.putFunds(principalPortion > principalRequested_ ? principalRequested_: principalPortion);

        // Create debt Locker 
        DebtLocker debtLocker = DebtLocker(pool.createDebtLocker(address(loan)));

        loan.setLender(address(debtLocker));

        assertEq(fundsAsset.balanceOf(address(loan)), claimableFunds_);
        assertEq(fundsAsset.balanceOf(address(pool)), 0);

        assertEq(debtLocker.principalRemainingAtLastClaim(), loan.principalRequested());

        uint256[7] memory details = pool.claim(address(debtLocker));

        assertEq(fundsAsset.balanceOf(address(loan)), 0);
        assertEq(fundsAsset.balanceOf(address(pool)), claimableFunds_);

        assertEq(debtLocker.principalRemainingAtLastClaim(), loan.principal());

        assertEq(details[0], claimableFunds_);
        assertEq(details[1], claimableFunds_ - principalPortion);
        assertEq(details[2], principalPortion);

        uint256 principalPortionLeft = loan.principal();
        uint256 newClaimableFunds    = principalPortionLeft + (principalRequested_ * interestRate_ / 10_000) * noOfPayments_;  // Different mock interest amount plus remaining principal

        // Mint funds directly to loan.
        fundsAsset.mint(address(loan), newClaimableFunds);
        
        // Reduce the principal in loan and set claimableFunds
        loan.setClaimableFunds(newClaimableFunds);
        loan.putFunds(principalPortionLeft);

        details = pool.claim(address(debtLocker));

        assertEq(fundsAsset.balanceOf(address(pool)), claimableFunds_ + newClaimableFunds);

        assertEq(details[0], newClaimableFunds);
        assertEq(details[1], newClaimableFunds - principalPortionLeft);
        assertEq(details[2], principalPortionLeft);
    }

    function test_liquidation() public {
        // Repossess
        // Send funds to liquidator
        // Claim funds
        // Assert losses

        loan = new MockLoan(1_000_000, 10_000, 1_000_000, address(fundsAsset), address(collateralAsset));

        // Mint funds directly to loan, simulating drawdown and payment
        fundsAsset.mint(address(loan), 10_000);

        collateralAsset.mint(address(loan), 200_000);  // Mint collateral into loan

        debtLocker.triggerDefault();
    }
    
}
