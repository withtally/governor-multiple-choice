# Setup Instructions for Multiple Choice Governor

## Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
- Git

## Project Setup

1. Initialize a new Forge project:
```bash
forge init forge-project
cd forge-project
```

2. Install OpenZeppelin contracts:
```bash
forge install OpenZeppelin/openzeppelin-contracts
```

3. Configure remappings in `foundry.toml`:
```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
remappings = [
    "@openzeppelin/=lib/openzeppelin-contracts/",
]
```

## Project Structure

Create the following directory structure:
```
forge-project/
├── src/
│   ├── GovernorCountingMultipleChoice.sol
│   ├── MultipleChoiceEvaluator.sol
│   └── example/
│       └── MultipleChoiceGovernorExample.sol
├── test/
│   ├── GovernorCountingMultipleChoice.t.sol
│   └── integration/
│       └── MultipleChoiceGovernorIntegration.t.sol
└── script/
    └── DeployMultipleChoiceGovernor.s.sol
```

## Development Workflow

1. Start by implementing the core `GovernorCountingMultipleChoice` module
2. Create unit tests to validate vote counting logic
3. Implement the `MultipleChoiceEvaluator` contract
4. Create integration tests with example Governor implementation
5. Set up fork tests to validate compatibility with existing systems

## Testing

Run tests with:
```bash
forge test
```

For verbose output:
```bash
forge test -vvv
```

For fork testing against live contracts:
```bash
forge test --fork-url <RPC_URL> --match-path test/integration/*.sol
```

## Gas Optimization

Analyze gas usage:
```bash
forge snapshot
```

Compare gas usage after changes:
```bash
forge snapshot --diff
```

## Deployment

Create a deployment script:
```bash
forge script script/DeployMultipleChoiceGovernor.s.sol --rpc-url <RPC_URL> --broadcast
``` 