# DeltaOperator

Integration layer between [Delta](https://github.com/rileytestut/Delta) and OperatorKit for [Epilogue](https://www.epilogue.co) Operator devices. Bridges cartridge lifecycle events, save data management, and UI state to Delta's emulation engine.

## Features

* Cartridge save writeback with change detection
* Periodic SRAM flush for cores without save callbacks
* Original save backup and restore for pre-existing games
* Operator status cell injection in game collection grids
* Overlay coordinator for the "No Games" placeholder

## Requirements

* iOS 16+
* Swift 5.9+
* [DeltaCore](https://github.com/rileytestut/DeltaCore)
* OperatorKit
* [Roxas](https://github.com/rileytestut/Roxas)
