// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {ERC721BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import {StringsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

import {PermissionControl, AccessControlUpgradeable} from "./permission/PermissionControl.sol";
import {IRandom} from "./interfaces/IRandom.sol";

contract CardNFT is
    PermissionControl,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    ERC721BurnableUpgradeable
{
    using StringsUpgradeable for uint256;

    string private baseUrl;
    uint256 public currentTokenId;

    IRandom private random;

    function initialize(
        string memory name_,
        string memory symbol_,
        IRandom _random
    ) external initializer {
        __PermissionControl_init();
        __ERC721_init(name_, symbol_);
        currentTokenId = 12385;
        random = _random;
    }

    function ownerOfAddr(address cardAddr) external view returns (address) {
        return ownerOf(uint256(uint160(cardAddr)));
    }

    function safeMint(address to) external returns (address) {
        uint256 tokenId = currentTokenId;
        _safeMint(to, tokenId);
        _setTokenURI(
            tokenId,
            string(abi.encodePacked(tokenId.toString(), ".json"))
        );
        random.update();
        uint256 add = random.seed() % 100;
        currentTokenId += add > 0 ? add : 1;
        return address(uint160(tokenId));
    }

    function minInit(
        address to,
        uint256 tokenId
    ) external onlyRole(MANAGER_ROLE) {
        require(tokenId < 12385, "error");
        _safeMint(to, tokenId);
    }

    function setBaseUrl(
        string calldata _baseUrl
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        baseUrl = _baseUrl;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    function _burn(
        uint256 tokenId
    ) internal override(ERC721Upgradeable, ERC721URIStorageUpgradeable) {
        super._burn(tokenId);
    }

    function tokenURI(
        uint256 tokenId
    )
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(
            AccessControlUpgradeable,
            ERC721EnumerableUpgradeable,
            ERC721Upgradeable
        )
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseUrl;
    }
}
