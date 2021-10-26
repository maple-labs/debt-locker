// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { TestUtils }              from "../../modules/contract-test-utils/contracts/test.sol";
import { MockERC20 }              from "../../modules/erc20/src/test/mocks/MockERC20.sol";
import { ConstructableMapleLoan } from "../../modules/loan/contracts/test/mocks/Mocks.sol";

import { DebtLocker }            from "../DebtLocker.sol";
import { DebtLockerFactory }     from "../DebtLockerFactory.sol";
import { DebtLockerInitializer } from "../DebtLockerInitializer.sol";

import { Governor }     from "./accounts/Governor.sol";
import { PoolDelegate } from "./accounts/PoolDelegate.sol";

import { ILiquidatorLike } from "../interfaces/Interfaces.sol";

import { MockGlobals, MockLiquidationStrategy, MockPool, MockPoolFactory } from "./mocks/Mocks.sol";

interface Hevm {

    // Sets block timestamp to `x`
    function warp(uint256 x) external view;

}

contract DebtLockerTest is TestUtils {

    ConstructableMapleLoan internal loan;
    DebtLockerFactory      internal dlFactory;
    DebtLocker             internal debtLocker;
    Governor               internal governor;
    MockERC20              internal collateralAsset;
    MockERC20              internal fundsAsset;
    MockGlobals            internal globals;
    MockPool               internal pool;
    MockPoolFactory        internal poolFactory;
    PoolDelegate           internal notPoolDelegate;
    PoolDelegate           internal poolDelegate;

    Hevm hevm = Hevm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    uint256 internal constant MAX_TOKEN_AMOUNT = 1e12 * 1e18;

    function setUp() public {
        governor        = new Governor();
        notPoolDelegate = new PoolDelegate();
        poolDelegate    = new PoolDelegate();

        globals     = new MockGlobals(address(governor));
        poolFactory = new MockPoolFactory(address(globals));
        dlFactory   = new DebtLockerFactory(address(globals));

        pool = MockPool(poolFactory.createPool(address(poolDelegate)));

        collateralAsset = new MockERC20("Collateral Asset", "CA", 18);
        fundsAsset      = new MockERC20("Funds Asset",      "FA", 18);

        // Deploying and registering DebtLocker implementation and initializer
        address implementation = address(new DebtLocker());
        address initializer    = address(new DebtLockerInitializer());

        governor.mapleProxyFactory_registerImplementation(address(dlFactory), 1, implementation, initializer);
        governor.mapleProxyFactory_setDefaultVersion(address(dlFactory), 1);

        globals.setPrice(address(collateralAsset), 10 * 10 ** 8);  // 10 USD
        globals.setPrice(address(fundsAsset),      1  * 10 ** 8);  // 1 USD
    }

    function _createLoan(uint256 principalRequested_) internal returns (ConstructableMapleLoan loan_) {
        address[2] memory assets     = [address(collateralAsset), address(fundsAsset)];
        uint256[6] memory parameters = [uint256(10 days), uint256(30 days), 6, 0.10e18, 0, 0];
        uint256[4] memory fees       = [uint256(0), uint256(0), uint256(0), uint256(0)];
        uint256[3] memory requests   = [0, principalRequested_, 0];

        loan_ = new ConstructableMapleLoan(address(this), assets, parameters, requests, fees);
    }

    function _createFundAndDrawdownLoan(uint256 principalRequested_) internal returns (ConstructableMapleLoan loan_, DebtLocker debtLocker_) {
        loan_ = _createLoan(principalRequested_);

        debtLocker_ = DebtLocker(pool.createDebtLocker(address(dlFactory), address(loan_)));

        fundsAsset.mint(address(this),    principalRequested_);
        fundsAsset.approve(address(loan_), principalRequested_);

        loan_.fundLoan(address(debtLocker_), principalRequested_);
        loan_.drawdownFunds(loan_.drawableFunds(), address(1));  // Drawdown to empty funds from loan (account for estab fees)
    }

    function test_claim(uint256 principalRequested_) public {

        /**********************************/
        /*** Create Loan and DebtLocker ***/
        /**********************************/

        principalRequested_ = constrictToRange(principalRequested_, 1_000_000, MAX_TOKEN_AMOUNT);

        ( loan, debtLocker ) = _createFundAndDrawdownLoan(principalRequested_);

        fundsAsset.mint(address(this),    principalRequested_);
        fundsAsset.approve(address(loan), principalRequested_);

        loan.fundLoan(address(debtLocker), principalRequested_);
        loan.drawdownFunds(loan.drawableFunds(), address(1));  // Drawdown to empty funds from loan (account for estab fees)

        /*************************/
        /*** Make two payments ***/
        /*************************/

        ( uint256 principal1, uint256 interest1, uint256 fees1 ) = loan.getNextPaymentsBreakDown(1);

        uint256 total1 = principal1 + interest1 + fees1;

        // Mock a payment amount with interest and principal
        fundsAsset.mint(address(this),    total1);
        fundsAsset.approve(address(loan), total1);  // Mock payment amount

        loan.makePayments(1, total1);

        ( uint256 principal2, uint256 interest2, uint256 fees2 ) = loan.getNextPaymentsBreakDown(1);

        uint256 total2 = principal2 + interest2 + fees2;

        // Mock a second payment amount with interest and principal
        fundsAsset.mint(address(this),    total2);
        fundsAsset.approve(address(loan), total2);  // Mock payment amount

        loan.makePayments(1, total2);

        assertEq(fundsAsset.balanceOf(address(loan)), total1 + total2);
        assertEq(fundsAsset.balanceOf(address(pool)), 0);

        assertEq(debtLocker.principalRemainingAtLastClaim(), loan.principalRequested());

        uint256[7] memory details = pool.claim(address(debtLocker));

        assertEq(fundsAsset.balanceOf(address(loan)), 0);
        assertEq(fundsAsset.balanceOf(address(pool)), total1 + total2);

        assertEq(debtLocker.principalRemainingAtLastClaim(), loan.principal());

        assertEq(details[0], total1 + total2);          // Total amount of funds claimed
        assertEq(details[1], interest1 + interest2);    // Excess funds go towards interest
        assertEq(details[2], principal1 + principal2);  // Principal amount
        assertEq(details[3], 0);                        // `feePaid` is always zero since PD establishment fees are paid in `fundLoan` now
        assertEq(details[4], 0);                        // `excessReturned` is always zero since new loans cannot be over-funded
        assertEq(details[5], 0);                        // Total recovered from liquidation is zero
        assertEq(details[6], 0);                        // Zero shortfall since no liquidation

        /*************************/
        /*** Make last payment ***/
        /*************************/

        ( uint256 principal3, uint256 interest3, uint256 fees3 ) = loan.getNextPaymentsBreakDown(1);

        uint256 total3 = principal3 + interest3 + fees3;

        // Mock a payment amount with interest and principal
        fundsAsset.mint(address(this),    total3);
        fundsAsset.approve(address(loan), total3);  // Mock payment amount

        // Reduce the principal in loan and set claimableFunds
        loan.makePayments(1, total3);

        details = pool.claim(address(debtLocker));

        assertEq(fundsAsset.balanceOf(address(pool)), total1 + total2 + total3);

        assertEq(details[0], total3);      // Total amount of funds claimed
        assertEq(details[1], interest3);   // Excess funds go towards interest
        assertEq(details[2], principal3);  // Principal amount
        assertEq(details[3], 0);           // `feePaid` is always zero since PD establishment fees are paid in `fundLoan` now
        assertEq(details[4], 0);           // `excessReturned` is always zero since new loans cannot be over-funded
        assertEq(details[5], 0);           // Total recovered from liquidation is zero
        assertEq(details[6], 0);           // Zero shortfall since no liquidation
    }

    function test_liquidation_shortfall(uint256 principalRequested_, uint256 collateralRequired_) public {

        /**********************************/
        /*** Create Loan and DebtLocker ***/
        /**********************************/

        principalRequested_ = constrictToRange(principalRequested_, 1_000_000, MAX_TOKEN_AMOUNT);
        collateralRequired_ = constrictToRange(collateralRequired_, 0,         principalRequested_ / 10);    
        
        ( loan, debtLocker ) = _createFundAndDrawdownLoan(principalRequested_);

        // Mint collateral into loan, representing 10x value since market value is $10
        collateralAsset.mint(address(loan), collateralRequired_);

        /**********************/
        /*** Make a payment ***/
        /**********************/

        ( uint256 principal, uint256 interest, uint256 fees ) = loan.getNextPaymentsBreakDown(1);

        uint256 total = principal + interest + fees;

        // Mock a payment amount with interest and principal
        fundsAsset.mint(address(this),    total);
        fundsAsset.approve(address(loan), total);  // Mock payment amount

        loan.makePayments(1, total);

        /*************************************/
        /*** Trigger default and liquidate ***/
        /*************************************/

        assertEq(collateralAsset.balanceOf(address(loan)),       collateralRequired_);
        assertEq(collateralAsset.balanceOf(address(debtLocker)), 0);
        assertEq(fundsAsset.balanceOf(address(loan)),            total);
        assertEq(fundsAsset.balanceOf(address(debtLocker)),      0);
        assertEq(fundsAsset.balanceOf(address(pool)),            0);
        assertTrue(!debtLocker.repossessed());

        hevm.warp(loan.nextPaymentDueDate() + loan.gracePeriod() + 1);

        try pool.triggerDefault(address(debtLocker)) { assertTrue(false, "Cannot liquidate with claimableFunds"); } catch { }

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
        assertEq(fundsAsset.balanceOf(address(pool)),            total);
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
        assertEq(fundsAsset.balanceOf(address(pool)),            total);

        uint256[7] memory details = pool.claim(address(debtLocker));

        assertEq(fundsAsset.balanceOf(address(debtLocker)), 0);
        assertEq(fundsAsset.balanceOf(address(pool)),       total + amountRecovered);
        assertTrue(!debtLocker.repossessed());

        assertEq(details[0], amountRecovered);                     // Total amount of funds claimed
        assertEq(details[1], 0);                                   // Interest is zero since all funds go towards principal in a shortfall
        assertEq(details[2], amountRecovered);                     // All funds are registered as principal in a shortfall
        assertEq(details[3], 0);                                   // `feePaid` is always zero since PD establishment fees are paid in `fundLoan` now
        assertEq(details[4], 0);                                   // `excessReturned` is always zero since new loans cannot be over-funded
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
        ( loan, debtLocker ) = _createFundAndDrawdownLoan(principalRequested_);

        // Mint collateral into loan, representing 10x value since market value is $10
        collateralAsset.mint(address(loan), collateralRequired);

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

        hevm.warp(loan.nextPaymentDueDate() + loan.gracePeriod() + 1);

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
        assertEq(details[3], 0);                // `feePaid` is always zero since PD establishment fees are paid in `fundLoan` now
        assertEq(details[4], 0);                // `excessReturned` is always zero since new loans cannot be over-funded
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
        ( loan, debtLocker ) = _createFundAndDrawdownLoan(principalRequested_);

        // Mint collateral into loan, representing 10x value since market value is $10
        collateralAsset.mint(address(loan), collateralRequired);

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

        hevm.warp(loan.nextPaymentDueDate() + loan.gracePeriod() + 1);

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
        assertEq(details[3], 0);                                   // `feePaid` is always zero since PD establishment fees are paid in `fundLoan` now
        assertEq(details[4], 0);                                   // `excessReturned` is always zero since new loans cannot be over-funded
        assertEq(details[5], amountRecovered);                     // Total recovered from liquidation
        assertEq(details[6], 0);                                   // Zero shortfall since principalToCover == amountRecovered
    }

    function test_setAllowedSlippage() external {
        loan = _createLoan(1_000_000);

        debtLocker = DebtLocker(pool.createDebtLocker(address(dlFactory), address(loan)));

        assertEq(debtLocker.allowedSlippage(), 0);

        assertTrue(!notPoolDelegate.try_debtLocker_setAllowedSlippage(address(debtLocker), 100));  // Non-PD can't set
        assertTrue(    poolDelegate.try_debtLocker_setAllowedSlippage(address(debtLocker), 100));  // PD can set

        assertEq(debtLocker.allowedSlippage(), 100);
    }

    function test_setAuctioneer() external {
        ( loan, debtLocker ) = _createFundAndDrawdownLoan(1_000_000);

        // Mint collateral into loan so that liquidator gets deployed
        collateralAsset.mint(address(loan), 1000);

        hevm.warp(loan.nextPaymentDueDate() + loan.gracePeriod() + 1);

        pool.triggerDefault(address(debtLocker));

        assertEq(ILiquidatorLike(debtLocker.liquidator()).auctioneer(), address(debtLocker));

        assertTrue(!notPoolDelegate.try_debtLocker_setAuctioneer(address(debtLocker), address(1)));  // Non-PD can't set
        assertTrue(    poolDelegate.try_debtLocker_setAuctioneer(address(debtLocker), address(1)));  // PD can set

        assertEq(ILiquidatorLike(debtLocker.liquidator()).auctioneer(), address(1));
    }

    function test_setMinRatio() external {
        loan = _createLoan(1_000_000);

        debtLocker = DebtLocker(pool.createDebtLocker(address(dlFactory), address(loan)));

        assertEq(debtLocker.minRatio(), 0);

        assertTrue(!notPoolDelegate.try_debtLocker_setMinRatio(address(debtLocker), 100 * 10 ** 6));  // Non-PD can't set
        assertTrue(    poolDelegate.try_debtLocker_setMinRatio(address(debtLocker), 100 * 10 ** 6));  // PD can set

        assertEq(debtLocker.minRatio(), 100 * 10 ** 6);
    }

    function test_refinance_withAmountIncrease(uint256 principalRequested_, uint256 principalIncrease_) external {
        principalRequested_ = constrictToRange(principalRequested_, 1_000_000, MAX_TOKEN_AMOUNT) / 10 * 10;
        principalIncrease_  = constrictToRange(principalIncrease_, 1, 1e12);
        
        /**********************************/
        /*** Create Loan and DebtLocker ***/
        /**********************************/


        loan = new MockLoan(principalRequested_, address(fundsAsset), address(collateralAsset));

        DebtLocker debtLocker = DebtLocker(pool.createDebtLocker(address (dlFactory), abi.encode(address(loan), address(pool))));

        loan.setLender(address(debtLocker));

        /**********************/
        /*** Make a payment ***/
        /**********************/

        uint256 paymentAmount     = principalRequested_ / 10;
        uint256 interestAmount    = principalRequested_ / 20;
        uint256 principalPortion_ = paymentAmount - interestAmount;

        fundsAsset.mint(address(this),    paymentAmount);
        fundsAsset.approve(address(loan), paymentAmount);

        loan.makePayment(principalPortion_, interestAmount);

        /******************/
        /*** Refinance ***/
        /****************/

        address refinancer  = address(2);
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("increasePrincipal(uint256)", principalIncrease_);

        loan.setProposedNewTermsHash(keccak256(abi.encode(refinancer, data)));

        fundsAsset.mint(address(debtLocker), principalIncrease_);

        // should fail due to pending claim
        try debtLocker.acceptNewTerms(refinancer, data, true) { fail(); } catch { }

        pool.claim(address(debtLocker));

        uint256 principalBefore = loan.principal();

        debtLocker.acceptNewTerms(refinancer, data, true);

        uint256 principalAfter = loan.principal();

        assertEq(principalBefore + principalIncrease_, principalAfter);
    }

}
