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

    function test_claim(uint256 principalRequested_, uint256 paymentAmount1_, uint256 paymentAmount2_, uint256 interestRate_) public {

        /*************************/
        /*** Set up parameters ***/
        /*************************/

        principalRequested_ = constrictToRange(principalRequested_, 1_000_000, MAX_TOKEN_AMOUNT);
        interestRate_       = constrictToRange(interestRate_,       1,         10_000);  // 0.01% to 100%

        uint256 interestAmount = (principalRequested_ * interestRate_ / 10_000);  // Mock interest amount

        paymentAmount1_ = constrictToRange(paymentAmount1_, interestAmount, principalRequested_ / 2 + interestAmount);
        paymentAmount2_ = constrictToRange(paymentAmount2_, interestAmount, principalRequested_ / 2 + interestAmount);

        /**********************************/
        /*** Create Loan and DebtLocker ***/
        /**********************************/

        loan = new MockLoan(principalRequested_, address(fundsAsset), address(collateralAsset));

        DebtLocker debtLocker = DebtLocker(pool.createDebtLocker(address (dlFactory), address(loan)));

        loan.setLender(address(debtLocker));

        /*************************/
        /*** Make two payments ***/
        /*************************/
        
        // Mock a payment amount with interest and principal
        fundsAsset.mint(address(this),    paymentAmount1_);
        fundsAsset.approve(address(loan), paymentAmount1_);  // Mock payment amount

        uint256 principalPortion1 = paymentAmount1_ - interestAmount;

        loan.makePayment(principalPortion1, interestAmount);

        // Mock a second payment amount with interest and principal
        fundsAsset.mint(address(this),    paymentAmount2_);
        fundsAsset.approve(address(loan), paymentAmount2_);  // Mock payment amount

        uint256 principalPortion2 = paymentAmount2_ - interestAmount;

        loan.makePayment(principalPortion2, interestAmount);        

        assertEq(fundsAsset.balanceOf(address(loan)), paymentAmount1_ + paymentAmount2_);
        assertEq(fundsAsset.balanceOf(address(pool)), 0);

        assertEq(debtLocker.principalRemainingAtLastClaim(), loan.principalRequested());

        uint256[7] memory details = pool.claim(address(debtLocker));

        assertEq(fundsAsset.balanceOf(address(loan)), 0);
        assertEq(fundsAsset.balanceOf(address(pool)), paymentAmount1_ + paymentAmount2_);

        assertEq(debtLocker.principalRemainingAtLastClaim(), loan.principal());

        assertEq(details[0], paymentAmount1_ + paymentAmount2_);
        assertEq(details[1], interestAmount * 2);
        assertEq(details[2], principalPortion1 + principalPortion2);
        assertEq(details[3], 0);
        assertEq(details[4], 0);
        assertEq(details[5], 0);
        assertEq(details[6], 0);

        /*************************/
        /*** Make last payment ***/
        /*************************/

        uint256 principalPortion3 = loan.principal();

        // Mock a payment amount with interest and principal
        fundsAsset.mint(address(this),    principalPortion3 + interestAmount);
        fundsAsset.approve(address(loan), principalPortion3 + interestAmount);  // Mock payment amount

        // Reduce the principal in loan and set claimableFunds
        loan.makePayment(principalPortion3, interestAmount);

        details = pool.claim(address(debtLocker));

        assertEq(fundsAsset.balanceOf(address(pool)), paymentAmount1_ + paymentAmount2_ + principalPortion3 + interestAmount);

        assertEq(details[0], principalPortion3 + interestAmount);
        assertEq(details[1], interestAmount);
        assertEq(details[2], principalPortion3);
        assertEq(details[3], 0);
        assertEq(details[4], 0);
        assertEq(details[5], 0);
        assertEq(details[6], 0);
    }

    function test_liquidation_shortfall(uint256 principalRequested_, uint256 paymentAmount_, uint256 principalPortion_, uint256 collateralRequired_) public {

        /*************************/
        /*** Set up parameters ***/
        /*************************/

        principalRequested_ = constrictToRange(principalRequested_, 1_000_000, MAX_TOKEN_AMOUNT);
        collateralRequired_ = constrictToRange(collateralRequired_, 0,         principalRequested_ / 10);                              // 0 - 100% collateralized
        paymentAmount_      = constrictToRange(paymentAmount_,      1,         principalRequested_ - (collateralRequired_ * 10) - 1);  // Must have a shortfall, must be non-zero for claim assertion
        principalPortion_   = constrictToRange(principalPortion_,   0,         paymentAmount_);

        uint256 interestAmount = paymentAmount_ - principalPortion_;

        /**********************************/
        /*** Create Loan and DebtLocker ***/
        /**********************************/

        loan = new MockLoan(principalRequested_, address(fundsAsset), address(collateralAsset));

        // Mint collateral into loan, representing 10x value since market value is $10
        collateralAsset.mint(address(loan), collateralRequired_);  

        DebtLocker debtLocker = DebtLocker(pool.createDebtLocker(address (dlFactory), address(loan)));

        loan.setLender(address(debtLocker));

        /**********************/
        /*** Make a payment ***/
        /**********************/

        fundsAsset.mint(address(this),    paymentAmount_);
        fundsAsset.approve(address(loan), paymentAmount_);

        loan.makePayment(principalPortion_, interestAmount);

        /*************************************/
        /*** Trigger default and liquidate ***/
        /*************************************/

        assertEq(collateralAsset.balanceOf(address(loan)),       collateralRequired_);
        assertEq(collateralAsset.balanceOf(address(debtLocker)), 0);
        assertEq(fundsAsset.balanceOf(address(loan)),            paymentAmount_);
        assertEq(fundsAsset.balanceOf(address(debtLocker)),      0);
        assertEq(fundsAsset.balanceOf(address(pool)),            0);
        assertTrue(!debtLocker.repossessed());

        try pool.triggerDefault(address(debtLocker)) { fail(); } catch { }  // Can't liquidate with claimable funds

        pool.claim(address(debtLocker));

        uint256 principalToCover = loan.principal();  // Remaining principal before default

        pool.triggerDefault(address(debtLocker));

        address liquidator = debtLocker.liquidator();

        assertEq(collateralAsset.balanceOf(address(loan)),       0);
        assertEq(collateralAsset.balanceOf(address(debtLocker)), 0);
        assertEq(collateralAsset.balanceOf(liquidator),          collateralRequired_);
        assertEq(fundsAsset.balanceOf(address(loan)),            0);
        assertEq(fundsAsset.balanceOf(address(debtLocker)),      0);
        assertEq(fundsAsset.balanceOf(liquidator),               0);
        assertEq(fundsAsset.balanceOf(address(pool)),            paymentAmount_);
        assertTrue(debtLocker.repossessed());

        if (collateralRequired_ > 0) {
            MockLiquidationStrategy mockLiquidationStrategy = new MockLiquidationStrategy();

            mockLiquidationStrategy.flashBorrowLiquidation(liquidator, collateralRequired_, address(collateralAsset), address(fundsAsset));
        }

        /*******************/
        /*** Claim funds ***/
        /*******************/

        uint256 amountRecovered = collateralRequired_ * 10;

        assertEq(collateralAsset.balanceOf(address(loan)),       0);
        assertEq(collateralAsset.balanceOf(address(debtLocker)), 0);
        assertEq(collateralAsset.balanceOf(liquidator),          0);
        assertEq(fundsAsset.balanceOf(address(loan)),            0);
        assertEq(fundsAsset.balanceOf(address(debtLocker)),      amountRecovered);
        assertEq(fundsAsset.balanceOf(liquidator),               0);
        assertEq(fundsAsset.balanceOf(address(pool)),            paymentAmount_);

        uint256[7] memory details = pool.claim(address(debtLocker));

        assertEq(fundsAsset.balanceOf(address(debtLocker)), 0);
        assertEq(fundsAsset.balanceOf(address(pool)),       paymentAmount_ + amountRecovered);
        assertTrue(!debtLocker.repossessed());

        assertEq(details[0], amountRecovered);
        assertEq(details[1], 0);
        assertEq(details[2], amountRecovered);  // All funds are registered as principal in a shortfall
        assertEq(details[3], 0);
        assertEq(details[4], 0);
        assertEq(details[5], amountRecovered);
        assertEq(details[6], principalToCover - amountRecovered);
    }

    // function test_liquidation_equalToPrincipal() public {
    //     // Repossess
    //     // Send funds to liquidator
    //     // Claim funds
    //     // Assert losses

    //     loan = new MockLoan(1_000_000, address(fundsAsset), address(collateralAsset));

    //     // Mint funds directly to loan, simulating drawdown and payment
    //     fundsAsset.mint(address(loan), 50_000);

    //     // Mint collateral into loan, representing $950k USD at market prices
    //     collateralAsset.mint(address(loan), 95_000);  

    //     // Create Debt Locker 
    //     DebtLocker debtLocker = DebtLocker(pool.createDebtLocker(address(dlFactory), address(loan)));

    //     loan.setLender(address(debtLocker));

    //     assertEq(collateralAsset.balanceOf(address(loan)),       95_000);
    //     assertEq(collateralAsset.balanceOf(address(debtLocker)), 0);
    //     assertEq(fundsAsset.balanceOf(address(loan)),            50_000);
    //     assertEq(fundsAsset.balanceOf(address(debtLocker)),      0);
    //     assertTrue(!debtLocker.repossessed());

    //     pool.triggerDefault(address(debtLocker));

    //     address liquidator = debtLocker.liquidator();

    //     assertEq(collateralAsset.balanceOf(address(loan)),       0);
    //     assertEq(collateralAsset.balanceOf(address(debtLocker)), 0);
    //     assertEq(collateralAsset.balanceOf(liquidator),          95_000);
    //     assertEq(fundsAsset.balanceOf(address(loan)),            0);
    //     assertEq(fundsAsset.balanceOf(address(debtLocker)),      50_000);
    //     assertEq(fundsAsset.balanceOf(liquidator),               0);
    //     assertTrue(debtLocker.repossessed());

    //     MockLiquidationStrategy mockLiquidationStrategy = new MockLiquidationStrategy();

    //     mockLiquidationStrategy.flashBorrowLiquidation(liquidator, 95_000, address(collateralAsset), address(fundsAsset));

    //     assertEq(collateralAsset.balanceOf(address(loan)),       0);
    //     assertEq(collateralAsset.balanceOf(address(debtLocker)), 0);
    //     assertEq(collateralAsset.balanceOf(liquidator),          0);
    //     assertEq(fundsAsset.balanceOf(address(loan)),            0);
    //     assertEq(fundsAsset.balanceOf(address(debtLocker)),      1_000_000);
    //     assertEq(fundsAsset.balanceOf(liquidator),               0);
    //     assertEq(fundsAsset.balanceOf(address(pool)),            0);

    //     uint256[7] memory details = pool.claim(address(debtLocker));

    //     assertEq(fundsAsset.balanceOf(address(debtLocker)), 0);
    //     assertEq(fundsAsset.balanceOf(address(pool)),       1_000_000);
    //     assertTrue(!debtLocker.repossessed());

    //     assertEq(details[0], 1_000_000);
    //     assertEq(details[1], 0);
    //     assertEq(details[2], 1_000_000);
    //     assertEq(details[3], 0);
    //     assertEq(details[4], 0);
    //     assertEq(details[5], 1_000_000);
    //     assertEq(details[6], 0);
    // }

    // function test_liquidation_greaterThanPrincipal() public {
    //     // Repossess
    //     // Send funds to liquidator
    //     // Claim funds
    //     // Assert losses

    //     loan = new MockLoan(1_000_000, address(fundsAsset), address(collateralAsset));

    //     // Mint funds directly to loan, simulating drawdown and payment
    //     fundsAsset.mint(address(loan), 50_000);

    //     // Mint collateral into loan, representing $975k USD at market prices
    //     collateralAsset.mint(address(loan), 97_500);  

    //     // Create Debt Locker 
    //     DebtLocker debtLocker = DebtLocker(pool.createDebtLocker(address(dlFactory), address(loan)));

    //     loan.setLender(address(debtLocker));

    //     assertEq(collateralAsset.balanceOf(address(loan)),       97_500);
    //     assertEq(collateralAsset.balanceOf(address(debtLocker)), 0);
    //     assertEq(fundsAsset.balanceOf(address(loan)),            50_000);
    //     assertEq(fundsAsset.balanceOf(address(debtLocker)),      0);
    //     assertTrue(!debtLocker.repossessed());

    //     pool.triggerDefault(address(debtLocker));

    //     address liquidator = debtLocker.liquidator();

    //     assertEq(collateralAsset.balanceOf(address(loan)),       0);
    //     assertEq(collateralAsset.balanceOf(address(debtLocker)), 0);
    //     assertEq(collateralAsset.balanceOf(liquidator),          97_500);
    //     assertEq(fundsAsset.balanceOf(address(loan)),            0);
    //     assertEq(fundsAsset.balanceOf(address(debtLocker)),      50_000);
    //     assertEq(fundsAsset.balanceOf(liquidator),               0);
    //     assertTrue(debtLocker.repossessed());

    //     MockLiquidationStrategy mockLiquidationStrategy = new MockLiquidationStrategy();

    //     mockLiquidationStrategy.flashBorrowLiquidation(liquidator, 97_500, address(collateralAsset), address(fundsAsset));

    //     assertEq(collateralAsset.balanceOf(address(loan)),       0);
    //     assertEq(collateralAsset.balanceOf(address(debtLocker)), 0);
    //     assertEq(collateralAsset.balanceOf(liquidator),          0);
    //     assertEq(fundsAsset.balanceOf(address(loan)),            0);
    //     assertEq(fundsAsset.balanceOf(address(debtLocker)),      1_025_000);
    //     assertEq(fundsAsset.balanceOf(liquidator),               0);
    //     assertEq(fundsAsset.balanceOf(address(pool)),            0);

    //     uint256[7] memory details = pool.claim(address(debtLocker));

    //     assertEq(fundsAsset.balanceOf(address(debtLocker)), 0);
    //     assertEq(fundsAsset.balanceOf(address(pool)),       1_025_000);
    //     assertTrue(!debtLocker.repossessed());

    //     assertEq(details[0], 1_025_000);
    //     assertEq(details[1], 25_000);
    //     assertEq(details[2], 1_000_000);
    //     assertEq(details[3], 0);
    //     assertEq(details[4], 0);
    //     assertEq(details[5], 1_025_000);
    //     assertEq(details[6], 0);
    // }
    
    
}
