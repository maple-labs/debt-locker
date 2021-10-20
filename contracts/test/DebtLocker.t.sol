// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { TestUtils }   from "../../modules/contract-test-utils/contracts/test.sol";
import { MockERC20 }   from "../../modules/erc20/src/test/mocks/MockERC20.sol";

import { MapleProxyFactory } from "../../modules/maple-proxy-factory/contracts/MapleProxyFactory.sol";

import { DebtLocker }            from "../DebtLocker.sol";
import { DebtLockerInitializer } from "../DebtLockerInitializer.sol";

import { Governor } from "./accounts/Governor.sol";
import { MockGlobals, MockLiquidationStrategy, MockLoan, MockPool, MockPoolFactory } from "./mocks/Mocks.sol";

contract DebtLockerTest is TestUtils {

    Governor          governor;
    MockGlobals       globals;
    MockLoan          loan;
    MockPool          pool;
    MockPoolFactory   poolFactory;
    MapleProxyFactory dlFactory;
    MockERC20         fundsAsset;
    MockERC20         collateralAsset;

    uint256 internal constant MAX_TOKEN_AMOUNT = 1e12 * 1e18;

    function setUp() public {
        governor    = new Governor();
        globals     = new MockGlobals(address(governor));
        poolFactory = new MockPoolFactory(address(globals));
        dlFactory   = new MapleProxyFactory(address(globals));
        pool        = MockPool(poolFactory.createPool(address(this)));

        fundsAsset      = new MockERC20("Funds Asset",      "FA", 18);
        collateralAsset = new MockERC20("Collateral Asset", "CA", 18);

        // Deploying and registering DebtLocker implementation and initializer
        address implementation = address(new DebtLocker());
        address initializer    = address(new DebtLockerInitializer());

        governor.debtLockerFactory_registerImplementation(address(dlFactory), 1, implementation, initializer);
        governor.debtLockerFactory_setDefaultVersion(address(dlFactory), 1);

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

        DebtLocker debtLocker = DebtLocker(pool.createDebtLocker(address (dlFactory), abi.encode(address(loan), address(pool))));

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

        assertEq(details[0], paymentAmount1_ + paymentAmount2_);      // Total amount of funds claimed
        assertEq(details[1], interestAmount * 2);                     // Excess funds go towards interest
        assertEq(details[2], principalPortion1 + principalPortion2);  // Principal amount
        assertEq(details[3], 0);                                      // `feePaid` is always zero since PD estab fees are paid in `fundLoan` now
        assertEq(details[4], 0);                                      // `excessReturned` is always zero since new loans cannot be overfunded
        assertEq(details[5], 0);                                      // Total recovered from liquidation is zero
        assertEq(details[6], 0);                                      // Zero shortfall since no liquidation

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

        assertEq(details[0], principalPortion3 + interestAmount);  // Total amount of funds claimed
        assertEq(details[1], interestAmount);                      // Excess funds go towards interest
        assertEq(details[2], principalPortion3);                   // Principal amount
        assertEq(details[3], 0);                                   // `feePaid` is always zero since PD estab fees are paid in `fundLoan` now
        assertEq(details[4], 0);                                   // `excessReturned` is always zero since new loans cannot be overfunded
        assertEq(details[5], 0);                                   // Total recovered from liquidation is zero
        assertEq(details[6], 0);                                   // Zero shortfall since no liquidation
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

        DebtLocker debtLocker = DebtLocker(pool.createDebtLocker(address (dlFactory), abi.encode(address(loan), address(pool))));

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

        assertEq(details[0], amountRecovered);                     // Total amount of funds claimed
        assertEq(details[1], 0);                                   // Interest is zero since all funds go towards principal in a shortfall
        assertEq(details[2], amountRecovered);                     // All funds are registered as principal in a shortfall
        assertEq(details[3], 0);                                   // `feePaid` is always zero since PD estab fees are paid in `fundLoan` now
        assertEq(details[4], 0);                                   // `excessReturned` is always zero since new loans cannot be overfunded
        assertEq(details[5], amountRecovered);                     // Total recovered from liquidation
        assertEq(details[6], principalToCover - amountRecovered);  // Shortfall to be covered by burning BPTs
    }

    function test_liquidation_equalToPrincipal(uint256 principalRequested_) public {
        
        /*************************/
        /*** Set up parameters ***/
        /*************************/

        // Round to nearest tenth so no rounding error for collateral
        principalRequested_ = constrictToRange(principalRequested_, 1_000_000, MAX_TOKEN_AMOUNT) / 10 * 10;  
        uint256 collateralRequired = principalRequested_ / 10;  // Amount recovered equal to principal to cover

        /**********************************/
        /*** Create Loan and DebtLocker ***/
        /**********************************/

        loan = new MockLoan(principalRequested_, address(fundsAsset), address(collateralAsset));

        // Mint collateral into loan, representing 10x value since market value is $10
        collateralAsset.mint(address(loan), collateralRequired);  

        DebtLocker debtLocker = DebtLocker(pool.createDebtLocker(address (dlFactory), abi.encode(address(loan), address(pool))));

        loan.setLender(address(debtLocker));

        /*************************************/
        /*** Trigger default and liquidate ***/
        /*************************************/

        assertEq(collateralAsset.balanceOf(address(loan)),       collateralRequired);
        assertEq(collateralAsset.balanceOf(address(debtLocker)), 0);
        assertEq(fundsAsset.balanceOf(address(loan)),            0);
        assertEq(fundsAsset.balanceOf(address(debtLocker)),      0);
        assertEq(fundsAsset.balanceOf(address(pool)),            0);
        assertTrue(!debtLocker.repossessed());

        uint256 principalToCover = loan.principal();  // Remaining principal before default

        pool.triggerDefault(address(debtLocker));

        address liquidator = debtLocker.liquidator();

        assertEq(collateralAsset.balanceOf(address(loan)),       0);
        assertEq(collateralAsset.balanceOf(address(debtLocker)), 0);
        assertEq(collateralAsset.balanceOf(liquidator),          collateralRequired);
        assertEq(fundsAsset.balanceOf(address(loan)),            0);
        assertEq(fundsAsset.balanceOf(address(debtLocker)),      0);
        assertEq(fundsAsset.balanceOf(liquidator),               0);
        assertEq(fundsAsset.balanceOf(address(pool)),            0);
        assertTrue(debtLocker.repossessed());

        if (collateralRequired > 0) {
            MockLiquidationStrategy mockLiquidationStrategy = new MockLiquidationStrategy();

            mockLiquidationStrategy.flashBorrowLiquidation(liquidator, collateralRequired, address(collateralAsset), address(fundsAsset));
        }

        /*******************/
        /*** Claim funds ***/
        /*******************/

        uint256 amountRecovered = collateralRequired * 10;

        assertEq(collateralAsset.balanceOf(address(loan)),       0);
        assertEq(collateralAsset.balanceOf(address(debtLocker)), 0);
        assertEq(collateralAsset.balanceOf(liquidator),          0);
        assertEq(fundsAsset.balanceOf(address(loan)),            0);
        assertEq(fundsAsset.balanceOf(address(debtLocker)),      amountRecovered);
        assertEq(fundsAsset.balanceOf(liquidator),               0);
        assertEq(fundsAsset.balanceOf(address(pool)),            0);

        uint256[7] memory details = pool.claim(address(debtLocker));

        assertEq(fundsAsset.balanceOf(address(debtLocker)), 0);
        assertEq(fundsAsset.balanceOf(address(pool)),       amountRecovered);
        assertTrue(!debtLocker.repossessed());

        assertEq(amountRecovered, principalToCover);

        assertEq(details[0], amountRecovered);  // Total amount of funds claimed
        assertEq(details[1], 0);                // Interest is zero since all funds go towards principal
        assertEq(details[2], amountRecovered);  // All funds are registered as principal
        assertEq(details[3], 0);                // `feePaid` is always zero since PD estab fees are paid in `fundLoan` now
        assertEq(details[4], 0);                // `excessReturned` is always zero since new loans cannot be overfunded
        assertEq(details[5], amountRecovered);  // Total recovered from liquidation
        assertEq(details[6], 0);                // Zero shortfall since principalToCover == amountRecovered
    }

    function test_liquidation_greaterThanPrincipal(uint256 principalRequested_, uint256 excessRecovered_) public {
        
        /*************************/
        /*** Set up parameters ***/
        /*************************/

        // Round to nearest tenth so no rounding error for collateral
        principalRequested_ = constrictToRange(principalRequested_, 1_000_000, MAX_TOKEN_AMOUNT) / 10 * 10;  
        excessRecovered_    = constrictToRange(excessRecovered_,    1,         principalRequested_);  // Amount recovered that is excess
        uint256 collateralRequired = principalRequested_ / 10 + excessRecovered_;                     // Amount recovered greater than principal to cover

        /**********************************/
        /*** Create Loan and DebtLocker ***/
        /**********************************/

        loan = new MockLoan(principalRequested_, address(fundsAsset), address(collateralAsset));

        // Mint collateral into loan, representing 10x value since market value is $10
        collateralAsset.mint(address(loan), collateralRequired);  

        DebtLocker debtLocker = DebtLocker(pool.createDebtLocker(address (dlFactory), abi.encode(address(loan), address(pool))));

        loan.setLender(address(debtLocker));

        /*************************************/
        /*** Trigger default and liquidate ***/
        /*************************************/

        assertEq(collateralAsset.balanceOf(address(loan)),       collateralRequired);
        assertEq(collateralAsset.balanceOf(address(debtLocker)), 0);
        assertEq(fundsAsset.balanceOf(address(loan)),            0);
        assertEq(fundsAsset.balanceOf(address(debtLocker)),      0);
        assertEq(fundsAsset.balanceOf(address(pool)),            0);
        assertTrue(!debtLocker.repossessed());

        uint256 principalToCover = loan.principal();  // Remaining principal before default

        pool.triggerDefault(address(debtLocker));

        address liquidator = debtLocker.liquidator();

        assertEq(collateralAsset.balanceOf(address(loan)),       0);
        assertEq(collateralAsset.balanceOf(address(debtLocker)), 0);
        assertEq(collateralAsset.balanceOf(liquidator),          collateralRequired);
        assertEq(fundsAsset.balanceOf(address(loan)),            0);
        assertEq(fundsAsset.balanceOf(address(debtLocker)),      0);
        assertEq(fundsAsset.balanceOf(liquidator),               0);
        assertEq(fundsAsset.balanceOf(address(pool)),            0);
        assertTrue(debtLocker.repossessed());

        if (collateralRequired > 0) {
            MockLiquidationStrategy mockLiquidationStrategy = new MockLiquidationStrategy();

            mockLiquidationStrategy.flashBorrowLiquidation(liquidator, collateralRequired, address(collateralAsset), address(fundsAsset));
        }

        /*******************/
        /*** Claim funds ***/
        /*******************/

        uint256 amountRecovered = collateralRequired * 10;

        assertEq(collateralAsset.balanceOf(address(loan)),       0);
        assertEq(collateralAsset.balanceOf(address(debtLocker)), 0);
        assertEq(collateralAsset.balanceOf(liquidator),          0);
        assertEq(fundsAsset.balanceOf(address(loan)),            0);
        assertEq(fundsAsset.balanceOf(address(debtLocker)),      amountRecovered);
        assertEq(fundsAsset.balanceOf(liquidator),               0);
        assertEq(fundsAsset.balanceOf(address(pool)),            0);

        uint256[7] memory details = pool.claim(address(debtLocker));

        assertEq(fundsAsset.balanceOf(address(debtLocker)), 0);
        assertEq(fundsAsset.balanceOf(address(pool)),       amountRecovered);
        assertTrue(!debtLocker.repossessed());

        assertEq(details[0], amountRecovered);                     // Total amount of funds claimed
        assertEq(details[1], amountRecovered - principalToCover);  // Excess funds go towards interest
        assertEq(details[2], principalToCover);                    // Principal is fully covered
        assertEq(details[3], 0);                                   // `feePaid` is always zero since PD estab fees are paid in `fundLoan` now
        assertEq(details[4], 0);                                   // `excessReturned` is always zero since new loans cannot be overfunded
        assertEq(details[5], amountRecovered);                     // Total recovered from liquidation
        assertEq(details[6], 0);                                   // Zero shortfall since principalToCover == amountRecovered
    }    
    
}
