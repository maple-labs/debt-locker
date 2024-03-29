// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { TestUtils }            from "../modules/contract-test-utils/contracts/test.sol";
import { MockERC20 }            from "../modules/erc20/contracts/test/mocks/MockERC20.sol";
import { MapleLoan }            from "../modules/loan/contracts/MapleLoan.sol";
import { MapleLoanFactory }     from "../modules/loan/contracts/MapleLoanFactory.sol";
import { MapleLoanInitializer } from "../modules/loan/contracts/MapleLoanInitializer.sol";
import { Refinancer }           from "../modules/loan/contracts/Refinancer.sol";

import { ILiquidatorLike } from "../contracts/interfaces/Interfaces.sol";

import { DebtLocker }            from "../contracts/DebtLocker.sol";
import { DebtLockerFactory }     from "../contracts/DebtLockerFactory.sol";
import { DebtLockerInitializer } from "../contracts/DebtLockerInitializer.sol";
import { DebtLockerV4Migrator }  from "../contracts/DebtLockerV4Migrator.sol";

import { GlobalAdmin }  from "./accounts/GlobalAdmin.sol";
import { Governor }     from "./accounts/Governor.sol";
import { PoolDelegate } from "./accounts/PoolDelegate.sol";
import { LoanMigrator } from "./accounts/LoanMigrator.sol";

import { DebtLockerHarness }       from "./mocks/DebtLockerHarness.sol";
import { ManipulatableDebtLocker } from "./mocks/ManipulatableDebtLocker.sol";
import {
    MockGlobals,
    MockLiquidationStrategy,
    MockLoan,
    MockMigrator,
    MockPool,
    MockPoolFactory
} from "./mocks/Mocks.sol";

interface Hevm {

    // Sets block timestamp to `x`.
    function warp(uint256 x) external view;

    function expectRevert(bytes calldata) external;

}

