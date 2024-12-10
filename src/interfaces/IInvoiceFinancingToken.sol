// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IInvoiceFinancingToken
 * @dev Interface for the Invoice Financing Token contract
 */
interface IInvoiceFinancingToken {
    struct InvoiceDetails {
        uint256 totalInvoiceAmount;
        uint256 tokenPrice;
        uint256 tokensTotal;
        uint256 maturityDate;
        address companyWallet;
        uint256 collateralDeposited;
        bool isActive;
        uint256 tokensRemaining;
        string ipfsDocumentHash;
        uint256[] tokenIds;
    }

    // Events
    event CollateralDeposited(address indexed company, uint256 amount);
    event CollateralWithdrawn(address indexed company, uint256 amount);
    event InvoiceTokenCreated(uint256 indexed tokenId, uint256 totalAmount, uint256 tokenPrice, uint256 tokensTotal, string ipfsDocumentHash);
    event InvoiceTokenPurchased(uint256 indexed tokenId, address indexed buyer, uint256 tokenAmount, uint256 paymentAmount);
    event InvoiceTokenPurchasedback(uint256 indexed tokenId, address indexed buyer, uint256 paymentAmount);
    event TokensRedeemed(uint256 indexed tokenId, address indexed user, uint256 tokenAmount, uint256 redemptionAmount);

    /**
     * @dev Deposit collateral for the company.
     */
    function depositCollateral() external payable;

    /**
     * @dev Withdraw collateral for the company.
     * @param _amount The amount to withdraw.
     * TODO this function should be only for companies
     */
    function withdrawCollateral(uint256 _amount) external;

    /**
     * @dev Calculate locked collateral for a company.
     * @param _company The company address.
     * @return lockedAmount The amount of locked collateral.
     */
    function calculateLockedCollateral(address _company)
        external
        view
        returns (uint256 lockedAmount);

    /**
    * @dev Create an invoice token.
    * @param _invoiceId The id of the invoice.
    * @param _totalInvoiceAmount The full invoice price.
    * @param _tokenPrice The price per token.
    * @param _tokensTotal The amount of the total invoice tokens.
    * @param _maturityDate The maturity date of the invoice.
    * @param _ipfsDocumentHash The IPSF-hash, where the document is stored.
    */
    function createInvoiceToken(
        uint256 _invoiceId,
        uint256 _totalInvoiceAmount,
        uint256 _tokenPrice,
        uint256 _tokensTotal,
        uint256 _maturityDate,
        string calldata _ipfsDocumentHash
    ) external payable;


    /**
     * @dev Purchase invoice tokens.
     * @param _invoiceId The id of the invoice.
     * @param _tokenAmount The the amount of the tokens to be bought.
     */
    function purchaseToken(uint256 _invoiceId, uint256 _tokenAmount)
        external
        payable;

    /**
    * @dev Redeem tokens after maturity date.
    * @param _invoiceId The id of the invoice.
    */
    function redeemTokens(uint256 _invoiceId) external;
}