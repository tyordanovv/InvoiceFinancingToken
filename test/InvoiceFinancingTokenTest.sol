// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {InvoiceFinancingToken} from "../src/InvoiceFinancingToken.sol";
import {DeployInvoiceFinancingToken} from "../script/DeployInvoiceFinancingToken.s.sol";
import "../src/InvoiceFinancingToken.sol";

contract InvoiceFinancingTokenTest is Test {
    InvoiceFinancingToken public invoiceToken;
    address public owner;
    address public company1;
    address public investor1;

    function setUp() public {
        // Setup accounts
        owner = makeAddr("owner");
        company1 = makeAddr("company1");
        investor1 = makeAddr("investor1");

        // Deploy contract
        vm.prank(owner);
        invoiceToken = new InvoiceFinancingToken();
    }

    function testInitialState() public {
        assertEq(invoiceToken.name(), "InvoiceFinancingToken");
        assertEq(invoiceToken.symbol(), "IFT");
    }

    function testDepositCollateral() public {
        // Company deposits collateral
        vm.prank(company1);
        vm.deal(company1, 10 ether);
        invoiceToken.depositCollateral{value: 5 ether}();

        assertEq(invoiceToken.companyCollateral(company1), 5 ether);
    }

    function testCreateInvoiceToken() public {
        // Prepare company with collateral
        vm.startPrank(company1);
        vm.deal(company1, 10 ether);
        invoiceToken.depositCollateral{value: 5 ether}();

        // Create invoice token
        uint256 invoiceId = 1;
        uint256 totalAmount = 10000;
        uint256 tokenPrice = 100;
        uint256 tokensTotal = 100;
        uint256 maturityDate = block.timestamp + 30 days;
        string memory ipfsHash = "QmHash123";

        invoiceToken.createInvoiceToken(
            invoiceId, 
            totalAmount, 
            tokenPrice, 
            tokensTotal, 
            maturityDate, 
            ipfsHash
        );
        vm.stopPrank();

        // Verify
        (
            uint256 storedTotalAmount,
            uint256 storedTokenPrice,
            uint256 storedTokensTotal,
            ,
            address storedCompanyWallet,
            ,
            bool storedIsActive,
            uint256 storedTokensRemaining,
            string memory storedIpfsHash
        ) = invoiceToken.invoices(invoiceId);

        assertEq(storedTotalAmount, totalAmount);
        assertEq(storedTokenPrice, tokenPrice);
        assertEq(storedTokensTotal, tokensTotal);
        assertEq(storedCompanyWallet, company1);
        assertTrue(storedIsActive);
        assertEq(storedTokensRemaining, tokensTotal);
        assertEq(storedIpfsHash, ipfsHash);

        // TODO Fix when calculateRequiredCollateral is imlpemented
        assertEq(invoiceToken.calculateLockedCollateral(company1), 8000);
    }

    function testCreateInvoiceTokenNoCollateral() public {
        // Prepare company without depositing collateral
        vm.startPrank(company1);
        vm.deal(company1, 10 ether);

        // Prepare invoice token parameters
        uint256 invoiceId = 1;
        uint256 totalAmount = 10000;
        uint256 tokenPrice = 100;
        uint256 tokensTotal = 100;
        uint256 maturityDate = block.timestamp + 30 days;
        string memory ipfsHash = "QmHash123";

        vm.expectRevert();
        invoiceToken.createInvoiceToken(
            invoiceId, 
            totalAmount, 
            tokenPrice, 
            tokensTotal, 
            maturityDate, 
            ipfsHash
        );
        
        vm.stopPrank();
    }

    function testPurchaseToken() public {
        // Prepare company with collateral and create invoice
        vm.startPrank(company1);
        vm.deal(company1, 10 ether);
        invoiceToken.depositCollateral{value: 5 ether}();

        uint256 invoiceId = 1;
        uint256 totalAmount = 10000;
        uint256 tokenPrice = 1000;
        uint256 tokensTotal = 10;
        uint256 maturityDate = block.timestamp + 30 days;
        string memory ipfsHash = "QmHash123";

        invoiceToken.createInvoiceToken(
            invoiceId, 
            totalAmount, 
            tokenPrice, 
            tokensTotal, 
            maturityDate, 
            ipfsHash
        );
        vm.stopPrank();

        // Prepare investor
        vm.startPrank(investor1);
        vm.deal(investor1, 10 ether);

        // Purchase tokens
        uint256 purchaseAmount = 2;
        invoiceToken.purchaseToken{value: purchaseAmount * tokenPrice}(
            invoiceId, 
            purchaseAmount
        );
        vm.stopPrank();

        // Verify purchase
        assertEq(invoiceToken.calculateLockedCollateral(company1), 8000);
        assertEq(company1.balance, 500000000000002000);

        (, , , , , , , uint256 remainingTokens, ) = invoiceToken.invoices(invoiceId);
        assertEq(remainingTokens, tokensTotal - purchaseAmount);
    }

    function testSuccessRedeemTokens() public {
        // TODO 
    }

    function testErrorRedeemTokensNotMature() public {
        // TODO 
    }

    function testErrorRedeemTokensNotMatureInsufficientFunds() public {
        // TODO 
    }

    function testCalculateLockedCollateralNoInvoices() public {
        vm.prank(company1);
        vm.deal(company1, 10 ether);
        invoiceToken.depositCollateral{value: 5 ether}();

        assertEq(invoiceToken.companyCollateral(company1), 5 ether);

        uint256 lockedCollateral = invoiceToken.calculateLockedCollateral(company1);
        assertEq(lockedCollateral, 0, "Locked collateral should be 0 when no invoices exist.");
    }
    
    function testCalculateLockedCollateralNoCollateralDeposited() public {
        vm.prank(company1);
        vm.deal(company1, 10 ether);

        assertEq(invoiceToken.companyCollateral(company1), 0 ether);

        uint256 lockedCollateral = invoiceToken.calculateLockedCollateral(company1);
        assertEq(lockedCollateral, 0, "Locked collateral should be 0 when no invoices exist.");
    }
}