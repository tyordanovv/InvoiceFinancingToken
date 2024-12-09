// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IInvoiceFinancingToken {
    function createInvoiceTokens(
        uint256 _invoiceId,
        uint256 _totalInvoiceAmount,
        uint256 _tokenPrice,
        uint256 _tokensTotal,
        uint256 _maturityDate,
        string calldata _ipfsDocumentHash
    ) external payable;

    function purchaseTokens(
        uint256 _invoiceId, 
        uint256 _tokenAmount
    ) external payable;
}

contract InvoiceMarketplace is Ownable, ReentrancyGuard {
    // Struct to represent a marketplace listing
    struct InvoiceListing {
        uint256 invoiceId;
        address seller;
        uint256 totalAmount;
        uint256 tokenPrice;
        uint256 tokensTotal;
        uint256 maturityDate;
        bool isActive;
        uint256 minimumRiskScore;
    }

    // Interface to the Invoice Financing Token contract
    IInvoiceFinancingToken public invoiceTokenContract;

    // Mapping of invoice listings
    mapping(uint256 => InvoiceListing) public listings;

    // Events
    event ListingCreated(
        uint256 indexed invoiceId, 
        address indexed seller, 
        uint256 totalAmount, 
        uint256 tokenPrice
    );
    event ListingUpdated(
        uint256 indexed invoiceId, 
        uint256 newTokenPrice
    );
    event ListingCancelled(
        uint256 indexed invoiceId
    );

    // Constructor
    constructor(
        address _invoiceTokenContractAddress
    ) Ownable(msg.sender) {
        invoiceTokenContract = IInvoiceFinancingToken(_invoiceTokenContractAddress);
    }

    /**
     * TODO
     */
    function createInvoiceListing(
        uint256 _invoiceId,
        uint256 _totalInvoiceAmount,
        uint256 _tokenPrice,
        uint256 _tokensTotal,
        uint256 _maturityDate,
        uint256 _minimumRiskScore
    ) external payable nonReentrant {}

    /**
     * TODO
     */
    function updateListingPrice(
        uint256 _invoiceId, 
        uint256 _newTokenPrice
    ) external nonReentrant {}

    /**
     * TODO
     */
    function cancelListing(uint256 _invoiceId) external nonReentrant {}

    /**
     * TODO
     */
    function buyTokens(
        uint256 _invoiceId, 
        uint256 _tokenAmount
    ) external payable nonReentrant {}

    // Fallback and receive functions
    receive() external payable {}
    fallback() external payable {}
}