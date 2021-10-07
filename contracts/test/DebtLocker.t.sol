// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { TestUtils }   from "../../modules/contract-test-utils/contracts/test.sol";
import { ERC20Helper } from "../../modules/erc20-helper/src/ERC20Helper.sol";
import { ERC20 }       from "../../modules/erc20/src/ERC20.sol";

import { DebtLockerFactory, DebtLocker, IDebtLockerFactory } from "../DebtLockerFactory.sol";

contract MockToken is ERC20 {

    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol, _decimals) {

    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

}

contract MockGlobal {

    uint256 public treasuryFee;
    uint256 public investorFee;

    address public mapleTreasury;

    constructor(uint256 treasuryFee_, uint256 investorFee_, address mapleTreasury_) {
        treasuryFee   = treasuryFee_;
        investorFee   = investorFee_;
        mapleTreasury = mapleTreasury_;
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

    MockGlobal        global;
    MockLoan          loan;
    MockPool          pool;
    DebtLockerFactory dlFactory;
    MockToken         fundsAsset;
    MockToken         collateralAsset;

    address mapleTreasury = address(123);

    function setUp() public {
        global          = new MockGlobal(500, 500, address(123));
        dlFactory       = new DebtLockerFactory(address(global));
        pool            = new MockPool(address(dlFactory));
        fundsAsset      = new MockToken("Funds Asset", "FA", 18);
        collateralAsset = new MockToken("Collateral Asset", "CA", 18);
    }

    function test_claim(uint256 principalRequested_, uint256 claimableFunds_, uint256 principal_, uint256 noOfPayments_, uint256 interestRate_) public {
        principalRequested_ = constrictToRange(principalRequested_, 1_000_000, 1_000_000_000);
        principal_          = constrictToRange(principal_, 1_000_000, principalRequested_);
        noOfPayments_       = constrictToRange(noOfPayments_, 1, 12);
        interestRate_       = constrictToRange(interestRate_, 100, 4000);  // Maximum 40 % return.
        claimableFunds_     = constrictToRange(claimableFunds_, (1_000_000 * interestRate_ / 10_000) * noOfPayments_, principal_ + (principal_ * interestRate_ / 10_000) * noOfPayments_);
        // Create the loan 
        loan = new MockLoan(principalRequested_, claimableFunds_, principal_, address(fundsAsset), address(collateralAsset), address(321));
        // Mint funds directly to loan.
        fundsAsset.mint(address(loan), claimableFunds_);
        uint256 principalPortion;

        if (claimableFunds_ > (principal_ * interestRate_ / 10_000) * noOfPayments_) {
            principalPortion = claimableFunds_ - (principal_ * interestRate_ / 10_000) * noOfPayments_;
        }
        loan.putFunds(principalPortion);

        // Create debt Locker 
        DebtLocker debtLocker = DebtLocker(pool.createDebtLocker(address(loan)));

        assertEq(fundsAsset.balanceOf(address(loan)), claimableFunds_, "Incorrect no. of funds in the loan");
        assertEq(fundsAsset.balanceOf(address(pool)), 0, "Incorrect no. of funds in the pool");

        uint256[7] memory details = pool.claim(debtLocker);

        assertEq(fundsAsset.balanceOf(address(pool)), claimableFunds_, "Invalid amount of funds transferred to the pool");
        assertEq(details[0], claimableFunds_,  "Details_0 set incorrectly");
        assertEq(details[1], uint256(0),       "Details_1 set incorrectly");
        assertEq(details[2], principalPortion, "Details_2 set incorrectly");
        assertEq(details[3], uint256(0),       "Details_3 set incorrectly");
    }
}