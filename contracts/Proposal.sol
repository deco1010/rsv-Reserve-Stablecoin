pragma solidity ^0.5.8;

import "./zeppelin/token/ERC20/IERC20.sol";
import "./zeppelin/token/ERC20/SafeERC20.sol";
import "./ownership/Ownable.sol";
import "./Basket.sol";

/**
 * A Proposal represents a suggestion to change the backing for RSV.
 *
 * The lifecycle of a proposal:
 * 1. Creation
 * 2. Acceptance
 * 3. Completion
 *
 * A time can be set during acceptance to determine when completion is eligible.
 * A proposal can also be closed before it is Completed. 
 *
 * This contract is intended to be used in one of two possible ways. Either:
 * - A target RSV basket is suggested, and quantities to be exchanged are  
 *     deduced at the time of proposal execution.
 * - A specific quantity of tokens to be exchanged is suggested, and the 
 *     resultant RSV basket is determined at the time of proposal execution.
 *
 */

contract Proposal is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public time;
    address public proposer;

    enum State { Created, Accepted, Cancelled, Completed }
    State public state;
    
    constructor(address _proposer) public {
        proposer = _proposer;
        state = State.Created;
    }

    /// Moves a proposal from the Created to Accepted state. 
    function accept(uint256 _time) external onlyOwner {
        require(state == State.Created, "proposal not created");
        time = _time;
        state = State.Accepted;
    }

    /// Cancels a proposal if it has not been completed. 
    function cancel() external onlyOwner {
        require(state != State.Completed);
        state = State.Closed;
    }

    /// Moves a proposal from the Accepted to Completed state.
    /// Returns the tokens, quantitiesIn, and quantitiesOut, required to implement the proposal.
    function complete(uint256 rsvSupply, address vaultAddr, Basket prevBasket) 
        external onlyOwner returns(Basket)
    {
        require(state == State.Accepted, "proposal must be accepted");
        require(now > time, "wait to execute");
        state = State.Completed;

        return _newBasket(rsvSupply, vaultAddr, prevBasket);
    }

    /// Returns the newly-proposed basket, and the tokens, quantitiesIn, and quantitiesOut
    /// required to implement the proposal.  This varies for different types of proposals,
    /// so it's abstract here.
    function _newBasket(uint256 rsvSupply, uint8 rsvDecimals, address vault, Basket oldBasket)
        internal view returns(Basket);

    /// _has returns true iff _addr is in _addrArray.
    function _has(address[] memory _addrArray, address _addr) internal pure returns(bool) {
        for (uint i = 0; i < _addrArray.length; i++) {
            if (_addrArray[i] == _addr) return true;
        }
        return false;
    }
}

contract SwapProposal is Proposal {
    address public proposer;
    IERC20[] public tokens;
    uint256[] public amounts;
    bool[] public toVault;

    constructor(address _proposer,
                IERC20[] memory _tokens,
                uint256[] memory _amounts,
                bool[] memory _toVault )
        Proposal(_proposer) public
    {
        require(_tokens.length == _amounts.length && _amounts.length == _toVault.length,
                "unequal array lengths");
        tokens = _tokens;
        amounts = _amounts;
        toVault = _toVault;
    }

    /// Return the newly-proposed basket, based on the current vault and the old basket
    function _newBasket(uint256 rsvSupply, uint8 rsvDecimals, address vault, Basket oldBasket)
        internal view returns(Basket) {
        // Compute new basket
        uint256[] memory weights;
        
        for (uint i = 0; i < tokens.length; i++) {
            uint256 newAmount;

            if (toVault[i]) {
                newAmount = tokens[i].balanceOf(vault).add(amounts[i]);
            } else {
                newAmount = tokens[i].balanceOf(vault).sub(amounts[i]);
            }

            // TODO(elder): it'd maybe be clearer if oldBasket and rsvSupply here were replaced with
            // just a reference to the RSV contract.

            // TODO(elder): how do you correctly deal with rounding error here?
            weights.push(newAmount.mul(10**rsvDecimals).div(rsvSupply));
        }

        return new Basket(oldBasket, tokens, weights);
    }
}

contract WeightProposal is Proposal {
    Basket public basket;

    constructor(address _proposer, Basket _basket)
        Proposal(_proposer) public {
        basket = _basket;
    }

    /// Returns the newly-proposed basket
    function _newBasket(uint256 rsvSupply, uint8 rsvDecimals, address vault, Basket oldBasket)
        internal view returns(Basket) {
        return basket;
    }
}
