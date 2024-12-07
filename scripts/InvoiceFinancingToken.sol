// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * TODO introduce UpgradeableCollateralManager and move depositCollateral, withdrawCollateral, calculateLockedCollateral
 */
contract InvoiceFinancingToken is ERC20, Ownable, ReentrancyGuard {
    
    /** Struct - Invoice details */
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
    }

    // Mapping to track Invoice details
    mapping(uint256 => InvoiceDetails) public invoices;
    
    // Mapping to track company collateral
    mapping(address => uint256) public companyCollateral;

    // Mapping to track user token holdings per invoice
    mapping(uint256 => mapping(address => uint256)) public userTokens;

    // Events
    event CollateralDeposited(
        address indexed company,
        uint256 amount
    );
    event CollateralWithdrawn(
        address indexed company, 
        uint256 amount
    );
    event InvoiceTokensCreated(
        uint256 indexed invoiceId, 
        uint256 totalAmount, 
        uint256 tokenPrice, 
        uint256 tokensTotal,
        string ipfsDocumentHash
    );

    // Constructor
    constructor() Ownable(msg.sender) ERC20("InvoiceFinancingToken", "IFT") {}

    /**
     * TODO
     */
    function depositCollateral() external payable nonReentrant {}

    /**
     * TODO
     */
    function withdrawCollateral(uint256 _amount) external nonReentrant {}

    /**
     * TODO
     */
    function calculateLockedCollateral(address _company) public view returns (uint256) {}

    /**
     * TODO
     */
    function createInvoiceTokens(
        uint256 _invoiceId,
        uint256 _totalInvoiceAmount,
        uint256 _tokenPrice,
        uint256 _tokensTotal,
        uint256 _maturityDate,
        string calldata _ipfsDocumentHash
    ) external payable nonReentrant {}

    /**
     * TODO
     */
    function purchaseTokens(
        uint256 _invoiceId, 
        uint256 _tokenAmount
    ) external payable nonReentrant {}

    /**
     * TODO
     */
    function redeemTokens(uint256 _invoiceId) external nonReentrant {}

    /**
     * TODO
     */
    function checkLiquidation(uint256 _invoiceId) external {}

    // Fallback and receive functions to accept ETH
    receive() external payable {}
    fallback() external payable {}
}