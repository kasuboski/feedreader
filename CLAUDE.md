# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a minimal RSS/feed reader web application built in Rust, designed as a self-hosted alternative to services like Miniflux. The application provides a simple web interface for managing and reading RSS feeds with LibSQL/SQLite storage.

## Development Setup

### Environment Management
The project uses **direnv** for automatic environment loading:
- `direnv allow` - Allow direnv to load the environment automatically
- `direnv exec . <command>` - Run commands with the environment loaded (e.g., `direnv exec . cargo test`)

The `.envrc` file configures the Nix flake development environment automatically when entering the project directory.

## Development Commands

### Building and Running
- `cargo build` - Build the application
- `cargo run` - Run the development server
- `just build` - Build using Earthly (containerized build)
- `cargo test` - Run all tests

### Container and Deployment
- `just image` - Build and push container image
- `just multiarch-push` - Push multi-architecture images
- `just list-images` - List available container images
- `just local-workflow` - Run GitHub Actions locally with act

### Nix Development
- `nix develop` - Enter development shell with all dependencies
- `just cache-nix` - Cache Nix build artifacts to Cachix

## Architecture

### Core Components
- **`src/main.rs`** - Application entry point, HTTP server setup, and background feed processing logic
- **`src/db.rs`** - Database abstraction layer with LibSQL operations and connection management
- **`src/view.rs`** - Web route handlers and Askama template rendering

### Technology Stack
- **Web Framework**: Axum v0.7 with async/await
- **Database**: LibSQL (SQLite-compatible) with optional Turso remote sync
- **Templating**: Askama (compile-time Jinja-like templates)
- **Feed Parsing**: feed-rs library for RSS/Atom parsing
- **HTTP Client**: Reqwest with rustls-tls for feed fetching

### Key Features
- Background feed refresh (configurable interval, default 3 minutes)
- OPML import/export for feed management
- Entry marking (read/starred status)
- Local SQLite or remote Turso database support
- Server-rendered HTML with TurretCSS styling

## Database Schema

The application uses two main tables:
- **feeds** - RSS feed metadata (name, URLs, fetch status, categories)
- **entries** - Individual feed entries (title, content, read/starred status, timestamps)

Database connection uses separate read/write pools configured via environment variables:
- `DATABASE_URL` - Primary database connection
- `DATABASE_READ_URL` - Optional read replica connection

## Environment Configuration

Key environment variables:
- `DATABASE_URL` - LibSQL database connection string
- `FEED_FETCH_INTERVAL_MINUTES` - How often to refresh feeds (default: 3)
- `RUST_LOG` - Logging level configuration

## Testing

Tests are integrated into source files using Rust's built-in testing framework:
- Unit tests in `src/main.rs` for OPML parsing
- Async database tests in `src/db.rs` 
- Template rendering tests in `src/view.rs`

Run tests with `cargo test` - no additional test framework setup required.

## Build Tools

The project uses multiple build systems:
- **Cargo** - Standard Rust package manager and build tool
- **Just** - Task runner (modern Make alternative) defined in Justfile
- **Earthly** - Containerized builds for reproducible artifacts
- **Nix** - Development environment and dependency management
- **direnv** - Automatic environment loading via Nix flake

Use `just` without arguments to see available commands.