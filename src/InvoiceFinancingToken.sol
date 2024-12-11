// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IInvoiceFinancingToken.sol";

/**
 * @title InvoiceFinancingToken
 * @dev Implementation of the IInvoiceFinancingToken interface
 */
contract InvoiceFinancingToken is ERC721, Ownable, ReentrancyGuard, IInvoiceFinancingToken {
    // State variables
    mapping(uint256 => InvoiceDetails) public invoices;
    mapping(address => uint256) private companyCollateral;
    mapping(address => uint256[]) private companyActiveInvoices;
    mapping(uint256 => uint256[]) private invoiceFreeTokens;
    mapping(address => uint256[]) private userPurchasedTokens;

    // Minimum deposit amount
    uint256 public constant MIN_DEPOSIT = 0.1 ether;

    // Minimum percentage of total collateral that will be locked
    uint256 public constant MIN_LOCK_PERCENTAGE = 80;

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
    error NotTokenOwner(address investor, uint256 tokenId);

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
     * @dev Modifier to check invoice ownership.
     */
    modifier onlyCompany(uint256 invoiceId) {
        require(invoices[invoiceId].companyWallet == msg.sender, "Not authorized");
        _;
    }

    /**
     * @dev See {IInvoiceFinancingToken-depositCollateral}.
     */
    function depositCollateral() external payable nonReentrant {
        if (msg.value < MIN_DEPOSIT) revert InvalidCollateralAmount();
        companyCollateral[msg.sender] += msg.value;
        emit CollateralDeposited(msg.sender, msg.value);
    }


    /**
     * @dev See {IInvoiceFinancingToken-withdrawCollateral}.
     */
    function withdrawCollateral(
        uint256 _amount
    ) external nonReentrant hasSufficientCollateral(_amount) {
        companyCollateral[msg.sender] -= _amount;
        payable(msg.sender).transfer(_amount);
        emit CollateralWithdrawn(msg.sender, _amount);
    }

    /**
     * @dev See {IInvoiceFinancingToken-calculateLockedCollateral}.
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
     * @dev See {IInvoiceFinancingToken-createInvoiceToken}.
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

        // Collateral calculation (80% of total token value)
        uint256 requiredCollateral = (_tokenPrice * _tokensTotal * 80) / 100;
        uint256 availableCollateral = companyCollateral[msg.sender] - calculateLockedCollateral(msg.sender);
        if (availableCollateral < requiredCollateral) revert InsufficientCollateral(availableCollateral, requiredCollateral);

        uint256[] memory tokenIds = new uint256[](_tokensTotal);

        // Mint tokens and track token IDs
        for (uint256 i = 0; i < _tokensTotal; i++) {
            uint256 tokenId = _invoiceId * 1e6 + i;
            _mint(msg.sender, tokenId);
            _addFreeInvoiceToken(_invoiceId, tokenId);
            tokenIds[i] = tokenId;
        }

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
            ipfsDocumentHash: _ipfsDocumentHash,
            tokenIds: tokenIds
        });

        _addActiveInvoice(msg.sender, _invoiceId);
        emit InvoiceTokenCreated(_invoiceId, _totalInvoiceAmount, _tokenPrice, _tokensTotal, _ipfsDocumentHash);
    }

    /**
     * @dev See {IInvoiceFinancingToken-purchaseToken}.
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
            userPurchasedTokens[msg.sender].push(_tokenId);
        }

        (bool success, ) = invoice.companyWallet.call{value: msg.value}("");
        if (!success) revert TokenPaymentTransferFailed(invoice.companyWallet, msg.sender, msg.value);

        emit InvoiceTokenPurchased(_invoiceId, msg.sender, _tokenAmount, msg.value);
    }

    /**
     * @dev See {IInvoiceFinancingToken-redeemTokens}.
     */
    function redeemTokens(
        uint256 _invoiceId
    ) external nonReentrant onlyCompany(_invoiceId) {
        InvoiceDetails storage invoice = invoices[_invoiceId];
        
        if (block.timestamp < invoice.maturityDate) 
            revert InvalidMaturityDate(block.timestamp, invoice.maturityDate);

        uint256 soldTokens = invoice.tokensTotal - invoice.tokensRemaining;
        uint256 redemptionAmount = soldTokens * invoice.tokenPrice;

        if (invoice.companyWallet.balance < redemptionAmount) 
            revert InsufficientFundsToRedeem(invoice.companyWallet, msg.sender, redemptionAmount);

        for (uint256 i = 0; i < invoice.tokensTotal; i++) {
            uint256 tokenId = invoice.tokenIds[i];
            address tokenOwner = ownerOf(tokenId);
            if (tokenOwner != msg.sender) {
                _transfer(tokenOwner, invoice.companyWallet, tokenId);
                emit InvoiceTokenPurchasedback(tokenId, msg.sender, invoice.tokenPrice);

                (bool success, ) = tokenOwner.call{value: invoice.tokenPrice}("");
                if (!success) revert RedemptionPaymentTransferFailed(invoice.companyWallet, tokenOwner, invoice.tokenPrice);
            }
        }

        invoice.isActive = false;
        _removeInactiveInvoice(invoice.companyWallet, _invoiceId);

        emit TokensRedeemed(_invoiceId, msg.sender, soldTokens, redemptionAmount);
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

    /**
     * @dev Function to fetch user tokens. 
     * @param user The address of the user.
     */
    function getPurchasedTokens(
        address user
    ) external view returns (uint256[] memory) {
        return userPurchasedTokens[user];
    }

    /**
     * @dev Function to fetch company active invoices. 
     * @param company The address of the company.
     */
    function getCompanyActiveInvoices(
        address company
    ) external view returns (uint256[] memory) {
        require(msg.sender == company, "Not authorized");
        return companyActiveInvoices[company];
    }

    // Fallback and receive functions to accept ETH
    receive() external payable {}
    fallback() external payable {}
}
