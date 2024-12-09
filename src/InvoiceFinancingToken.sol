// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * Invoice Financing with Tokens
 */
contract InvoiceFinancingToken is ERC721, Ownable, ReentrancyGuard {
    
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

    // Mapping to track Invoice details by tokenId (Token ID)
    mapping(uint256 => InvoiceDetails) public invoices;
    
    // Mapping to track company collateral
    mapping(address => uint256) public companyCollateral;

    // Track active invoices for each company
    mapping(address => uint256[]) private companyActiveInvoices;
    
    // Track active free tokens for each invoice
    mapping(uint256 => uint256[]) private invoiceFreeTokens;

    // Custom Errors
    error InsufficientCollateral(uint256 available, uint256 required);
    error InvalidInvoiceAmount(uint256 amount);
    error InvalidTokenPrice(uint256 price);
    error InvalidMaturityDate(uint256 currentTimestamp, uint256 maturityDate);
    error MissingIPFSHash();
    error InvoiceNotActive(uint256 invoiceId);
    error InsufficientTokens(uint256 requested, uint256 available);
    error IncorrectPaymentAmount(uint256 sent, uint256 expected);

    // Events
    event CollateralDeposited(
        address indexed company,
        uint256 amount
    );
    event CollateralWithdrawn(
        address indexed company, 
        uint256 amount
    );
    event InvoiceTokenCreated(
        uint256 indexed tokenId, 
        uint256 totalAmount, 
        uint256 tokenPrice, 
        uint256 tokensTotal,
        string ipfsDocumentHash
    );
    event InvoiceTokenPurchased(
        uint256 indexed tokenId,
        address indexed buyer,
        uint256 tokenAmount,
        uint256 paymentAmount
    );
    event TokensRedeemed(
        uint256 indexed tokenId,
        address indexed user,
        uint256 tokenAmount,
        uint256 redemptionAmount
    );

    // Constructor
    constructor() Ownable(msg.sender) ERC721("InvoiceFinancingToken", "IFT") {}

    /**
     * Internal function to add active invoice
     */
    function _addActiveInvoice(address _company, uint256 _invoiceId) private {
        companyActiveInvoices[_company].push(_invoiceId);
    }

    /**
     * Internal function to add free invoice token
     */
    function _addFreeInvoiceToken(uint256 _invoiceId, uint256 _tokenId) private {
        invoiceFreeTokens[_invoiceId].push(_tokenId);
    }

    /**
     * Internal function to fetch one free tokena dn remove it from tht array. 
     * It fetches the last one and directly pops it to make the function gas-efficient.
     */
    function _popFreeTokenId(uint256 _invoiceId) internal returns (uint256) {
        uint256[] storage freeTokens = invoiceFreeTokens[_invoiceId];
        require(freeTokens.length > 0, "No free tokens available");

        uint256 tokenId = freeTokens[freeTokens.length - 1];
        freeTokens.pop();

        return tokenId;
    }

    /**
     * Internal function to remove inactive invoice
     */    
    function _removeInactiveInvoice(
        address _company, 
        uint256 _invoiceId
    ) private {
        uint256[] storage activeInvoices = companyActiveInvoices[_company];
        for (uint256 i = 0; i < activeInvoices.length; i++) {
            if (activeInvoices[i] == _invoiceId) {
                activeInvoices[i] = activeInvoices[activeInvoices.length - 1];
                activeInvoices.pop();
                break;
            }
        }
    }

    /**
     * Deposit collateral for the company
     */
    function depositCollateral() external payable nonReentrant {
        require(msg.value > 0, "Deposited collateral must be greater than 0!");
        companyCollateral[msg.sender] += msg.value;

        emit CollateralDeposited(msg.sender, msg.value);
    }

    /**
     * Withdraw collateral for the company
     */
    function withdrawCollateral(
        uint256 _amount
    ) external nonReentrant {
        require(companyCollateral[msg.sender] >= _amount, "Insufficient collateral!");

        uint256 lockedCollateral = calculateLockedCollateral(msg.sender);
        require((companyCollateral[msg.sender] - lockedCollateral) >= _amount, "Cannot withdraw locked collateral. Insufficient free collateral!");

        companyCollateral[msg.sender] -= _amount;
        payable(msg.sender).transfer(_amount);

        emit CollateralWithdrawn(msg.sender, _amount);
    }

    /**
     * Calculate the locked collateral for a company
     */
    function calculateLockedCollateral(address _company) public view returns (uint256) {
        uint256 lockedAmount = 0;
        uint256[] memory activeInvoices = companyActiveInvoices[_company];

        for (uint256 i = 0; i < activeInvoices.length; i++) {
            InvoiceDetails memory invoice = invoices[activeInvoices[i]];
            if (invoice.companyWallet == _company && invoice.isActive) {
                lockedAmount += invoice.collateralDeposited;
            }
        }

        return lockedAmount;
    }

    /**
     * Create an Invoice Token
     */
    function createInvoiceToken(
        uint256 _invoiceId,
        uint256 _totalInvoiceAmount,
        uint256 _tokenPrice,
        uint256 _tokensTotal,
        uint256 _maturityDate,
        string calldata _ipfsDocumentHash
    ) external payable nonReentrant {
        require(_totalInvoiceAmount > 0, "Amount of invoice must be greater than 0.");
        require(_tokenPrice > 0, "Token price must be greater than 0.");
        require(_tokensTotal > 0, "Amount of tokens must be greater than 0.");
        require(_maturityDate > block.timestamp, "Maturity date should be in the future.");
        require(bytes(_ipfsDocumentHash).length > 0, "IPFS hash is required.");

        // Check if there is sufficient collateral (80% of total token value)
        uint256 requiredCollateral = (_tokenPrice * _tokensTotal * 80) / 100;
        uint256 lockedCollateral = calculateLockedCollateral(msg.sender);
        uint256 availableCollateral = companyCollateral[msg.sender] - lockedCollateral;
        require(availableCollateral >= requiredCollateral, "Insufficient company collateral");
        
        // Lock the required collateral
        companyCollateral[msg.sender] -= requiredCollateral;

        // Create invoice details
        InvoiceDetails memory newInvoice = InvoiceDetails({
            totalInvoiceAmount: _totalInvoiceAmount,
            tokenPrice: _tokenPrice,
            tokensTotal: _tokensTotal,
            maturityDate: _maturityDate,
            companyWallet: msg.sender,
            collateralDeposited: requiredCollateral,
            isActive: true,
            tokensRemaining: _tokensTotal,
            ipfsDocumentHash: _ipfsDocumentHash
        });
        invoices[_invoiceId] = newInvoice;

        // Mint _tokensTotal Tokens derived from _invoiceId
        for (uint256 i = 0; i < _tokensTotal; i++) {
            uint256 _tokenId = _invoiceId * 1e6 + i;
            _mint(msg.sender, _tokenId);
            _addFreeInvoiceToken(_invoiceId, _tokenId);
        }

        // Add active invoice
        _addActiveInvoice(msg.sender, _invoiceId);

        emit InvoiceTokenCreated(
            _invoiceId, 
            _totalInvoiceAmount, 
            _tokenPrice, 
            _tokensTotal,
            _ipfsDocumentHash
        );
    }

    /**
     * Purchase Token (Invoice Token)
     */
    function purchaseToken(
        uint256 _invoiceId,
        uint256 _tokenAmount
    ) external payable nonReentrant {
        InvoiceDetails storage invoice = invoices[_invoiceId];

        // Validation
        require(invoice.companyWallet != address(0), "Invoice does not exist");
        require(invoice.isActive, "Invoice is not active");
        require(_tokenAmount > 0, "Token amount must be greater than 0");
        require(_tokenAmount <= invoice.tokensRemaining, "Insufficient tokens available");
        require(msg.value == _tokenAmount * invoice.tokenPrice, "Incorrect payment amount");

        // Update
        invoice.tokensRemaining -= _tokenAmount;

        // Transfer the Token to the buyer
        uint _tokenId = _popFreeTokenId(_invoiceId);
        _transfer(invoice.companyWallet, msg.sender, _tokenId);
        (bool success, ) = invoice.companyWallet.call{value: msg.value}("");
        require(success, "Failed to transfer payment to the company");

        emit InvoiceTokenPurchased(_tokenId, msg.sender, _tokenAmount, msg.value);
    }

    /**
     * Redeem Token (Invoice) Tokens once maturity date is reached
     */
    function redeemTokens(
        uint256 _tokenId
    ) external nonReentrant {
        InvoiceDetails storage invoice = invoices[_tokenId];

        // Validate redemption
        require(block.timestamp >= invoice.maturityDate, "Invoice not mature yet");

        // Perform redemption logic
        uint256 redemptionAmount = invoice.tokensTotal * invoice.tokenPrice;
        require(address(this).balance >= redemptionAmount, "Insufficient funds to redeem");

        // TODO liquidate collateral 

        // Reset invoice state
        invoice.isActive = false;
        _removeInactiveInvoice(invoice.companyWallet, _tokenId);

        // Transfer redemption funds to the company
        (bool success, ) = invoice.companyWallet.call{value: redemptionAmount}("");
        require(success, "Redemption transfer failed");

        emit TokensRedeemed(_tokenId, invoice.companyWallet, invoice.tokensTotal, redemptionAmount);
    }

    // Fallback and receive functions to accept ETH
    receive() external payable {}
    fallback() external payable {}
}
