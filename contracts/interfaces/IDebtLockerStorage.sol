// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;


/// @title DebtLocker holds custody of LoanFDT tokens.
interface IDebtLockerStorage  {

    /**
     * @dev The address of the liquidator
     */
    function liquidator() external view returns (address liquidator_);

    /**
     * @dev The Loan contract this locker is holding tokens for.
     */
    function loan() external view returns (address loan_);

    /**
     * @dev The owner of this Locker (the Pool).
     */
    function pool() external view returns (address pool_);

    /**
     * @dev The maximum slippage allowed during liquidations
     */
    function allowedSlippage() external view returns (uint256 allowedSlippage_);

    /**
     * @dev The amount in funds asset recovered during liquidations
     */
    function amountRecovered() external view returns (uint256 amountRecovered_);

    /**
     * @dev The minimun exchange ration between funds asset and collateral asset
     */
    function minRatio() external view returns (uint256 minRatio_);

    /**
     * @dev Returns the principal that was present at the time of last claim.
     */
    function principalRemainingAtLastClaim() external view returns (uint256 principalRemainingAtLastClaim_);

    /**
     * @dev Returns if the funds have been repossessed
     */
    function repossessed() external view returns (bool repossessed_);

}
