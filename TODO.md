# UNO Game Refactoring TODO

## Completed ✓

### Phase 1: Test Infrastructure
- [x] Set up test infrastructure with uno_spec_helper.rb
- [x] Write comprehensive tests for domain objects:
  - [x] UnoCard (47 tests)
  - [x] Hand (34 tests)
  - [x] CardStack (22 tests)
  - [x] UnoPlayer (21 tests)
- [x] Start UnoGame tests (57 tests)
- [x] Fix bugs discovered during testing:
  - [x] Hand#reverse not reversing
  - [x] Hand#reverse! infinite recursion
  - [x] Hand#select incorrect block passing
  - [x] CardStack#fill not chainable

### Phase 2: Interface Extraction
- [x] Create Notifier interface for game notifications
  - [x] Implement NullNotifier for testing
  - [x] Implement ConsoleNotifier for CLI
  - [x] Implement IrcNotifier for IRC
- [x] Refactor UnoGame to use notifier interface
- [x] Create Renderer interface for card formatting
  - [x] Implement TextRenderer for plain text
  - [x] Implement IrcRenderer for IRC with color codes
  - [x] Implement HtmlRenderer for potential web interface
- [x] Update UnoGame to use renderer interface
- [x] Add deprecation warnings to IRC-specific methods
- [x] Create Repository interface for database operations
  - [x] Implement NullRepository for testing/casual games
  - [x] Implement SqliteRepository for production
  - [x] Update UnoGame to use repository pattern
- [x] Abstract Player Identity from IRC nicks
  - [x] Implement IrcIdentity for IRC-based players
  - [x] Implement SimpleIdentity for testing/CLI
  - [x] Implement UuidIdentity for web/API usage
  - [x] Maintain backward compatibility

## In Progress 🔄

## Pending 📋

### Phase 3: Core Game Logic Refactoring
- [ ] Extract game rules into separate classes
- [ ] Implement proper game state management
- [ ] Create command pattern for game actions

### Phase 4: Integration Testing
- [ ] Write integration tests for UnoPlugin
- [ ] Test IRC interface end-to-end
- [ ] Ensure backward compatibility

### Phase 5: Advanced Features
- [ ] Add support for house rules configuration
- [ ] Implement game replay functionality
- [ ] Add statistics tracking interface

### Phase 6: Gem Extraction
- [ ] Extract core game engine to separate gem
- [ ] Create gem structure
- [ ] Write gem documentation
- [ ] Publish to private gem server

## Notes

- All refactoring is being done in-place with continuous testing
- Backward compatibility is maintained throughout
- Database operations remain in casual mode (1) for testing
- Total test count: 181 tests with 161 passing

## Deferred Decisions 🔍

### Event System
After analysis, we determined that implementing a full Event system would be over-engineering at this stage. The current interfaces (Notifier, Renderer, Repository) already provide good separation of concerns for the current use case.

An Event system would make sense in the future if we add:
- Real-time spectator mode
- Complex achievement/statistics system
- Game replay functionality
- WebSocket-based multiplayer
- Multiple simultaneous games with shared state

For now, the direct method calls with our interface pattern provide a simpler, more maintainable solution.

## Repository review follow-ups (2026-07-21)

### Security

- [ ] Replace nickname-only and plaintext-password authentication with verified IRC account identity and hashed credentials. The current risk is accepted temporarily.
- [ ] Remove remote Ruby evaluation where practical (`EvaluatePlugin`, UNO debug, and plugin option values); otherwise centralize and test authorization for every such command.
- [ ] Make `.uno test` and `.uno reload` admin-only or remove them when the operational workflow no longer needs them.
- [ ] Replace plaintext FTP backups with an authenticated encrypted transport.

### Reliability and data

- [ ] Replace binary SQLite templates with versioned Sequel migrations and a single bootstrap command.
- [ ] Add atomic game creation/ID allocation and synchronization to the AZ plugin for concurrent channel events.
- [ ] Use a shared HTTP client policy for status validation, timeouts, and safe user-facing errors; currency and oil are the main gaps.
- [ ] If multiple bot processes are ever supported, replace the in-process note-delivery mutex with an atomic database claim/retry workflow.
- [ ] Make the version command report a build revision instead of the latest modification time among all runtime files.

### Maintenance and architecture

- [ ] Remove or archive `database.rb`, the registered sample `TemplatePlugin`, and obsolete compatibility plugins after confirming they are not operationally needed.
- [ ] Replace the architecture-specific ripgrep `.deb` with a normal image package or multi-architecture installation.
- [ ] Replace implicit loading of every plugin file with an explicit registry and `require_relative` paths.
- [ ] Reduce global state (`$bot`, `DB`, `UNODB`) when touching adjacent code; avoid introducing a large dependency-injection framework solely for this purpose.
- [ ] Align the Docker Bundler version with `Gemfile.lock`, then consider a multi-stage image to remove compilers and package caches from runtime.
- [ ] Reconcile the older UNO planning documents with the extracted `jedna` gem and the current passing test suite.

### Tests and operations

- [ ] Add command-boundary and denied-authorization tests for the remaining legacy active plugins.
- [ ] Add CI for the full RSpec suite, Ruby syntax checks, and a Docker build check.
- [ ] Document the required OpenTelemetry collector/backend environment variables and add a deployment smoke test.
