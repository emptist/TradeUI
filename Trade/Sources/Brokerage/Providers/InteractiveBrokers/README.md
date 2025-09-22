# Interactive Brokers Configuration

This directory contains the Interactive Brokers integration for TradeUI. To configure your IB account ID without modifying code, you can use the following environment variable:

## Available Environment Variables

| Variable Name | Description | Default Behavior |
|---------------|-------------|------------------|
| `IB_ACCOUNT_ID` | Your Interactive Brokers account ID | Falls back to first available account if not set |

## Setting Environment Variables

### On macOS

You can set the environment variable in your shell profile (`.bash_profile`, `.zshrc`, etc.):

```bash
# Add this line to your shell profile
export IB_ACCOUNT_ID="your_account_id_here"
```

Then reload your shell profile:

```bash
source ~/.zshrc  # or ~/.bash_profile depending on your shell
```

### In Xcode

To set the environment variable for running the app from Xcode:

1. Select your scheme from the menu bar
2. Click "Edit Scheme..."
3. Go to the "Run" tab
4. Select the "Arguments" section
5. Add `IB_ACCOUNT_ID` with your account ID in the "Environment Variables" section

## How It Works

The `InteractiveBrokers+Configuration.swift` extension provides a `Configuration` struct that reads the `IB_ACCOUNT_ID` environment variable using `ProcessInfo.processInfo.environment`.

The `getDefaultAccount()` method will:
1. First check if `IB_ACCOUNT_ID` is set in the environment variables
2. If set, it will use that account ID
3. If not set, it will fall back to using the first available account

This approach makes it easy to switch between different accounts without modifying the source code.

> Note: Host and port configurations are handled internally based on the selected connection type (gateway or workstation) and trading mode (live or paper).