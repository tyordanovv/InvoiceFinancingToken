// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title InvoiceFinancingToken
 * @dev Tokenized invoice financing using ERC721 tokens
 */
contract InvoiceFinancingToken is ERC721, Ownable, ReentrancyGuard {
    
    // Struct to store invoice details
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

    // State variables
    mapping(uint256 => InvoiceDetails) public invoices;
    mapping(address => uint256) public companyCollateral;
    mapping(address => uint256[]) private companyActiveInvoices;
    mapping(uint256 => uint256[]) private invoiceFreeTokens;

    // Events
    event CollateralDeposited(address indexed company, uint256 amount);
    event CollateralWithdrawn(address indexed company, uint256 amount);
    event InvoiceTokenCreated(uint256 indexed tokenId, uint256 totalAmount, uint256 tokenPrice, uint256 tokensTotal, string ipfsDocumentHash);
    event InvoiceTokenPurchased(uint256 indexed tokenId, address indexed buyer, uint256 tokenAmount, uint256 paymentAmount);
    event TokensRedeemed(uint256 indexed tokenId, address indexed user, uint256 tokenAmount, uint256 redemptionAmount);

    // Errors
    error InsufficientCollateral(uint256 available, uint256 required);
    error InsufficientFreeCollateral(uint256 available, uint256 required);
    error InvalidCollateralAmount();
    error InvalidInvoiceAmount(uint256 amount);
    error InvalidTokenPrice(uint256 price);
    error InvalidTokensToBuy(uint256 amount);
    error InvoiceNotActive(uint256 invoiceId);
    error InsufficientTokens(uint256 requested, uint256 available);
    error IncorrectPaymentAmount(uint256 sent, uint256 expected);
    error TokenPaymentTransferFailed(address companyWallet, address buyer, uint256 amount);
    error RedemptionPaymentTransferFailed(address companyWallet, address buyer, uint256 amount);
    error InvalidMaturityDate(uint256 currentTimestamp, uint256 maturityDate);
    error MissingIPFSHash();
    error InsufficientFundsToRedeem(address company, address investor, uint256 amount);

    constructor() Ownable(msg.sender) ERC721("InvoiceFinancingToken", "IFT") {}

    /**
     * @dev Modifier to ensure sufficient collateral is available for the company.
     */
    modifier hasSufficientCollateral(uint256 _requiredCollateral) {
        uint256 lockedCollateral = calculateLockedCollateral(msg.sender);
        uint256 availableCollateral = companyCollateral[msg.sender] - lockedCollateral;
        if(availableCollateral < _requiredCollateral) revert InsufficientCollateral(availableCollateral, _requiredCollateral);
        _;
    }

    /**
     * @dev Deposit collateral for the company.
     */
    function depositCollateral() external payable nonReentrant {
        if (msg.value == 0) revert InvalidCollateralAmount();
        companyCollateral[msg.sender] += msg.value;
        emit CollateralDeposited(msg.sender, msg.value);
    }

    /**
     * @dev Withdraw collateral for the company.
     * @param _amount The amount to withdraw.
     * TODO this function should be only for companies
     */
    function withdrawCollateral(
        uint256 _amount
    ) external nonReentrant hasSufficientCollateral(_amount) {
        companyCollateral[msg.sender] -= _amount;
        payable(msg.sender).transfer(_amount);
        emit CollateralWithdrawn(msg.sender, _amount);
    }

    /**
     * @dev Calculate locked collateral for a company.
     * @param _company The company address.
     * @return lockedAmount The amount of locked collateral.
     */
    function calculateLockedCollateral(
        address _company
    ) public view returns (uint256 lockedAmount) {
        uint256[] memory activeInvoices = companyActiveInvoices[_company];
        for (uint256 i = 0; i < activeInvoices.length; i++) {
            InvoiceDetails memory invoice = invoices[activeInvoices[i]];
            if (invoice.isActive) lockedAmount += invoice.collateralDeposited;
        }
    }

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
    ) external payable nonReentrant {
        if (_totalInvoiceAmount == 0) revert InvalidInvoiceAmount(_totalInvoiceAmount);
        if (_tokenPrice == 0) revert InvalidTokenPrice(_tokenPrice);
        if (_tokensTotal == 0) revert InvalidTokensToBuy(_tokensTotal);
        if (_maturityDate <= block.timestamp) revert InvalidMaturityDate(block.timestamp, _maturityDate);
        if (bytes(_ipfsDocumentHash).length == 0) revert MissingIPFSHash();

        uint256 requiredCollateral = (_tokenPrice * _tokensTotal * 80) / 100;
        uint256 availableCollateral = companyCollateral[msg.sender] - calculateLockedCollateral(msg.sender);
        if (availableCollateral < requiredCollateral) revert InsufficientCollateral(availableCollateral, requiredCollateral);

        companyCollateral[msg.sender] -= requiredCollateral;

        invoices[_invoiceId] = InvoiceDetails({
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

        for (uint256 i = 0; i < _tokensTotal; i++) {
            uint256 tokenId = _invoiceId * 1e6 + i;
            _mint(msg.sender, tokenId);
            _addFreeInvoiceToken(_invoiceId, tokenId);
         }

        _addActiveInvoice(msg.sender, _invoiceId);
        emit InvoiceTokenCreated(_invoiceId, _totalInvoiceAmount, _tokenPrice, _tokensTotal, _ipfsDocumentHash);
    }

    /**
     * @dev Purchase invoice tokens.
     * @param _invoiceId The id of the invoice.
     * @param _tokenAmount The the amount of the tokens to be bought.
     */
    function purchaseToken(
        uint256 _invoiceId, 
        uint256 _tokenAmount
    ) external payable nonReentrant {
        InvoiceDetails storage invoice = invoices[_invoiceId];
        if (!invoice.isActive || block.timestamp >= invoice.maturityDate) revert InvoiceNotActive(_invoiceId);
        if (msg.value != _tokenAmount * invoice.tokenPrice) revert IncorrectPaymentAmount(msg.value, _tokenAmount * invoice.tokenPrice);
        if (_tokenAmount > invoice.tokensRemaining) revert InsufficientTokens(_tokenAmount, invoice.tokensRemaining);

        invoice.tokensRemaining -= _tokenAmount;

        for (uint256 i = 0; i < _tokenAmount; i++) {
            uint _tokenId = _popFreeTokenId(_invoiceId);
             _transfer(invoice.companyWallet, msg.sender, _tokenId);
        }

        (bool success, ) = invoice.companyWallet.call{value: msg.value}("");
        if (!success) revert TokenPaymentTransferFailed(invoice.companyWallet, msg.sender, msg.value);

        emit InvoiceTokenPurchased(_invoiceId, msg.sender, _tokenAmount, msg.value);
    }

    /**
     * @dev Redeem tokens after maturity date.
     * @param _invoiceId The id of the invoice.
     * @param _tokenId The id of the token.
     */
    function redeemTokens(
        uint256 _invoiceId,
        uint256 _tokenId
    ) external nonReentrant {
        InvoiceDetails storage invoice = invoices[_invoiceId];
        if (block.timestamp < invoice.maturityDate) revert InvalidMaturityDate(block.timestamp, invoice.maturityDate);

        uint256 redemptionAmount = invoice.tokensTotal * invoice.tokenPrice;
        if (address(this).balance < redemptionAmount) revert InsufficientFundsToRedeem(invoice.companyWallet, msg.sender, redemptionAmount);

        invoice.isActive = false;
        _removeInactiveInvoice(invoice.companyWallet, _tokenId);

        (bool success, ) = invoice.companyWallet.call{value: redemptionAmount}("");
        if (!success) revert RedemptionPaymentTransferFailed(invoice.companyWallet, msg.sender, redemptionAmount);

        emit TokensRedeemed(_invoiceId, msg.sender, invoice.tokensTotal, redemptionAmount);
    }

    
    /**
     * @dev Internal function to add active invoice
     * @param _company The address of the company.
     * @param _invoiceId The id of the invoice.
     */
    function _addActiveInvoice(
        address _company, 
        uint256 _invoiceId
    ) private {
        companyActiveInvoices[_company].push(_invoiceId);
    }

    /**
     * @dev Internal function to remove inactive invoice
     * @param _company The address of the company.
     * @param _invoiceId The id of the invoice.
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
     * @dev Internal function to add free invoice token
     * @param _invoiceId The id of the invoice.
     * @param _tokenId The id of the invoice token.
     */
    function _addFreeInvoiceToken(
        uint256 _invoiceId, 
        uint256 _tokenId
    ) private {
        invoiceFreeTokens[_invoiceId].push(_tokenId);
    }

    /**
     * @dev Internal function to fetch one free tokena dn remove it from tht array. 
     * It fetches the last one and directly pops it to make the function gas-efficient.
     * @param _invoiceId The id of the invoice.
     */
    function _popFreeTokenId(
        uint256 _invoiceId
    ) internal returns (uint256) {
        uint256[] storage freeTokens = invoiceFreeTokens[_invoiceId];
        if (freeTokens.length == 0) {
            revert InsufficientTokens(1, 0);
        }
        uint256 tokenId = freeTokens[freeTokens.length - 1];
        freeTokens.pop();

        return tokenId;
    }

    // Fallback and receive functions to accept ETH
    receive() external payable {}
    fallback() external payable {}
}
