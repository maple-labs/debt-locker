// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

interface IMapleGlobalsLike {

   function defaultUniswapPath(address fromAsset_, address toAsset_) external view returns (address intermediateAsset_);

   function investorFee() external view returns (uint256 investorFee_);

   function mapleTreasury() external view returns (address mapleTreasury_);

   function treasuryFee() external view returns (uint256 treasuryFee_);

}

interface IMapleLoanLike {

    function claimableFunds() external view returns (uint256 claimableFunds_);

    function collateralAsset() external view returns (address collateralAsset_);

    function fundsAsset() external view returns (address fundsAsset_);

    function lender() external view returns (address lender_);

    function principal() external view returns (uint256 principal_);

    function principalRequested() external view returns (uint256 principalRequested_);

    function claimFunds(uint256 amount_, address destination_) external;

    function repossess(address collateralAssetDestination_, address fundsAssetDestination_) external returns (
        uint256 collateralAssetAmount_,
        uint256 fundsAssetAmount_
    );

}

interface IPoolLike {

    function poolDelegate() external pure returns (address poolDelegate_);

}

interface IUniswapRouterLike {

    function swapExactTokensForTokens(
        uint amountIn_,
        uint amountOutMin_,
        address[] calldata path_,
        address to_,
        uint deadline_
    ) external returns (uint[] memory amounts_);

}