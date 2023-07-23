// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "abdk-libraries-solidity/ABDKMath64x64.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NTCGMiddleman is ReentrancyGuard, AccessControl, Pausable {
    AggregatorV3Interface internal priceFeed;
    IERC20 public NTCG;
    bytes32 public constant GAME_BACKEND_ROLE = keccak256("GAME_BACKEND_ROLE");

    mapping(address => uint256) public fragmentsBalance;
    mapping(address => uint256) public pendingWithdrawals;

    constructor(address _NTCG, address _priceFeed, address _gameBackend) {
        NTCG = IERC20(_NTCG);
        priceFeed = AggregatorV3Interface(_priceFeed);
        _setupRole(GAME_BACKEND_ROLE, _gameBackend);
    }

    function getLatestNTCGPrice() public view returns (int) {
        (, int price,,,) = priceFeed.latestRoundData();
        return price;
    }

    function sellFragmentsForNTCG(address user, uint256 fragmentsAmount) public onlyRole(GAME_BACKEND_ROLE) nonReentrant whenNotPaused {
        require(fragmentsBalance[user] >= fragmentsAmount, "User doesn't have enough Fragments");
        fragmentsBalance[user] -= fragmentsAmount;

        int latestNTCGPrice = getLatestNTCGPrice();
        require(latestNTCGPrice > 0, "Price should be a positive number");

        int128 pricePerFragmentInNTCG = ABDKMath64x64.divu(1e18, uint64(uint256(latestNTCGPrice)));  // assuming each Fragment is worth 1 USD

        uint256 NTCGAmount = ABDKMath64x64.mulu(pricePerFragmentInNTCG, fragmentsAmount);
        require(NTCG.balanceOf(address(this)) >= NTCGAmount, "Contract does not have enough NTCG");

        pendingWithdrawals[user] += NTCGAmount;
    }

    function approveWithdrawal(address user) public onlyRole(GAME_BACKEND_ROLE) nonReentrant whenNotPaused {
        uint256 amount = pendingWithdrawals[user];
        require(NTCG.balanceOf(address(this)) >= amount, "Contract does not have enough NTCG");

        pendingWithdrawals[user] = 0;
        NTCG.transfer(user, amount);
    }

    function creditFragments(address user, uint256 fragmentsAmount) public onlyRole(GAME_BACKEND_ROLE) {
        fragmentsBalance[user] += fragmentsAmount;
    }

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function receiveNTCG(uint256 amount) external {
    require(NTCG.transferFrom(msg.sender, address(this), amount), "Transfer failed");
    }

    fallback() external payable {}
    receive() external payable {}

}