contract DebtLockerTests is TestUtils {

    DebtLockerFactory    internal dlFactory;
    GlobalAdmin          internal globalAdmin;
    GlobalAdmin          internal notGlobalAdmin;
    Governor             internal governor;
    MapleLoanFactory     internal loanFactory;
    MapleLoanInitializer internal loanInitializer;
    MockERC20            internal collateralAsset;
    MockERC20            internal fundsAsset;
    MockGlobals          internal globals;
    MockPool             internal pool;
    MockPoolFactory      internal poolFactory;
    PoolDelegate         internal notPoolDelegate;
    PoolDelegate         internal poolDelegate;

    Hevm internal hevm = Hevm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    uint256 internal constant MAX_TOKEN_AMOUNT = 1e12 * 1e18;

    function setUp() external {
        globalAdmin     = new GlobalAdmin();
        governor        = new Governor();
        notGlobalAdmin  = new GlobalAdmin();
        notPoolDelegate = new PoolDelegate();
        poolDelegate    = new PoolDelegate();

        globals     = new MockGlobals(address(governor));
        poolFactory = new MockPoolFactory(address(globals));
        dlFactory   = new DebtLockerFactory(address(globals));
        loanFactory = new MapleLoanFactory(address(globals));

        pool = MockPool(poolFactory.createPool(address(poolDelegate)));

        collateralAsset = new MockERC20("Collateral Asset", "CA", 18);
        fundsAsset      = new MockERC20("Funds Asset",      "FA", 18);

        globals.setValidCollateralAsset(address(collateralAsset), true);
        globals.setValidLiquidityAsset(address(fundsAsset), true);
        globals.setGlobalAdmin(address(globalAdmin));

        // Deploying and registering DebtLocker implementation and initializer
        address debtLockerImplementation = address(new DebtLocker());
        address debtLockerInitializer    = address(new DebtLockerInitializer());

        // Deploying and registering DebtLocker implementation and initializer
        address loanImplementation = address(new MapleLoan());
        loanInitializer            = new MapleLoanInitializer();

        governor.mapleProxyFactory_registerImplementation(address(dlFactory), 1, debtLockerImplementation, debtLockerInitializer);
        governor.mapleProxyFactory_setDefaultVersion(address(dlFactory), 1);

        governor.mapleProxyFactory_registerImplementation(address(loanFactory), 1, loanImplementation, address(loanInitializer));
        governor.mapleProxyFactory_setDefaultVersion(address(loanFactory), 1);

        globals.setPrice(address(collateralAsset), 10 * 10 ** 8);  // 10 USD
        globals.setPrice(address(fundsAsset),      1  * 10 ** 8);  // 1 USD
    }

    function _createLoan(uint256 principalRequested_, uint256 collateralRequired_) internal returns (MapleLoan loan_) {
        address[2] memory assets      = [address(collateralAsset), address(fundsAsset)];
        uint256[3] memory termDetails = [uint256(10 days), uint256(30 days), 6];
        uint256[3] memory amounts     = [collateralRequired_, principalRequested_, 0];
        uint256[4] memory rates       = [uint256(0.10e18), uint256(0), uint256(0), uint256(0)];

        bytes memory arguments = loanInitializer.encodeArguments(address(this), assets, termDetails, amounts, rates);
        bytes32 salt           = keccak256(abi.encodePacked("salt"));

        // Create Loan
        loan_ = MapleLoan(loanFactory.createInstance(arguments, salt));
    }

    function _fundAndDrawdownLoan(address loan_, address debtLocker_) internal {
        MapleLoan loan = MapleLoan(loan_);

        uint256 principalRequested = loan.principalRequested();
        uint256 collateralRequired = loan.collateralRequired();

        fundsAsset.mint(address(this), principalRequested);
        fundsAsset.approve(loan_,      principalRequested);

        loan.fundLoan(debtLocker_, principalRequested);

        collateralAsset.mint(address(this), collateralRequired);
        collateralAsset.approve(loan_,      collateralRequired);

        loan.drawdownFunds(loan.drawableFunds(), address(1));  // Drawdown to empty funds from loan
    }

    function _createFundAndDrawdownLoan(uint256 principalRequested_, uint256 collateralRequired_) internal returns (MapleLoan loan_, DebtLocker debtLocker_) {
        loan_ = _createLoan(principalRequested_, collateralRequired_);

        debtLocker_ = DebtLocker(pool.createDebtLocker(address(dlFactory), address(loan_)));

        _fundAndDrawdownLoan(address(loan_), address(debtLocker_));
    }

    /*******************/
    /*** Claim Tests ***/
    /*******************/

    function test_claim(uint256 principalRequested_, uint256 collateralRequired_) external {

        /**********************************/
        /*** Create Loan and DebtLocker ***/
        /**********************************/

        principalRequested_ = constrictToRange(principalRequested_, 1_000_000, MAX_TOKEN_AMOUNT);
        collateralRequired_ = constrictToRange(collateralRequired_, 0,         MAX_TOKEN_AMOUNT);

        ( MapleLoan loan, DebtLocker debtLocker ) = _createFundAndDrawdownLoan(principalRequested_, collateralRequired_);

        /*************************/
        /*** Make two payments ***/
        /*************************/
        {
            ( uint256 principal1, uint256 interest1, uint256 delegateFee, uint256 treasuryFee ) = loan.getNextPaymentBreakdown();

            uint256 total1 = principal1 + interest1 + delegateFee + treasuryFee;

            // Make a payment amount with interest and principal
            fundsAsset.mint(address(this),    total1);
            fundsAsset.approve(address(loan), total1);  // Mock payment amount

            loan.makePayment(total1);

            uint256 principal2;
            uint256 interest2;

            ( principal2, interest2, delegateFee, treasuryFee ) = loan.getNextPaymentBreakdown();

            uint256 total2 = principal2 + interest2 + delegateFee + treasuryFee;

            // Mock a second payment amount with interest and principal
            fundsAsset.mint(address(this),    total2);
            fundsAsset.approve(address(loan), total2);  // Mock payment amount

            loan.makePayment(total2);

            uint256 totalPayments = (total1 + total2) - (delegateFee + treasuryFee) * 2;

            assertEq(fundsAsset.balanceOf(address(loan)), totalPayments);
            assertEq(fundsAsset.balanceOf(address(pool)), 0);

            assertEq(debtLocker.principalRemainingAtLastClaim(), loan.principalRequested());

            uint256[7] memory details = pool.claim(address(debtLocker));

            assertEq(fundsAsset.balanceOf(address(loan)), 0);
            assertEq(fundsAsset.balanceOf(address(pool)), totalPayments);

            assertEq(debtLocker.principalRemainingAtLastClaim(), loan.principal());

            assertEq(details[0], totalPayments);  // Total amount of funds claimed
            assertEq(details[1], interest1 + interest2);   // Excess funds go towards interest
            assertEq(details[2], principal1 + principal2);  // Principal amount
            assertEq(details[3], 0);              // `feePaid` is always zero since PD establishment fees are paid in `fundLoan` now
            assertEq(details[4], 0);              // `excessReturned` is always zero since new loans cannot be over-funded
            assertEq(details[5], 0);              // Total recovered from liquidation is zero
            assertEq(details[6], 0);              // Zero shortfall since no liquidation
        }

        /*************************/
        /*** Make last payment ***/
        /*************************/

        {
            ( uint256 principal3, uint256 interest3, uint256 delegateFee, uint256 treasuryFee ) = loan.getNextPaymentBreakdown();

            uint256 total3 = principal3 + interest3 + delegateFee + treasuryFee;

            // Make a payment amount with interest and principal
            fundsAsset.mint(address(this),    total3);
            fundsAsset.approve(address(loan), total3);  // Mock payment amount

            // Reduce the principal in loan and set claimableFunds
            loan.makePayment(total3);

            uint256 poolBal = fundsAsset.balanceOf(address(pool));

            uint256[7] memory details = pool.claim(address(debtLocker));

            assertEq(fundsAsset.balanceOf(address(pool)), poolBal + interest3 + principal3);

            assertEq(details[0], total3 - delegateFee - treasuryFee);  // Total amount of funds claimed
            assertEq(details[1], interest3);                           // Excess funds go towards interest
            assertEq(details[2], principal3);                          // Principal amount
            assertEq(details[3], 0);                                   // `feePaid` is always zero since PD establishment fees are paid in `fundLoan` now
            assertEq(details[4], 0);                                   // `excessReturned` is always zero since new loans cannot be over-funded
            assertEq(details[5], 0);                                   // Total recovered from liquidation is zero
            assertEq(details[6], 0);                                   // Zero shortfall since no liquidation
        }
    }

    function test_initialize_invalidCollateralAsset() external {
        MapleLoan loan = _createLoan(1_000_000, 300_000);

        assertTrue(globals.isValidCollateralAsset(loan.collateralAsset()));

        globals.setValidCollateralAsset(loan.collateralAsset(), false);

        assertTrue(!globals.isValidCollateralAsset(loan.collateralAsset()));

        try pool.createDebtLocker(address(dlFactory), address(loan)) { assertTrue(false, "Able to create DL with invalid collateralAsset"); } catch { }

        globals.setValidCollateralAsset(loan.collateralAsset(), true);

        assertTrue(pool.createDebtLocker(address(dlFactory), address(loan)) != address(0));
    }

    function test_initialize_invalidLiquidityAsset() external {
        MapleLoan loan = _createLoan(1_000_000, 300_000);

        assertTrue(globals.isValidLiquidityAsset(loan.fundsAsset()));

        globals.setValidLiquidityAsset(loan.fundsAsset(), false);

        assertTrue(!globals.isValidLiquidityAsset(loan.fundsAsset()));

        try pool.createDebtLocker(address(dlFactory), address(loan)) { assertTrue(false, "Able to create DL with invalid fundsAsset"); } catch { }

        globals.setValidLiquidityAsset(loan.fundsAsset(), true);

        assertTrue(pool.createDebtLocker(address(dlFactory), address(loan)) != address(0));
    }

    function test_claim_liquidation_shortfall(uint256 principalRequested_, uint256 collateralRequired_) external {

        /**********************************/
        /*** Create Loan and DebtLocker ***/
        /**********************************/

        principalRequested_ = constrictToRange(principalRequested_, 1_000_000, MAX_TOKEN_AMOUNT);
        collateralRequired_ = constrictToRange(collateralRequired_, 0,         principalRequested_ / 12);

        ( MapleLoan loan, DebtLocker debtLocker ) = _createFundAndDrawdownLoan(principalRequested_, collateralRequired_);

        /**********************/
        /*** Make a payment ***/
        /**********************/

        ( uint256 principal, uint256 interest, uint256 delegateFee, uint256 treasuryFee ) = loan.getNextPaymentBreakdown();

        uint256 total        = principal + interest + delegateFee + treasuryFee;
        uint256 totalPayment = principal + interest;

        // Make a payment amount with interest and principal
        fundsAsset.mint(address(this),    total);
        fundsAsset.approve(address(loan), total);  // Mock payment amount

        loan.makePayment(total);

        /*************************************/
        /*** Trigger default and liquidate ***/
        /*************************************/

        assertEq(collateralAsset.balanceOf(address(loan)),       collateralRequired_);
        assertEq(collateralAsset.balanceOf(address(debtLocker)), 0);
        assertEq(fundsAsset.balanceOf(address(loan)),            totalPayment);
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
        assertEq(fundsAsset.balanceOf(address(pool)),            totalPayment);
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
        assertEq(fundsAsset.balanceOf(address(pool)),            totalPayment);

        uint256[7] memory details = pool.claim(address(debtLocker));

        assertEq(fundsAsset.balanceOf(address(debtLocker)), 0);
        assertEq(fundsAsset.balanceOf(address(pool)),       totalPayment + amountRecovered);
        assertTrue(!debtLocker.repossessed());

        assertEq(details[0], amountRecovered);                     // Total amount of funds claimed
        assertEq(details[1], 0);                                   // Interest is zero since all funds go towards principal in a shortfall
        assertEq(details[2], 0);                                   // Principal is not registered in liquidation, covered by details[5]
        assertEq(details[3], 0);                                   // `feePaid` is always zero since PD establishment fees are paid in `fundLoan` now
        assertEq(details[4], 0);                                   // `excessReturned` is always zero since new loans cannot be over-funded
        assertEq(details[5], amountRecovered);                     // Total recovered from liquidation
        assertEq(details[6], principalToCover - amountRecovered);  // Shortfall to be covered by burning BPTs
    }

    function test_claim_liquidation_equalToPrincipal(uint256 principalRequested_) external {

        /*************************/
        /*** Set up parameters ***/
        /*************************/

        // Round to nearest tenth so no rounding error for collateral
        principalRequested_ = constrictToRange(principalRequested_, 1_000_000, MAX_TOKEN_AMOUNT) / 10 * 10;
        uint256 collateralRequired = principalRequested_ / 10;  // Amount recovered equal to principal to cover

        /**********************************/
        /*** Create Loan and DebtLocker ***/
        /**********************************/

        ( MapleLoan loan, DebtLocker debtLocker ) = _createFundAndDrawdownLoan(principalRequested_, collateralRequired);

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
        assertEq(details[2], 0);                // Principal is not registered in liquidation, covered by details[5]
        assertEq(details[3], 0);                // `feePaid` is always zero since PD establishment fees are paid in `fundLoan` now
        assertEq(details[4], 0);                // `excessReturned` is always zero since new loans cannot be over-funded
        assertEq(details[5], amountRecovered);  // Total recovered from liquidation
        assertEq(details[6], 0);                // Zero shortfall since principalToCover == amountRecovered
    }

    function test_claim_liquidation_greaterThanPrincipal(uint256 principalRequested_, uint256 excessRecovered_) external {

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

        ( MapleLoan loan, DebtLocker debtLocker ) = _createFundAndDrawdownLoan(principalRequested_, collateralRequired);

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
        assertEq(details[2], 0);                                   // Principal is not registered in liquidation, covered by details[5]
        assertEq(details[3], 0);                                   // `feePaid` is always zero since PD establishment fees are paid in `fundLoan` now
        assertEq(details[4], 0);                                   // `excessReturned` is always zero since new loans cannot be over-funded
        assertEq(details[5], principalToCover);                    // Total recovered from liquidation
        assertEq(details[6], 0);                                   // Zero shortfall since principalToCover == amountRecovered
    }

    function test_liquidation_dos_prevention(uint256 principalRequested_, uint256 collateralRequired_) external {

        /**********************************/
        /*** Create Loan and DebtLocker ***/
        /**********************************/

        principalRequested_ = constrictToRange(principalRequested_, 1_000_000, MAX_TOKEN_AMOUNT);
        collateralRequired_ = constrictToRange(collateralRequired_, 1,         principalRequested_ / 10);  // Need collateral for liquidator deployment

        ( MapleLoan loan, DebtLocker debtLocker ) = _createFundAndDrawdownLoan(principalRequested_, collateralRequired_);

        /*************************************/
        /*** Trigger default and liquidate ***/
        /*************************************/

        hevm.warp(loan.nextPaymentDueDate() + loan.gracePeriod() + 1);

        pool.triggerDefault(address(debtLocker));

        address liquidator = debtLocker.liquidator();

        if (collateralRequired_ > 0) {
            MockLiquidationStrategy mockLiquidationStrategy = new MockLiquidationStrategy();
            mockLiquidationStrategy.flashBorrowLiquidation(liquidator, collateralRequired_, address(collateralAsset), address(fundsAsset));
        }

        assertTrue(collateralAsset.balanceOf(liquidator) == 0);  // _isLiquidationActive == false

        // Mint 1 wei of collateralAsset into liquidator, simulating DoS attack
        // Attacker could frontrun PD claim and continue to transfer small amounts into the liquidator
        collateralAsset.mint(liquidator, 1);

        assertTrue(collateralAsset.balanceOf(liquidator) > 0);  // _isLiquidationActive == true

        try pool.claim(address(debtLocker)) { assertTrue(false, "Able to claim while _isLiquidationActive == true"); } catch { }

        assertTrue(debtLocker.liquidator() != address(0));  // _isLiquidationActive == true

        assertTrue(!notPoolDelegate.try_debtLocker_stopLiquidation(address(debtLocker)));  // Non-PD can't call
        assertTrue(    poolDelegate.try_debtLocker_stopLiquidation(address(debtLocker)));  // PD can call

        assertTrue(debtLocker.liquidator() == address(0));  // _isLiquidationActive == false

        pool.claim(address(debtLocker));  // Can successfully claim
    }

    function test_liquidation_pullFunds(uint256 principalRequested_, uint256 collateralRequired_) external {

        /**********************************/
        /*** Create Loan and DebtLocker ***/
        /**********************************/

        principalRequested_ = constrictToRange(principalRequested_, 1_000_000, MAX_TOKEN_AMOUNT);
        collateralRequired_ = constrictToRange(collateralRequired_, 1,         principalRequested_ / 10);  // Need collateral for liquidator deployment

        ( MapleLoan loan, DebtLocker debtLocker ) = _createFundAndDrawdownLoan(principalRequested_, collateralRequired_);

        /*************************************/
        /*** Trigger default and liquidate ***/
        /*************************************/

        hevm.warp(loan.nextPaymentDueDate() + loan.gracePeriod() + 1);

        pool.triggerDefault(address(debtLocker));

        address liquidator = debtLocker.liquidator();

        assertEq(collateralAsset.balanceOf(address(this)),       0);
        assertEq(collateralAsset.balanceOf(address(liquidator)), collateralRequired_);

        assertTrue(!notPoolDelegate.try_debtLocker_pullFunds(address(debtLocker), address(liquidator), address(collateralAsset), address(this), collateralRequired_));
        assertTrue(    poolDelegate.try_debtLocker_pullFunds(address(debtLocker), address(liquidator), address(collateralAsset), address(this), collateralRequired_));

        assertEq(collateralAsset.balanceOf(address(this)),       collateralRequired_);
        assertEq(collateralAsset.balanceOf(address(liquidator)), 0);
    }

    /****************************/
    /*** Access Control Tests ***/
    /****************************/

    function test_acl_factory_migrate() external {
        MockLoan mockLoan = new MockLoan();

        ManipulatableDebtLocker debtLocker = new ManipulatableDebtLocker(address(mockLoan), address(pool), address(dlFactory));

        address migrator = address(new MockMigrator());

        try debtLocker.migrate(address(migrator), abi.encode(0)) { assertTrue(false, "Non-factory calling migrate"); } catch { }

        assertEq(debtLocker.factory(), address(dlFactory));

        debtLocker.setFactory(address(this));

        assertEq(debtLocker.factory(), address(this));

        debtLocker.migrate(address(migrator), abi.encode(0));
    }

    function test_acl_factory_setImplementation() external {
        MockLoan mockLoan = new MockLoan();

        ManipulatableDebtLocker debtLocker = new ManipulatableDebtLocker(address(mockLoan), address(pool), address(dlFactory));

        try debtLocker.setImplementation(address(1)) { assertTrue(false, "Non-factory calling setImplementation"); } catch { }

        assertEq(debtLocker.factory(), address(dlFactory));

        debtLocker.setFactory(address(this));

        assertEq(debtLocker.factory(),        address(this));
        assertEq(debtLocker.implementation(), address(0));

        debtLocker.setImplementation(address(1));
    }

    function test_acl_poolDelegate_setAllowedSlippage() external {
        MapleLoan loan = _createLoan(1_000_000, 30_000);

        DebtLocker debtLocker = DebtLocker(pool.createDebtLocker(address(dlFactory), address(loan)));

        assertEq(debtLocker.allowedSlippage(), 0);

        assertTrue(!notPoolDelegate.try_debtLocker_setAllowedSlippage(address(debtLocker), 100));  // Non-PD can't set
        assertTrue(    poolDelegate.try_debtLocker_setAllowedSlippage(address(debtLocker), 100));  // PD can set

        assertEq(debtLocker.allowedSlippage(), 100);
    }

    function test_acl_poolDelegate_setAuctioneer() external {
        ( MapleLoan loan, DebtLocker debtLocker ) = _createFundAndDrawdownLoan(1_000_000, 30_000);

        // Mint collateral into loan so that liquidator gets deployed
        collateralAsset.mint(address(loan), 1000);

        hevm.warp(loan.nextPaymentDueDate() + loan.gracePeriod() + 1);

        pool.triggerDefault(address(debtLocker));

        assertEq(ILiquidatorLike(debtLocker.liquidator()).auctioneer(), address(debtLocker));

        assertTrue(!notPoolDelegate.try_debtLocker_setAuctioneer(address(debtLocker), address(1)));  // Non-PD can't set
        assertTrue(    poolDelegate.try_debtLocker_setAuctioneer(address(debtLocker), address(1)));  // PD can set

        assertEq(ILiquidatorLike(debtLocker.liquidator()).auctioneer(), address(1));
    }

    function test_acl_poolDelegate_setFundsToCapture() external {
        MapleLoan loan = _createLoan(1_000_000, 30_000);

        DebtLocker debtLocker = DebtLocker(pool.createDebtLocker(address(dlFactory), address(loan)));

        assertEq(debtLocker.fundsToCapture(), 0);

        assertTrue(!notPoolDelegate.try_debtLocker_setFundsToCapture(address(debtLocker), 100 * 10 ** 6));  // Non-PD can't set
        assertTrue(    poolDelegate.try_debtLocker_setFundsToCapture(address(debtLocker), 100 * 10 ** 6));  // PD can set

        assertEq(debtLocker.fundsToCapture(), 100 * 10 ** 6);
    }

    function test_acl_poolDelegate_setMinRatio() external {
        MapleLoan loan = _createLoan(1_000_000, 30_000);

        DebtLocker debtLocker = DebtLocker(pool.createDebtLocker(address(dlFactory), address(loan)));

        assertEq(debtLocker.minRatio(), 0);

        assertTrue(!notPoolDelegate.try_debtLocker_setMinRatio(address(debtLocker), 100 * 10 ** 6));  // Non-PD can't set
        assertTrue(    poolDelegate.try_debtLocker_setMinRatio(address(debtLocker), 100 * 10 ** 6));  // PD can set

        assertEq(debtLocker.minRatio(), 100 * 10 ** 6);
    }

    function test_acl_globalAdmin_upgrade() external {
        MapleLoan loan = _createLoan(1_000_000, 30_000);

        DebtLocker debtLocker = DebtLocker(pool.createDebtLocker(address(dlFactory), address(loan)));

        // Deploying and registering DebtLocker implementation and initializer
        address implementationV2 = address(new DebtLocker());
        address initializerV2    = address(new DebtLockerInitializer());

        governor.mapleProxyFactory_registerImplementation(address(dlFactory), 2, implementationV2, initializerV2);
        governor.mapleProxyFactory_enableUpgradePath(address(dlFactory), 1, 2, address(0));

        assertTrue(dlFactory.implementationOf(1) != dlFactory.implementationOf(2));

        assertEq(debtLocker.implementation(), dlFactory.implementationOf(1));

        bytes memory arguments = new bytes(0);

        assertTrue(!notGlobalAdmin.try_debtLocker_upgrade(address(debtLocker), 2, arguments));  // Non-GA can't set
        assertTrue(    globalAdmin.try_debtLocker_upgrade(address(debtLocker), 2, arguments));  // GA can set

        assertEq(debtLocker.implementation(), dlFactory.implementationOf(2));
    }

    function test_acl_poolDelegate_acceptNewTerms() external {
        ( MapleLoan loan, DebtLocker debtLocker ) = _createFundAndDrawdownLoan(1_000_000, 30_000);

        address refinancer = address(new Refinancer());
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("setEarlyFeeRate(uint256)", 100);

        uint256 deadline = block.timestamp + 1;

        loan.proposeNewTerms(refinancer, deadline, data);  // address(this) is borrower

        assertEq(loan.earlyFeeRate(), 0);

        assertTrue(!notPoolDelegate.try_debtLocker_acceptNewTerms(address(debtLocker), refinancer, deadline, data, 0));  // Non-PD can't set
        assertTrue(    poolDelegate.try_debtLocker_acceptNewTerms(address(debtLocker), refinancer, deadline, data, 0));  // PD can set

        assertEq(loan.earlyFeeRate(), 100);
    }

    function test_acl_poolDelegate_rejectNewTerms() external {
        ( MapleLoan loan, DebtLocker debtLocker ) = _createFundAndDrawdownLoan(1_000_000, 30_000);

        address refinancer = address(new Refinancer());
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("setEarlyFeeRate(uint256)", 100);

        uint256 deadline = block.timestamp + 1;

        loan.proposeNewTerms(refinancer, deadline, data);  // address(this) is borrower

        assertTrue(loan.refinanceCommitment() != bytes32(0));

        assertTrue(!notPoolDelegate.try_debtLocker_rejectNewTerms(address(debtLocker), refinancer, deadline, data));  // Non-PD can't set
        assertTrue(    poolDelegate.try_debtLocker_rejectNewTerms(address(debtLocker), refinancer, deadline, data));  // PD can set

        assertTrue(loan.refinanceCommitment() == bytes32(0));
    }

    function test_acl_pool_claim() external {
        MapleLoan loan = _createLoan(1_000_000, 30_000);

        ManipulatableDebtLocker debtLocker = new ManipulatableDebtLocker(address(loan), address(pool), address(dlFactory));

        _fundAndDrawdownLoan(address(loan), address(debtLocker));

        ( uint256 principal1, uint256 interest1, uint256 delegateFee1, uint256 treasuryFee1 ) = loan.getNextPaymentBreakdown();

        uint256 total1 = principal1 + interest1 + delegateFee1 + treasuryFee1;

        // Make a payment amount with interest and principal
        fundsAsset.mint(address(this),    total1);
        fundsAsset.approve(address(loan), total1);  // Mock payment amount

        loan.makePayment(total1);

        debtLocker.setPool(address(1));

        try pool.claim(address(debtLocker)) { assertTrue(false, "Non-pool able to claim"); } catch { }

        debtLocker.setPool(address(pool));

        pool.claim(address(debtLocker));
    }

    function test_acl_pool_triggerDefault() external {
        MapleLoan loan = _createLoan(1_000_000, 30_000);

        ManipulatableDebtLocker debtLocker = new ManipulatableDebtLocker(address(loan), address(pool), address(dlFactory));

        _fundAndDrawdownLoan(address(loan), address(debtLocker));

        hevm.warp(loan.nextPaymentDueDate() + loan.gracePeriod() + 1);

        debtLocker.setPool(address(1));

        try pool.triggerDefault(address(debtLocker)) { assertTrue(false, "Non-pool able to triggerDefault"); } catch { }

        debtLocker.setPool(address(pool));

        pool.triggerDefault(address(debtLocker));
    }

    /******************************/
    /*** Input Validation Tests ***/
    /******************************/

    function test_setAllowedSlippage_invalidSlippage() external {
        MapleLoan loan = _createLoan(1_000_000, 30_000);

        DebtLocker debtLocker = DebtLocker(pool.createDebtLocker(address(dlFactory), address(loan)));

        assertTrue(!poolDelegate.try_debtLocker_setAllowedSlippage(address(debtLocker), 10_001));
        assertTrue( poolDelegate.try_debtLocker_setAllowedSlippage(address(debtLocker), 10_000));
    }

    /***********************/
    /*** Refinance Tests ***/
    /***********************/

    function test_acceptNewTerms_withAmountIncrease(uint256 principalIncrease_) external {
        principalIncrease_  = constrictToRange(principalIncrease_, 1, 1_000_000);

        /**********************************/
        /*** Create Loan and DebtLocker ***/
        /**********************************/

        ( MapleLoan loan, DebtLocker debtLocker ) = _createFundAndDrawdownLoan(1_000_000, 100_000);

        /**********************/
        /*** Make a payment ***/
        /**********************/

        ( uint256 principal, uint256 interest, uint256 delegateFee, uint256 treasuryFee ) = loan.getNextPaymentBreakdown();

        {
            uint256 total = principal + interest + delegateFee + treasuryFee;

            // Make a payment amount with interest and principal
            fundsAsset.mint(address(this),    total);
            fundsAsset.approve(address(loan), total);  // Mock payment amount

            loan.makePayment(total);
        }

        /*****************/
        /*** Refinance ***/
        /*****************/

        address refinancer  = address(new Refinancer());
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("increasePrincipal(uint256)", principalIncrease_);

        loan.proposeNewTerms(refinancer, block.timestamp, data);

        fundsAsset.mint(address(debtLocker), principalIncrease_);

        // Should fail due to pending claim
        try debtLocker.acceptNewTerms(refinancer, block.timestamp, data, principalIncrease_) { fail(); } catch { }

        pool.claim(address(debtLocker));

        // Should fail for not pool delegate
        try notPoolDelegate.debtLocker_acceptNewTerms(address(debtLocker), refinancer, block.timestamp, data, principalIncrease_) { fail(); } catch { }

        // Note: More state changes in real loan that are asserted in integration tests
        uint256 principalBefore = loan.principal();

        poolDelegate.debtLocker_acceptNewTerms(address(debtLocker), refinancer, block.timestamp, data, principalIncrease_);

        uint256 principalAfter = loan.principal();

        assertEq(principalBefore + principalIncrease_,       principalAfter);
        assertEq(debtLocker.principalRemainingAtLastClaim(), principalAfter);
    }

    // TODO: test_refinance_withExcessAmount (Will leave in until DoS loan PR is merged and updated as submodule)

    /***************************/
    /*** Funds Capture Tests ***/
    /***************************/

    function test_fundsToCaptureForNextClaim() external {
        ( MapleLoan loan, DebtLocker debtLocker ) = _createFundAndDrawdownLoan(1_000_000, 30_000);

        // Make a payment amount with interest and principal
        ( uint256 principal, uint256 interest, uint256 delegateFee, uint256 treasuryFee ) = loan.getNextPaymentBreakdown();

        fundsAsset.mint(address(loan), principal + interest + delegateFee + treasuryFee);
        loan.makePayment(0);

        // Prepare additional amount to be captured in next claim
        fundsAsset.mint(address(debtLocker), 500_000);
        poolDelegate.debtLocker_setFundsToCapture(address(debtLocker), 500_000);

        assertEq(fundsAsset.balanceOf(address(debtLocker)),  500_000);
        assertEq(fundsAsset.balanceOf(address(pool)),        0);
        assertEq(debtLocker.principalRemainingAtLastClaim(), loan.principalRequested());
        assertEq(debtLocker.fundsToCapture(),                500_000);

        uint256[7] memory details = pool.claim(address(debtLocker));

        assertEq(fundsAsset.balanceOf(address(debtLocker)),  0);
        assertEq(fundsAsset.balanceOf(address(pool)),        principal + interest + 500_000);
        assertEq(debtLocker.principalRemainingAtLastClaim(), loan.principal());
        assertEq(debtLocker.fundsToCapture(),                0);

        assertEq(details[0], principal + interest + 500_000);
        assertEq(details[1], interest);
        assertEq(details[2], principal + 500_000);
        assertEq(details[3], 0);
        assertEq(details[4], 0);
        assertEq(details[5], 0);
        assertEq(details[6], 0);
    }

    function test_fundsToCaptureWhileInDefault() external {
        ( MapleLoan loan, DebtLocker debtLocker ) = _createFundAndDrawdownLoan(1_000_000, 30_000);

        // Prepare additional amount to be captured
        fundsAsset.mint(address(debtLocker), 500_000);

        assertEq(fundsAsset.balanceOf(address(debtLocker)),  500_000);
        assertEq(fundsAsset.balanceOf(address(pool)),        0);
        assertEq(debtLocker.principalRemainingAtLastClaim(), loan.principalRequested());
        assertEq(debtLocker.fundsToCapture(),                0);

        // Trigger default
        hevm.warp(loan.nextPaymentDueDate() + loan.gracePeriod() + 1);

        pool.triggerDefault(address(debtLocker));  // ACL not done in mock pool

        // After triggering default, set funds to capture
        poolDelegate.debtLocker_setFundsToCapture(address(debtLocker), 500_000);

        // Claim
        try pool.claim(address(debtLocker)) { assertTrue(false, "Able to claim during active liquidation"); } catch { }

        MockLiquidationStrategy mockLiquidationStrategy = new MockLiquidationStrategy();

        mockLiquidationStrategy.flashBorrowLiquidation(debtLocker.liquidator(), loan.collateralRequired(), address(collateralAsset), address(fundsAsset));

        uint256[7] memory details = pool.claim(address(debtLocker));

        assertEq(fundsAsset.balanceOf(address(debtLocker)),  0);
        assertEq(fundsAsset.balanceOf(address(pool)),        800_000);
        assertEq(debtLocker.fundsToCapture(),                0);

        assertEq(details[0], 500_000 + 300_000);  // Funds to capture included, with recovered funds (30k at $10)
        assertEq(details[1], 0);
        assertEq(details[2], 500_000);  // Funds to capture accounted as principal
        assertEq(details[3], 0);
        assertEq(details[4], 0);
        assertEq(details[5], 300_000);  // Recovered funds (30k at $10)
        assertEq(details[6], 700_000);  // 300k recovered on a 1m loan
    }

    function testFail_fundsToCaptureForNextClaim() external {
        ( MapleLoan loan, DebtLocker debtLocker ) = _createFundAndDrawdownLoan(1_000_000, 30_000);

        fundsAsset.mint(address(loan), 1_000_000);
        loan.fundLoan(address(debtLocker), 1_000_000);

        // Make a payment amount with interest and principal
        ( uint256 principal, uint256 interest, uint256 delegateFee, uint256 treasuryFee ) = loan.getNextPaymentBreakdown();

        fundsAsset.mint(address(loan), principal + interest + delegateFee + treasuryFee);
        loan.makePayment(principal + interest);

        // Erroneously prepare additional amount to be captured in next claim
        poolDelegate.debtLocker_setFundsToCapture(address(debtLocker), 1);

        assertEq(fundsAsset.balanceOf(address(debtLocker)),  0);
        assertEq(fundsAsset.balanceOf(address(pool)),        0);
        assertEq(debtLocker.principalRemainingAtLastClaim(), loan.principalRequested());
        assertEq(debtLocker.fundsToCapture(),                1);

        pool.claim(address(debtLocker));
    }

    /************************************/
    /*** Internal View Function Tests ***/
    /************************************/

    function _registerDebtLockerHarness() internal {
        // Deploying and registering DebtLocker implementation and initializer
        address implementation = address(new DebtLockerHarness());
        address initializer    = address(new DebtLockerInitializer());

        governor.mapleProxyFactory_registerImplementation(address(dlFactory), 2, implementation, initializer);
        governor.mapleProxyFactory_setDefaultVersion(address(dlFactory), 2);
    }

    function test_getGlobals() external {
        _registerDebtLockerHarness();

        MapleLoan loan = _createLoan(1_000_000, 30_000);

        DebtLockerHarness debtLocker = DebtLockerHarness(pool.createDebtLocker(address(dlFactory), address(loan)));

        assertEq(debtLocker.getGlobals(), address(globals));
    }

    function test_getPoolDelegate() external {
        _registerDebtLockerHarness();

        MapleLoan loan = _createLoan(1_000_000, 30_000);

        DebtLockerHarness debtLocker = DebtLockerHarness(pool.createDebtLocker(address(dlFactory), address(loan)));

        assertEq(debtLocker.poolDelegate(), address(poolDelegate));
    }

    function test_isLiquidationActive() external {
        _registerDebtLockerHarness();

        MapleLoan loan = _createLoan(1_000_000, 30_000);

        DebtLockerHarness debtLocker = DebtLockerHarness(pool.createDebtLocker(address(dlFactory), address(loan)));

        // No liquidator deployed, liquidation not active
        assertTrue(!(debtLocker.liquidator() != address(0)));
        assertTrue(!(collateralAsset.balanceOf(debtLocker.liquidator()) > 0));
        assertTrue(!debtLocker.isLiquidationActive());

        collateralAsset.mint(address(0), 100);  // address(0) can have a balance of collateralAsset on mainnet

        // Zero address has balance of collateralAsset, liquidation not active
        assertTrue(!(debtLocker.liquidator() != address(0)));
        assertTrue( (collateralAsset.balanceOf(debtLocker.liquidator()) > 0));  // address(0) can have a balance of collateralAsset on mainnet
        assertTrue(!debtLocker.isLiquidationActive());

        _fundAndDrawdownLoan(address(loan), address(debtLocker));

        hevm.warp(loan.nextPaymentDueDate() + loan.gracePeriod() + 1);

        pool.triggerDefault(address(debtLocker));

        // Liquidator is deployed, and new liquidator address has a balance, liquidation active
        assertTrue((debtLocker.liquidator() != address(0)));
        assertTrue((collateralAsset.balanceOf(debtLocker.liquidator()) > 0));
        assertTrue(debtLocker.isLiquidationActive());

        // Perform fake liquidation
        MockLiquidationStrategy mockLiquidationStrategy = new MockLiquidationStrategy();

        mockLiquidationStrategy.flashBorrowLiquidation(debtLocker.liquidator(), loan.collateralRequired(), address(collateralAsset), address(fundsAsset));

        // Liquidator is deployed, liquidator has no balance, liquidation finished
        assertTrue( (debtLocker.liquidator() != address(0)));
        assertTrue(!(collateralAsset.balanceOf(debtLocker.liquidator()) > 0));
        assertTrue(!debtLocker.isLiquidationActive());
    }

}

