# Multiple Choice Governor Testing Checklist

## GovernorCountingMultipleChoice Tests

### Proposal Creation
- [ ] Creating a standard proposal (without options)
- [ ] Creating a multiple choice proposal (with options)
- [ ] Creating a proposal with minimum number of options (2 options)
- [ ] Creating a proposal with maximum number of options (10 options)
- [ ] Attempting to create a proposal with too few options (should revert)
- [ ] Attempting to create a proposal with too many options (should revert)
- [ ] Verifying options are stored correctly
- [ ] Verifying option count is stored correctly
- [ ] Verifying ProposalOptionsCreated event is emitted correctly

### Vote Casting
- [ ] Casting standard votes (For, Against, Abstain) on a standard proposal
- [ ] Casting standard votes on a multiple choice proposal
- [ ] Casting multiple choice votes on a multiple choice proposal
- [ ] Attempting to cast a multiple choice vote on a standard proposal (should revert)
- [ ] Attempting to cast a vote for an invalid option index (should revert)
- [ ] Verifying vote weights are counted correctly
- [ ] Testing vote delegation and its impact on vote counting
- [ ] Testing vote delegation change mid-proposal

### Vote Counting
- [ ] Verifying standard proposalVotes function returns correct counts
- [ ] Verifying proposalAllVotes function returns all vote counts
- [ ] Verifying proposalOptionVotes returns individual option vote counts
- [ ] Verifying vote counts when no votes are cast

### State Transitions
- [ ] Testing proposal state transitions (Pending → Active → Succeeded/Defeated)
- [ ] Testing quorum calculation with standard votes
- [ ] Testing quorum calculation with multiple choice votes
- [ ] Testing proposal cancellation

## MultipleChoiceEvaluator Tests

### Plurality Evaluation
- [ ] Testing basic plurality evaluation (highest vote wins)
- [ ] Testing plurality with tied votes
- [ ] Testing plurality with no votes cast
- [ ] Testing plurality with single option receiving votes

### Majority Evaluation
- [ ] Testing majority evaluation with clear majority (>50%)
- [ ] Testing majority evaluation with no clear majority
- [ ] Testing majority with exact 50% (not a majority)
- [ ] Testing majority with no votes cast

### Other Evaluation Strategies
- [ ] Testing unsupported strategies (should revert)
- [ ] Testing custom strategy implementations

### Administrative Functions
- [ ] Testing setEvaluationStrategy function
- [ ] Testing updating the governor address
- [ ] Testing authorization controls

## Integration Tests

### End-to-End Workflow
- [ ] Complete workflow: proposal creation → voting → evaluation → execution
- [ ] Testing with TimelockController integration
- [ ] Testing with different token types (ERC20Votes, ERC721Votes)

### Compatibility
- [ ] Verifying compatibility with standard Governor functions
- [ ] Verifying compatibility with GovernorVotes module
- [ ] Verifying compatibility with GovernorTimelockControl module
- [ ] Verifying compatibility with GovernorSettings module

## Edge Cases and Security

### Edge Cases
- [ ] Testing with extremely large vote counts
- [ ] Testing with maximum number of voters
- [ ] Testing with maximum gas consumption scenarios
- [ ] Testing proposal execution based on different winning options

### Security
- [ ] Testing against double voting
- [ ] Testing against option manipulation
- [ ] Testing authorization boundaries
- [ ] Testing reentrancy protection

## Fork Tests

### Mainnet Compatibility
- [ ] Testing deployment and integration with live governance contracts
- [ ] Testing against existing multiple choice proposals (if any)
- [ ] Testing against popular governance implementations (Compound, Uniswap, etc.)

## Gas Optimization

### Gas Analysis
- [ ] Measuring gas usage for proposal creation
- [ ] Measuring gas usage for vote casting
- [ ] Measuring gas usage for evaluation
- [ ] Comparing gas usage with standard Governor implementations

## Documentation Verification

### Documentation Tests
- [ ] Verifying example code in documentation works correctly
- [ ] Verifying interfaces are documented correctly
- [ ] Verifying events are documented correctly
- [ ] Verifying error messages are documented correctly 