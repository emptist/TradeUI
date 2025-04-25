# **TradeUI**

![Swift Version](https://img.shields.io/badge/Swift-6.1-orange.svg) ![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-blue.svg) ![Linux](https://img.shields.io/badge/Linux-compatible-green.svg)
 [![SPM](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-blue.svg)](https://github.com/apple/swift-package-manager) ![Swift](https://img.shields.io/badge/Swift-5.0-orange) ![Platforms](https://img.shields.io/badge/platforms-macOS-blue) ![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)

## Overview

**TradeUI** is a Swift-based package and application built with **SwiftUI**, designed for trade visualization and analysis. It features both a graphical user interface (GUI) application and a command-line interface (CLI) for diverse use cases. The repository is modular, making it easy to extend and integrate with additional trading strategies and tools.

---

## Installation

### Prerequisites

1. **Xcode**: Ensure Xcode (version supporting Swift 6.1 or higher) is installed.
2. **Swift Package Manager (SPM)**: TradeUI uses SPM for dependency management.

### Steps

1. Clone the repository:
    ```bash
    git clone https://github.com/TradeWithIt/TradeUI.git
    cd TradeUI
    ```
2. Open the Xcode project:
    ```bash
    open TradeUI.xcodeproj
    ```
3. Build and run the application:
    - Select your desired target (simulator or device).
    - Press `Cmd + R` to run the application.

---

## Architecture & Runtime

TradeUI is organized into several Swift Package modules and targets, enabling a scalable and reusable architecture:

### Main Targets
- **Brokerage**: Manages broker integration (e.g., IBKit).
- **Persistence**: Provides trade data storage and caching.
- **Runtime**: Core runtime for data processing and trade monitoring.
- **TradeInterface**: The main module powering the SwiftUI-based graphical interface.
- **TradeCLI**: Command-line interface for trade management and strategy simulation.

### Key Features
- **Declarative UI**: Powered by SwiftUI for building intuitive interfaces.
- **Modular Design**: Designed for scalability and reusability.
- **Reactive Programming**: Uses Combine framework for handling asynchronous data streams.

### Dependencies
TradeUI integrates several libraries and tools:
- **Core Dependencies**:
  - [SwiftUIComponents](https://github.com/shial4/SwiftUIComponents)
  - [IBKit](https://github.com/TradeWithIt/IBKit)
  - [ForexFactory](https://github.com/TradeWithIt/ForexFactory)
  - [Strategy](https://github.com/TradeWithIt/Strategy)
- **Tools**:
  - [Swift Collections](https://github.com/apple/swift-collections)
  - [Swift Argument Parser](https://github.com/apple/swift-argument-parser)

### Supported Platforms
- iOS 17+
- macOS 15+
- The package is **pure Swift** and runs on all supported Swift platforms using **Foundation**.

---

## Application Screenshots

Here are some screenshots showcasing the application:

### Main Window
![Main Window](https://github.com/TradeWithIt/TradeUI/blob/main/Assets/main_window.png)

### System Application Bar
![System Application Bar](https://github.com/TradeWithIt/TradeUI/blob/main/Assets/bar_window.png)

### Watcher Preview Window
![Watcher Preview Window](https://github.com/TradeWithIt/TradeUI/blob/main/Assets/watcher_window.png)

These screenshots provide a visual overview of the application's key components and interface.

---

## Sub-Package

This repository also includes a **pure Swift sub-package**, located in the `Trade` directory. The sub-package is designed for maximum portability and compatibility with all Swift-supported platforms.

### Key Highlights of the Sub-Package:
- **Name**: `TradeApp`
- **Modules**:
  - `Brokerage`: Handles broker interactions and integrations.
  - `Persistence`: Manages storage and caching.
  - `Runtime`: Provides the core runtime logic.
  - `TradeInterface`: Powers the user interface components.
  - `TradeCLI`: CLI tool for managing and analyzing trade data.
- **Foundation-Based**: The sub-package builds upon the Foundation framework for cross-platform compatibility.
- **Targets**:
  - A **library** target (`TradeInterface`) for integrating with other projects.
  - An **executable** target (`TradeCLI`) for command-line operation.

The sub-package is self-contained and can be used independently as a Swift Package by importing it into your own projects.

---

## CLI Tool

TradeUI includes a command-line interface (CLI) for accessing key features programmatically.

### Features
- Fetch and display trade data.
- Simulate and test trading strategies.
- Export trade data to JSON or CSV formats.

### Usage
1. Navigate to the CLI target:
    ```bash
    cd Trade
    ```
2. Build the CLI:
    ```bash
    swift build
    ```
3. Run the CLI:
    ```bash
    .build/debug/TradeCLI --help
    ```

#### Output
```
Trade % swift run TradeCLI help
Building for debugging...
[1/1] Write swift-version--4143C679E9773007.txt
Build of product 'TradeCLI' complete! (0.49s)
TradeWithIt: A command-line interface for TradeApp
TradeWithIt enables algorithmic trading by integrating market analysis tools and trading strategies. It leverages:
- TradeUI: Provides market data and analysis tools for stocks and options, powered by APIs and AI-driven insights.
  Learn more: https://github.com/TradeWithIt/TradeUI
- Strategy: Implements trading strategies for automated trade execution.
  Learn more: https://github.com/TradeWithIt/Strategy

Usage:
  TradeWithIt <subcommand> [options]

Subcommands:
  help    Display this help information
  trade   Execute a trading strategy with an instrument (type, symbol, exchange, currency)

For detailed help on a subcommand, run:
  TradeWithIt <subcommand> --help
  
Trade Subcommand Arguments:
  <strategyFile>    Path to the .dylib file containing the trading strategy
  <type>            Instrument type (default: FUT)
  <symbol>          Trading symbol (default: ESM5)
  <interval>        Market data interval in seconds (default: 60)
  <exchange>        Exchange ID (default: CME)
  <currency>        Currency (default: USD)
  --verbose, -v     Enable verbose output for trade details

Examples:
  TradeWithIt trade /path/to/strategy.dylib FUT ESM5 60 CME USD
  TradeWithIt trade /path/to/strategy.dylib --verbose
  TradeWithIt help
  TradeWithIt trade --help

For detailed help on a subcommand, run:
  TradeWithIt <subcommand> --help

```

---

## Incorporating Your Own Strategies

TradeUI is designed to integrate custom trading strategies seamlessly. The **[Strategy](https://github.com/TradeWithIt/Strategy)** package provides a framework for creating, testing, and deploying custom strategies.

### Steps to Add Your Strategy
1. Clone the **Strategy** repository:
    ```bash
    git clone https://github.com/TradeWithIt/Strategy.git
    ```
2. Implement your strategy following the guidelines in the repository.
3. Link your strategy to TradeUI by updating the `Package.swift` file:
    ```swift
    .package(url: "https://github.com/your_username/YourStrategy.git", branch: "main"),
    ```

### Build your strategy as `dynamic lib` file, and select it's folder location from the **TradeUI** app. 

---

## Legal Disclaimer, License, and Contribution

### Legal Disclaimer
TradeUI is provided for educational and informational purposes only. **It is not intended for live trading**, and the maintainers are not responsible for any financial losses.

### License
This project is licensed under the **MIT License**. View the [LICENSE](./LICENSE) file for more details.

### Contribution
Contributions are welcome! To contribute:
1. Fork the repository.
2. Create a feature branch.
3. Submit a pull request with a detailed description of your changes.

For suggestions or issues, open a new issue in this repository.
