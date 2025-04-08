# Multiple Choice Governor Testing Checklist

## GovernorCountingMultipleChoice Tests

### Proposal Creation
- [x] Creating a standard proposal (without options)
- [x] Creating a multiple choice proposal (with options)
- [x] Creating a proposal with minimum number of options (2 options)
- [x] Creating a proposal with maximum number of options (10 options)
- [x] Attempting to create a proposal with too few options (should revert)
- [x] Attempting to create a proposal with too many options (should revert)
- [x] Verifying options are stored correctly
- [x] Verifying option count is stored correctly
- [x] Verifying ProposalOptionsCreated event is emitted correctly
  - *Note: Current test only checks emission, not exact proposalId topic or options data. Consider using `vm.recordLogs` for a more robust check later.*
- [x] Verifying ProposalCreated event is emitted correctly (Standard & MC)

### Vote Casting
- [x] Casting standard votes (For, Against, Abstain) on a standard proposal
- [x] Casting standard votes on a multiple choice proposal
- [x] Casting multiple choice votes on a multiple choice proposal
- [x] Attempting to cast a multiple choice vote on a standard proposal (should revert)
- [x] Attempting to cast a vote for an invalid option index (should revert)
- [x] Verifying vote weights are counted correctly
- [x] Testing vote delegation and its impact on vote counting
- [x] Testing vote delegation change mid-proposal
- [x] Verifying VoteCast event is emitted correctly (Standard)
- [x] Verifying VoteCastWithParams event is emitted correctly (Multiple Choice)

### Vote Counting
- [x] Verifying standard proposalVotes function returns correct counts
- [x] Verifying proposalAllVotes function returns all vote counts
- [x] Verifying proposalOptionVotes returns individual option vote counts
- [x] Verifying vote counts when no votes are cast

### State Transitions
- [x] Testing proposal state transitions (Pending → Active → Succeeded/Defeated)
- [x] Testing quorum calculation with standard votes
- [x] Testing quorum calculation with multiple choice votes
- [x] Testing reversion when voting after proposal ends

## MultipleChoiceEvaluator Tests

### Plurality Evaluation
- [x] Testing basic plurality evaluation (highest vote wins)
- [x] Testing plurality with tied votes
- [x] Testing plurality with no votes cast
- [x] Testing plurality with single option receiving votes

### Majority Evaluation
- [x] Testing majority evaluation with clear majority (>50%)
- [x] Testing majority evaluation with no clear majority
- [x] Testing majority with exact 50% (not a majority)
- [x] Testing majority with no votes cast

### Other Evaluation Strategies
- [x] Testing unsupported strategies (should revert)
- [ ] Testing custom strategy implementations // TODO: Requires defining a custom IEvaluator

### Administrative Functions
- [x] Testing setEvaluationStrategy function
- [x] Testing updating the governor address
- [x] Testing authorization controls (Ownable checks on setters)

## Integration Tests

### End-to-End Workflow
- [x] Complete workflow: proposal creation → voting → evaluation → execution (Tested Plurality, Majority, Standard, Quorum Failure)
- [x] Testing with TimelockController integration
- [x] Testing with different token types (ERC20Votes, ERC721Votes)
- [x] Testing execution not dependent on winning option (Fixed)

### Compatibility
- [x] Verifying compatibility with standard Governor functions
- [x] Verifying compatibility with GovernorVotes module
- [x] Verifying compatibility with GovernorTimelockControl module
- [x] Verifying compatibility with GovernorSettings module

## Edge Cases and Security

### Edge Cases
- [x] Testing with extremely large vote counts
- [ ] Testing with maximum number of voters // TODO
- [ ] Testing with maximum gas consumption scenarios // TODO: Gas snapshots added
- [x] Testing proposal execution based on different winning options (Fixed)

### Security
- [x] Testing against double voting
- [ ] Testing against option manipulation // TODO
- [x] Testing authorization boundaries (Propose Threshold pending contract mod, SetEvaluator tested)
- [x] Testing reentrancy protection (Basic check via attacker contract)

## Fork Tests

### Mainnet Compatibility
- [x] Testing deployment and integration with live governance contracts (Fixed setup with UNI - test skipped without RPC URL)
- [ ] Testing against existing multiple choice proposals (if any) // TODO: Research required
- [ ] Testing against popular governance implementations (Compound, Uniswap, etc.) // TODO: Research required

## Gas Optimization

### Gas Analysis
- [ ] Measuring gas usage for proposal creation // TODO: Snapshot added
- [ ] Measuring gas usage for vote casting // TODO: Snapshot added
- [ ] Measuring gas usage for evaluation // TODO: Snapshot added
- [ ] Comparing gas usage with standard Governor implementations // TODO

## Documentation Verification

### Documentation Tests
- [x] Verifying example code in documentation works correctly (Added to README)
- [x] Verifying interfaces are documented correctly (NatSpec added)
- [x] Verifying events are documented correctly (NatSpec added)
- [x] Verifying error messages are documented correctly (NatSpec added) 