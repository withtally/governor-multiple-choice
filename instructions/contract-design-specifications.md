# Multiple Choice Governor Contract Specifications

## GovernorCountingMultipleChoice.sol

### Overview
The `GovernorCountingMultipleChoice` extends the OpenZeppelin `GovernorCountingSimple` contract to support multiple choice options while maintaining backward compatibility with the original interface.

### State Variables
```solidity
// Options for a specific proposal
mapping(uint256 => string[]) private _proposalOptions;

// Votes cast for each option
mapping(uint256 => mapping(uint8 => uint256)) private _proposalOptionVotes;

// Number of options per proposal
mapping(uint256 => uint8) private _proposalOptionCount;

// Maximum number of options a proposal can have
uint8 public constant MAX_OPTIONS = 10;

// Minimum number of options a proposal should have
uint8 public constant MIN_OPTIONS = 2;
```

### Key Functions

#### Propose Function
```solidity
function propose(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    string memory description,
    string[] memory optionDescriptions
) public virtual returns (uint256)
```

- Extends the original `propose` function to accept option descriptions
- Validates that option count is between MIN_OPTIONS and MAX_OPTIONS
- Stores options in contract storage
- Returns the proposal ID

#### Cast Vote Functions
```solidity
function castVote(uint256 proposalId, uint8 support) public virtual returns (uint256)
function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) public virtual returns (uint256)
function castVoteWithReasonAndParams(uint256 proposalId, uint8 support, string calldata reason, bytes memory params) public virtual returns (uint256)
```

- Maintains compatibility with the original vote casting interface
- Extends `support` parameter semantics:
  - `0`: Against (unchanged)
  - `1`: For (unchanged)
  - `2`: Abstain (unchanged)
  - `3+`: Additional options (mapping to option index - 3)

#### Vote Counting
```solidity
function _countVote(
    uint256 proposalId,
    address account,
    uint8 support,
    uint256 weight,
    bytes memory params
) internal virtual override
```

- Overrides the original vote counting implementation
- Handles both standard votes (0-2) and multiple choice options (3+)
- Validates that the option is valid for the proposal

#### Option Queries
```solidity
function proposalOptions(uint256 proposalId) public view returns (string[] memory)
function proposalOptionCount(uint256 proposalId) public view returns (uint8)
function proposalOptionVotes(uint256 proposalId, uint8 optionIndex) public view returns (uint256)
```

- View functions to query proposal options and vote counts
- Provides transparency for all options

### Events
```solidity
event ProposalOptionsCreated(uint256 proposalId, string[] options);
```

- New event emitted when a proposal with multiple options is created

## MultipleChoiceEvaluator.sol

### Overview
The `MultipleChoiceEvaluator` contract provides evaluation logic for multiple choice proposals, determining outcomes based on various counting rules.

### State Variables
```solidity
// Interface to the Governor contract
IGovernor public governor;

// Evaluation strategy for each proposal
mapping(uint256 => EvaluationStrategy) public proposalEvaluationStrategies;

// Enum of possible evaluation strategies
enum EvaluationStrategy {
    Plurality,       // Option with most votes wins
    Majority,        // Option must have > 50% of votes
    RankedChoice,    // Ranked choice voting
    Custom           // Custom evaluation logic
}
```

### Key Functions

#### Set Evaluation Strategy
```solidity
function setEvaluationStrategy(uint256 proposalId, EvaluationStrategy strategy) public
```

- Sets the evaluation strategy for a proposal
- Can only be called by authorized accounts

#### Evaluate Proposal
```solidity
function evaluateProposal(uint256 proposalId) public view returns (uint8 winningOption, bool isValid)
```

- Evaluates a proposal to determine the winning option
- Returns the winning option index and whether the result is valid based on the strategy

#### Execute Based on Result
```solidity
function executeProposal(uint256 proposalId) public
```

- Evaluates the proposal and triggers execution if valid
- Forwards execution to the appropriate contract based on the winning option

#### Strategy-Specific Evaluation
```solidity
function _evaluatePlurality(uint256 proposalId) internal view returns (uint8, bool)
function _evaluateMajority(uint256 proposalId) internal view returns (uint8, bool)
function _evaluateRankedChoice(uint256 proposalId) internal view returns (uint8, bool)
```

- Implementation of specific evaluation strategies
- Returns the winning option and validity status

## MultipleChoiceGovernorExample.sol

### Overview
The `MultipleChoiceGovernorExample` contract demonstrates a complete implementation of a Governor using the multiple choice module.

### Key Components
```solidity
contract MultipleChoiceGovernorExample is
    Governor,
    GovernorCountingMultipleChoice,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    constructor(
        IVotes _token,
        TimelockController _timelock
    ) Governor("MultipleChoiceGovernor") GovernorVotes(_token) GovernorVotesQuorumFraction(4) GovernorTimelockControl(_timelock) {}
    
    // Implementation of required functions
    function votingDelay() public pure override returns (uint256) { return 7200; } // 1 day
    function votingPeriod() public pure override returns (uint256) { return 50400; } // 1 week
    function proposalThreshold() public pure override returns (uint256) { return 0; }
    
    // Required overrides for compatibility with other governor modules
    // ...
}
```

### Integration with MultipleChoiceEvaluator
```solidity
// In the example implementation
MultipleChoiceEvaluator public evaluator;

function setEvaluator(MultipleChoiceEvaluator _evaluator) public onlyGovernance {
    evaluator = _evaluator;
}

function executeWithEvaluator(uint256 proposalId) public {
    evaluator.executeProposal(proposalId);
}
``` 