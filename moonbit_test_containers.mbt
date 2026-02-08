// Testcontainers for MoonBit
// A library for creating and managing Docker containers for integration testing
//
// This file previously contained the monolithic implementation.
// The code has been refactored into modular files:
// - types.mbt: Type definitions and builder methods
// - container.mbt: Container lifecycle management
// - docker.mbt: Docker CLI execution utilities
// - error.mbt: Error handling
// - logs.mbt: Container logging functionality
// - wait_strategy.mbt: Wait strategies for container readiness
