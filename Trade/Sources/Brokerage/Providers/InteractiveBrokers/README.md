# Interactive Brokers Configuration

This directory contains the Interactive Brokers integration for TradeUI. To configure your IB connection without modifying code, you can use the following environment variables:

## Available Environment Variables

| Variable Name | Description | Default Value |
|---------------|-------------|---------------|
| `IB_ACCOUNT_ID` | Your Interactive Brokers account ID | Empty string (falls back to first available account) |
| `IB_HOST` | The host address for the IB Gateway or TWS | `127.0.0.1` |
| `IB_PORT` | The port number for the IB Gateway or TWS | `4002` (default IB Gateway port) |

## Setting Environment Variables

### On macOS

You can set environment variables in your shell profile (`.bash_profile`, `.zshrc`, etc.):

```bash
# Add these lines to your shell profile
export IB_ACCOUNT_ID="your_account_id_here"
export IB_HOST="127.0.0.1"
export IB_PORT="4002"
```

Then reload your shell profile:

```bash
source ~/.zshrc  # or ~/.bash_profile depending on your shell
```

### In Xcode

To set environment variables for running the app from Xcode:

1. Select your scheme from the menu bar
2. Click "Edit Scheme..."
3. Go to the "Run" tab
4. Select the "Arguments" section
5. Add your environment variables in the "Environment Variables" section

## How It Works

The `InteractiveBrokers+Configuration.swift` extension provides a `Configuration` struct that reads these environment variables using `ProcessInfo.processInfo.environment`.

The `getDefaultAccount()` method will:
1. First check if `IB_ACCOUNT_ID` is set in the environment variables
2. If set, it will use that account ID
3. If not set, it will fall back to using the first available account

This approach makes it easy to switch between different accounts or environments without modifying the source code.