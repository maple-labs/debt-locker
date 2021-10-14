// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { TestUtils }   from "../../modules/contract-test-utils/contracts/test.sol";
import { MockERC20 }   from "../../modules/erc20/src/test/mocks/MockERC20.sol";

import { DebtLockerFactory, DebtLocker, IDebtLockerFactory } from "../DebtLockerFactory.sol";

import { MockGlobals, MockLiquidationStrategy, MockLoan, MockPool, MockPoolFactory } from "./mocks/Mocks.sol";

contract DebtLockerTest is TestUtils {

    MockGlobals       globals;
    MockLoan          loan;
    MockPool          pool;
    MockPoolFactory   poolFactory;
    DebtLockerFactory dlFactory;
    MockERC20         fundsAsset;
    MockERC20         collateralAsset;

    uint256 internal constant MAX_TOKEN_AMOUNT = 1e12 * 1e18;

    function setUp() public {
        dlFactory   = new DebtLockerFactory();
        globals     = new MockGlobals();
        poolFactory = new MockPoolFactory(address(globals));
        pool        = MockPool(poolFactory.createPool(address(this)));

        fundsAsset      = new MockERC20("Funds Asset",      "FA", 18);
        collateralAsset = new MockERC20("Collateral Asset", "CA", 18);

        globals.setPrice(address(collateralAsset), 10 * 10 ** 8);  // 10 USD
        globals.setPrice(address(fundsAsset),      1  * 10 ** 8);  // 1 USD
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
        DebtLocker debtLocker = DebtLocker(pool.createDebtLocker(address (dlFactory), address(loan)));

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

        loan = new MockLoan(1_000_000, 50_000, 1_000_000, address(fundsAsset), address(collateralAsset));

        // Mint funds directly to loan, simulating drawdown and payment
        fundsAsset.mint(address(loan), 50_000);

        // Mint collateral into loan, representing $100k USD at market prices
        collateralAsset.mint(address(loan), 10_000);  

        // Create Debt Locker 
        DebtLocker debtLocker = DebtLocker(pool.createDebtLocker(address(dlFactory), address(loan)));

        loan.setLender(address(debtLocker));

        assertEq(collateralAsset.balanceOf(address(loan)),       10_000);
        assertEq(collateralAsset.balanceOf(address(debtLocker)), 0);
        assertEq(fundsAsset.balanceOf(address(loan)),            50_000);
        assertEq(fundsAsset.balanceOf(address(debtLocker)),      0);

        pool.triggerDefault(address(debtLocker));

        address liquidator = debtLocker.liquidator();

        assertEq(collateralAsset.balanceOf(address(loan)),       0);
        assertEq(collateralAsset.balanceOf(address(debtLocker)), 0);
        assertEq(collateralAsset.balanceOf(liquidator),          10_000);
        assertEq(fundsAsset.balanceOf(address(loan)),            0);
        assertEq(fundsAsset.balanceOf(address(debtLocker)),      50_000);
        assertEq(fundsAsset.balanceOf(liquidator),               0);

        MockLiquidationStrategy mockLiquidationStrategy = new MockLiquidationStrategy();

        mockLiquidationStrategy.flashBorrowLiquidation(liquidator, 10_000, address(collateralAsset), address(fundsAsset));

        assertEq(collateralAsset.balanceOf(address(loan)),       0);
        assertEq(collateralAsset.balanceOf(address(debtLocker)), 0);
        assertEq(collateralAsset.balanceOf(liquidator),          0);
        assertEq(fundsAsset.balanceOf(address(loan)),            0);
        assertEq(fundsAsset.balanceOf(address(debtLocker)),      150_000);
        assertEq(fundsAsset.balanceOf(liquidator),               0);
    }
    
}
