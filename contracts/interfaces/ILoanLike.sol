// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { IERC20 } from "../../modules/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface ILoanLike is IERC20 {

    /***********************/
    /*** State Variables ***/
    /***********************/

    /**
     *  @dev The borrower of the loan, responsible for repayments.
     */
    function borrower() external view returns (address borrower_);

    /**
     *  @dev The amount of funds that have yet to be claimed by the lender.
     */
    function claimableFunds() external view returns (uint256 claimableFunds_);

    /**
     *  @dev The amount of collateral posted against outstanding (drawn down) principal.
     */
    function collateral() external view returns (uint256 collateral_);

    /**
     *  @dev The address of the asset deposited by the borrower as collateral, if needed.
     */
    function collateralAsset() external view returns (address collateralAsset_);

    /**
     *  @dev The amount of collateral required if all of the principal required is drawn down.
     */
    function collateralRequired() external view returns (uint256 collateralRequired_);

    /**
     *  @dev The amount of funds that have yet to be drawn down by the borrower.
     */
    function drawableFunds() external view returns (uint256 drawableFunds_);

    /**
     *  @dev The portion of principal to not be paid down as part of payment installments, which would need to be paid back upon final payment.
     *  @dev If endingPrincipal = principal, loan is interest-only.
     */
    function endingPrincipal() external view returns (uint256 endingPrincipal_);

    /**
     *  @dev The asset deposited by the lender to fund the loan.
     */
    function fundsAsset() external view returns (address fundsAsset_);

    /**
     *  @dev The amount of time the borrower has, after a payment is due, to make a payment before being in default.
     */
    function gracePeriod() external view returns (uint256 gracePeriod_);

    /**
     *  @dev The annualized interest rate (APR), in basis points, scaled by 100 (i.e. 1% is 10_000).
     */
    function interestRate() external view returns (uint256 interestRate_);

    /**
     *  @dev The annualized fee rate charged on interest for late payments, in basis points, scaled by 100 (i.e. 1% is 10_000).
     */
    function lateFeeRate() external view returns (uint256 lateFeeRate_);

    /**
     *  @dev The lender of the Loan.
     */
    function lender() external view returns (address lender_);

    /**
     *  @dev The timestamp due date of the next payment.
     */
    function nextPaymentDueDate() external view returns (uint256 nextPaymentDueDate_);

    /**
     *  @dev The specified time between loan payments.
     */
    function paymentInterval() external view returns (uint256 paymentInterval_);

    /**
     *  @dev The number of payment installments remaining for the loan.
     */
    function paymentsRemaining() external view returns (uint256 paymentsRemaining_);

    /**
     *  @dev The amount of principal owed (initially, the requested amount), which needs to be paid back.
     */
    function principal() external view returns (uint256 principal_);

    /**
     *  @dev The initial principal amount requested by the borrower.
     */
    function principalRequested() external view returns (uint256 principalRequested_);

    /**
     * @dev Unixtimestamp at which last payment occurs.
     */
    function lastPaymentTime() external view returns (uint256 lastPaymentTime_);

    /********************************/
    /*** State Changing Functions ***/
    /********************************/

    /**
     *  @dev   Claim funds that have been paid (principal, interest, and late fees).
     *  @param amount_      The amount to be claimed.
     *  @param destination_ The address to send the funds.
     */
    function claimFunds(uint256 amount_, address destination_) external;

    /**
     *  @dev   Draw down funds from the loan.
     *  @param amount_      The amount to draw down.
     *  @param destination_ The address to send the funds.
     */
    function drawdownFunds(uint256 amount_, address destination_) external;

    /**
     *  @dev    Lend funds to the loan/borrower.
     *  @param  lender_ The address to be registered as the lender.
     *  @return amount_ The amount lent.
     */
    function lend(address lender_) external returns (uint256 amount_);

    /**
     *  @dev    Make one installment payment to the loan.
     *  @return totalPrincipalAmount_ The portion of the amount paid paying back principal.
     *  @return totalInterestFees_    The portion of the amount paid paying interest fees.
     *  @return totalLateFees_        The portion of the amount paid paying late fees.
     */
    function makePayment() external returns (uint256 totalPrincipalAmount_, uint256 totalInterestFees_, uint256 totalLateFees_);

    /**
     *  @dev    Make several installment payments to the loan.
     *  @param  numberOfPayments_     The number of payment installments to make.
     *  @return totalPrincipalAmount_ The portion of the amount paid paying back principal.
     *  @return totalInterestFees_    The portion of the amount paid paying interest fees.
     *  @return totalLateFees_        The portion of the amount paid paying late fees.
     */
    function makePayments(uint256 numberOfPayments_) external returns (
        uint256 totalPrincipalAmount_,
        uint256 totalInterestFees_,
        uint256 totalLateFees_
    );

    /**
     *  @dev    Post collateral to the loan.
     *  @return amount_ The amount posted.
     */
    function postCollateral() external returns (uint256 amount_);

    /**
     *  @dev   Remove collateral from the loan (opposite of posting collateral).
     *  @param amount_      The amount removed.
     *  @param destination_ The destination to send the removed collateral.
     */
    function removeCollateral(uint256 amount_, address destination_) external;

    /**
     *  @dev    Return funds to the loan (opposite of drawing down).
     *  @return amount_ The amount returned.
     */
    function returnFunds() external returns (uint256 amount_);

    /**
     *  @dev    Repossess collateral, and any funds, for a loan in default.
     *  @param  collateralAssetDestination_ The address where the collateral asset is to be sent.
     *  @param  fundsAssetDestination_      The address where the funds asset is to be sent.
     *  @return collateralAssetAmount_      The amount of collateral asset repossessed.
     *  @return fundsAssetAmount_           The amount of funds asset repossessed.
     */
    function repossess(address collateralAssetDestination_, address fundsAssetDestination_) external returns (
        uint256 collateralAssetAmount_,
        uint256 fundsAssetAmount_
    );

    /**
     *  @dev    Skims any amount, given an asset, which is unaccounted for (and thus not required).
     *  @param  asset_       The address of the asset.
     *  @param  destination_ The address where the amount of the asset is to be sent.
     *  @return amount_      The amount of the asset skimmed.
     */
    function skim(address asset_, address destination_) external returns (uint256 amount_);

    /**
     *  @dev    Upgrade the MapleLoan implementation used to a new version.
     *  @param  toVersion_ The MapleLoan version to upgrade to.
     *  @param  arguments_ The encoded arguments used for migration, if any.
     */
    function upgrade(uint256 toVersion_, bytes calldata arguments_) external;

    /**************************/
    /*** Readonly Functions ***/
    /**************************/

    /**
     *  @dev    Get the breakdown of the total payment needed to satisfy `numberOfPayments` payment installments.
     *  @param  numberOfPayments_     The number of payment installments.
     *  @return totalPrincipalAmount_ The portion of the total amount that will go towards principal.
     *  @return totalInterestFees_    The portion of the total amount that will go towards interest fees.
     *  @return totalLateFees_        The portion of the total amount that will go towards late fees.
     */
    function getNextPaymentsBreakDown(uint256 numberOfPayments_) external view returns (
        uint256 totalPrincipalAmount_,
        uint256 totalInterestFees_,
        uint256 totalLateFees_
    );

    /**
     *  @dev    Get the breakdown of the total payment needed to satisfy `numberOfPayments` payment installments.
     *  @param  lastClaimTime_        The number of payment installments.
     *  @return totalPrincipalAmount_ The portion of the total amount that will go towards principal.
     *  @return totalInterestFees_    The portion of the total amount that will go towards interest fees.
     *  @return totalLateFees_        The portion of the total amount that will go towards late fees.
     */
    function getPaymentsBreakdownForClaim(uint256 lastClaimTime_) external view returns (
        uint256 totalPrincipalAmount_,
        uint256 totalInterestFees_,
        uint256 totalLateFees_
    );

}