contract DebtLockerV4Migration is TestUtils {

    DebtLockerFactory    internal dlFactory;
    GlobalAdmin          internal globalAdmin;
    GlobalAdmin          internal notGlobalAdmin;
    Governor             internal governor;
    MapleLoanFactory     internal loanFactory;
    MapleLoanInitializer internal loanInitializer;
    MockERC20            internal collateralAsset;
    MockERC20            internal fundsAsset;
    MockGlobals          internal globals;
    MockPool             internal pool;
    MockPoolFactory      internal poolFactory;
    PoolDelegate         internal notPoolDelegate;
    PoolDelegate         internal poolDelegate;

    Hevm internal hevm = Hevm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    function setUp() external {
        globalAdmin     = new GlobalAdmin();
        governor        = new Governor();
        notGlobalAdmin  = new GlobalAdmin();
        notPoolDelegate = new PoolDelegate();
        poolDelegate    = new PoolDelegate();

        globals     = new MockGlobals(address(governor));
        poolFactory = new MockPoolFactory(address(globals));
        dlFactory   = new DebtLockerFactory(address(globals));
        loanFactory = new MapleLoanFactory(address(globals));

        pool = MockPool(poolFactory.createPool(address(poolDelegate)));

        collateralAsset = new MockERC20("Collateral Asset", "CA", 18);
        fundsAsset      = new MockERC20("Funds Asset",      "FA", 18);

        globals.setValidCollateralAsset(address(collateralAsset), true);
        globals.setValidLiquidityAsset(address(fundsAsset), true);
        globals.setGlobalAdmin(address(globalAdmin));

        // Deploying and registering DebtLocker implementation and initializer
        address debtLockerImplementation  = address(new DebtLocker());
        address debtLockerImplementation2 = address(new DebtLocker());
        address debtLockerInitializer     = address(new DebtLockerInitializer());
        address debtLockerV4Migrator      = address(new DebtLockerV4Migrator());

        governor.mapleProxyFactory_registerImplementation(address(dlFactory), 1, debtLockerImplementation, debtLockerInitializer);
        governor.mapleProxyFactory_setDefaultVersion(address(dlFactory), 1);

        governor.mapleProxyFactory_registerImplementation(address(dlFactory), 2, debtLockerImplementation2, debtLockerInitializer);
        governor.mapleProxyFactory_enableUpgradePath(address(dlFactory), 1, 2, debtLockerV4Migrator);

        // Deploying and registering DebtLocker implementation and initializer
        address loanImplementation = address(new MapleLoan());
        loanInitializer            = new MapleLoanInitializer();

        governor.mapleProxyFactory_registerImplementation(address(loanFactory), 1, loanImplementation, address(loanInitializer));
        governor.mapleProxyFactory_setDefaultVersion(address(loanFactory), 1);

        globals.setPrice(address(collateralAsset), 10 * 10 ** 8);  // 10 USD
        globals.setPrice(address(fundsAsset),      1  * 10 ** 8);  // 1 USD
    }

    function test_acl_upgradeToV4() external {
        MapleLoan loan_ = _createLoan(1e18, 1e18);

        DebtLocker debtLocker_ = DebtLocker(pool.createDebtLocker(address(dlFactory), address(loan_)));

        address loanMigrator = address(5);

        assertTrue(!notGlobalAdmin.try_debtLocker_upgrade(address(debtLocker_), 2, abi.encode(loanMigrator)));
        assertTrue(    globalAdmin.try_debtLocker_upgrade(address(debtLocker_), 2, abi.encode(loanMigrator)));

        assertEq(debtLocker_.loanMigrator(), loanMigrator);
    }

    function test_acl_setPendingLender() external {
        ( MapleLoan loan, DebtLocker debtLocker ) = _createFundAndDrawdownLoan(1_000_000, 30_000);

        LoanMigrator loanMigrator    = new LoanMigrator();
        LoanMigrator notLoanMigrator = new LoanMigrator();

        address newLender = address(3);

        globalAdmin.debtLocker_upgrade(address(debtLocker), 2, abi.encode(address(loanMigrator)));

        assertEq(loan.pendingLender(), address(0));

        assertTrue(!notLoanMigrator.try_debtLocker_setPendingLender(address(debtLocker), newLender));
        assertTrue(    loanMigrator.try_debtLocker_setPendingLender(address(debtLocker), newLender));

        assertEq(loan.pendingLender(), newLender);
    }

    function test_acl_acceptLender() external {
        ( , DebtLocker debtLocker ) = _createFundAndDrawdownLoan(1_000_000, 30_000);

        LoanMigrator loanMigrator    = new LoanMigrator();
        LoanMigrator notLoanMigrator = new LoanMigrator();

        globalAdmin.debtLocker_upgrade(address(debtLocker), 2, abi.encode(address(loanMigrator)));

        loanMigrator.debtLocker_setPendingLender(address(debtLocker), address(debtLocker));  // Set pending lender in Loan to get ACL to work

        vm.expectRevert("DL:AL:NOT_MIGRATOR");
        notLoanMigrator.debtLocker_acceptLender(address(debtLocker));

        loanMigrator.try_debtLocker_acceptLender(address(debtLocker));
    }

    function _createLoan(uint256 principalRequested_, uint256 collateralRequired_) internal returns (MapleLoan loan_) {
        address[2] memory assets      = [address(collateralAsset), address(fundsAsset)];
        uint256[3] memory termDetails = [uint256(10 days), uint256(30 days), 6];
        uint256[3] memory amounts     = [collateralRequired_, principalRequested_, 0];
        uint256[4] memory rates       = [uint256(0.10e18), uint256(0), uint256(0), uint256(0)];

        bytes memory arguments = loanInitializer.encodeArguments(address(this), assets, termDetails, amounts, rates);
        bytes32 salt           = keccak256(abi.encodePacked("salt"));

        // Create Loan
        loan_ = MapleLoan(loanFactory.createInstance(arguments, salt));
    }

    function _fundAndDrawdownLoan(address loan_, address debtLocker_) internal {
        MapleLoan loan = MapleLoan(loan_);

        uint256 principalRequested = loan.principalRequested();
        uint256 collateralRequired = loan.collateralRequired();

        fundsAsset.mint(address(this), principalRequested);
        fundsAsset.approve(loan_,      principalRequested);

        loan.fundLoan(debtLocker_, principalRequested);

        collateralAsset.mint(address(this), collateralRequired);
        collateralAsset.approve(loan_,      collateralRequired);

        loan.drawdownFunds(loan.drawableFunds(), address(1));  // Drawdown to empty funds from loan
    }

    function _createFundAndDrawdownLoan(uint256 principalRequested_, uint256 collateralRequired_) internal returns (MapleLoan loan_, DebtLocker debtLocker_) {
        loan_ = _createLoan(principalRequested_, collateralRequired_);

        debtLocker_ = DebtLocker(pool.createDebtLocker(address(dlFactory), address(loan_)));

        _fundAndDrawdownLoan(address(loan_), address(debtLocker_));
    }

}
