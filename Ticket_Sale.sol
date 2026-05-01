// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract NFTTicketing is ERC721, AccessControl, ERC2981, ReentrancyGuard {

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    uint256 public ticketCount;
    uint256 public maxSupply;
    uint256 public ticketPrice;

    string public eventName;

    uint256 public saleStart;
    uint256 public saleEnd;

    uint256 public constant MAX_PER_WALLET = 5;

    mapping(uint256 => bool) public isUsed;
    mapping(address => uint256) public mintedPerWallet;

    event TicketMinted(address indexed buyer, uint256 indexed tokenId);
    event TicketUsed(uint256 indexed tokenId, address indexed validator);
    event Withdrawn(address indexed admin, uint256 amount);

    constructor(
        string memory _eventName,
        uint256 _maxSupply,
        uint256 _ticketPrice,
        uint256 _saleStart,
        uint256 _saleEnd,
        address royaltyReceiver,
        uint96 royaltyFee
    ) ERC721("EventTicket", "ETKT") {

        require(royaltyFee <= 10000, "Royalty too high");
        require(_saleEnd > _saleStart, "Invalid time");

        eventName = _eventName;
        maxSupply = _maxSupply;
        ticketPrice = _ticketPrice;
        saleStart = _saleStart;
        saleEnd = _saleEnd;

        _setDefaultRoyalty(royaltyReceiver, royaltyFee);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function mintTicket() external payable nonReentrant {
        require(block.timestamp >= saleStart, "Sale not started");
        require(block.timestamp <= saleEnd, "Sale ended");
        require(ticketCount < maxSupply, "Sold out");
        require(msg.value >= ticketPrice, "Insufficient payment");
        require(mintedPerWallet[msg.sender] < MAX_PER_WALLET, "Limit reached");

        ticketCount++;
        mintedPerWallet[msg.sender]++;

        uint256 tokenId = ticketCount;
        _safeMint(msg.sender, tokenId);

        uint256 excess = msg.value - ticketPrice;
        if (excess > 0) {
            (bool refunded, ) = payable(msg.sender).call{value: excess}("");
            require(refunded, "Refund failed");
        }

        emit TicketMinted(msg.sender, tokenId);
    }

    function validateTicket(uint256 tokenId) external onlyRole(VALIDATOR_ROLE) {
        require(_ownerOf(tokenId) != address(0), "Invalid ticket");
        require(!isUsed[tokenId], "Already used");

        isUsed[tokenId] = true;

        emit TicketUsed(tokenId, msg.sender);
    }

    function addValidator(address validator) external onlyRole(ADMIN_ROLE) {
        _grantRole(VALIDATOR_ROLE, validator);
    }

    function removeValidator(address validator) external onlyRole(ADMIN_ROLE) {
        _revokeRole(VALIDATOR_ROLE, validator);
    }

    function withdraw() external onlyRole(ADMIN_ROLE) nonReentrant {
        uint256 amount = address(this).balance;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdraw failed");

        emit Withdrawn(msg.sender, amount);
    }

    
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address from) {
        from = super._update(to, tokenId, auth);

        
        if (from != address(0)) {
            require(!isUsed[tokenId], "Used ticket cannot transfer");
        }
    }

    function isTicketValid(uint256 tokenId) external view returns (bool) {
        return _ownerOf(tokenId) != address(0) && !isUsed[tokenId];
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}