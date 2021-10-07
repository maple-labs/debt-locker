// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { TestUtils }   from "../../modules/contract-test-utils/contracts/test.sol";
import { ERC20Helper } from "../../modules/erc20-helper/src/ERC20Helper.sol";
import { ERC20 }       from "../../modules/erc20/src/ERC20.sol";

import { DebtLockerFactory, DebtLocker, IDebtLockerFactory } from "../DebtLockerFactory.sol";

contract MockToken is ERC20 {

    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol, _decimals) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

}

contract MockLoan {

    uint256 public principalRequested;
    uint256 public claimableFunds;
    uint256 public principal;

    address public fundsAsset;
    address public collateralAsset;
    address public lender;

    constructor(uint256 principalRequested_, uint256 claimableFunds_, uint256 principal_, address fundsAsset_, address collateralAsset_, address lender_) {
        principalRequested = principalRequested_;
        claimableFunds     = claimableFunds_;
        principal          = principal_;
        fundsAsset         = fundsAsset_;
        collateralAsset    = collateralAsset_;
        lender             = lender_;
    }

    function setClaimableFunds(uint256 claimableFunds_) external {
        claimableFunds = claimableFunds_;
    }

    function claimFunds(uint256 amount_, address destination_) public returns (bool success_) {
        claimableFunds -= amount_;
        return ERC20Helper.transfer(fundsAsset, destination_, amount_);
    }

    function repossess() internal virtual returns (bool success_) {
        claimableFunds = uint256(0);
        principal      = uint256(0);
        return true;
    }

    function changeParams(uint256 principalRequested_, uint256 claimableFunds_, uint256 principal_, address fundsAsset_, address collateralAsset_, address lender_) external {
        principalRequested = principalRequested_;
        claimableFunds     = claimableFunds_;
        principal          = principal_;
        fundsAsset         = fundsAsset_;
        collateralAsset    = collateralAsset_;
        lender             = lender_;
    }

    function putFunds(uint256 fundsTo_) external {
        principal -= fundsTo_;
    }

}

contract MockPool {

    address public dlFactory;

    constructor(address dlFactory_) {
        dlFactory = dlFactory_;
    }

    function createDebtLocker(address loan) public returns(address) {
        return IDebtLockerFactory(dlFactory).newLocker(loan);
    }

    function claim(DebtLocker dl) public returns(uint256[7] memory) {
        return dl.claim();
    }

}

contract DebtLockerTest is TestUtils {

    MockLoan          loan;
    MockPool          pool;
    DebtLockerFactory dlFactory;
    MockToken         fundsAsset;
    MockToken         collateralAsset;

    uint256 internal constant MAX_TOKEN_AMOUNT = 1e12 * 1e18;

    function setUp() public {
        dlFactory       = new DebtLockerFactory();
        pool            = new MockPool(address(dlFactory));
        fundsAsset      = new MockToken("Funds Asset",      "FA", 18);
        collateralAsset = new MockToken("Collateral Asset", "CA", 18);
    }

    function test_claim(uint256 principalRequested_, uint256 endingPrincipal_, uint256 claimableFunds_, uint256 noOfPayments_, uint256 interestRate_) public {

        principalRequested_ = constrictToRange(principalRequested_, 1_000_000, MAX_TOKEN_AMOUNT);
        endingPrincipal_    = constrictToRange(endingPrincipal_,    0,         principalRequested_);
        noOfPayments_       = constrictToRange(noOfPayments_,       1,         10);
        interestRate_       = constrictToRange(interestRate_,       1,         10_000);  // 0.01% to 100%

        uint256 interestAmount = (principalRequested_ * interestRate_ / 10_000);  // Mock interest amount

        claimableFunds_ = constrictToRange(claimableFunds_, interestAmount, principalRequested_ + interestAmount);
        
        // Create the loan 
        loan = new MockLoan(principalRequested_, claimableFunds_, principalRequested_, address(fundsAsset), address(collateralAsset), address(321));
        
        // Mint funds directly to loan.
        fundsAsset.mint(address(loan), claimableFunds_);

        uint256 principalPortion;

        if (claimableFunds_ > interestAmount) {
            principalPortion = claimableFunds_ - interestAmount;
        }

        loan.putFunds(principalPortion > principalRequested_ ? principalRequested_: principalPortion);

        // Create debt Locker 
        DebtLocker debtLocker = DebtLocker(pool.createDebtLocker(address(loan)));

        assertEq(fundsAsset.balanceOf(address(loan)), claimableFunds_);
        assertEq(fundsAsset.balanceOf(address(pool)), 0);

        assertEq(debtLocker.principalRemainingAtLastClaim(), loan.principalRequested());

        uint256[7] memory details = pool.claim(debtLocker);

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

        details = pool.claim(debtLocker);

        assertEq(fundsAsset.balanceOf(address(pool)), claimableFunds_ + newClaimableFunds);

        assertEq(details[0], newClaimableFunds);
        assertEq(details[1], newClaimableFunds - principalPortionLeft);
        assertEq(details[2], principalPortionLeft);
    }
    
}
