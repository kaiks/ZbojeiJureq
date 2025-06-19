# RSpec Test Setup for BtcPlugin

## Summary

This test suite provides comprehensive coverage for the BtcPlugin, validating its cryptocurrency price tracking and IRC command functionality.

## Test Coverage

### ✅ Completed Tests (20 tests)

1. **Helper Methods**
   - `#round_to_500` - Price rounding logic
   - `#btc_price_update?` - Price change detection
   - `#cryptocompare_parse` - API response parsing

2. **Price Monitoring**
   - Timer-based price checking
   - Channel notifications for significant price changes
   - Color-coded messages (green for increases, red for decreases)
   - Checkpoint management

3. **Error Handling**
   - JSON parsing errors
   - Nil value handling
   - API response validation

### ✅ IRC Command Tests (6 tests)

All IRC command tests are now passing:
- `.btc` command
- `.eth` command  
- `.crypto` command (with valid and invalid coins)
- `.cryptoupdate` command (admin only)

## Running the Tests

```bash
# Run all tests
bundle exec rspec spec/plugins/btc_plugin_spec.rb

# Run with documentation format
bundle exec rspec spec/plugins/btc_plugin_spec.rb --format documentation

# Run specific test groups
bundle exec rspec spec/plugins/btc_plugin_spec.rb -e "price monitoring"
```

## Technical Notes

### WebMock Issue Resolution
The plugin uses `open` from the global namespace which caused `Errno::ENOENT` errors in Ruby 3.0+ because `open-uri` no longer overwrites `Kernel#open`. This was resolved by:

1. **Understanding the issue**: In Ruby 3.0+, `open("http://...")` tries to open a local file instead of making an HTTP request
2. **Solution**: Mocking the `open` method directly in tests to return `StringIO` objects
3. **Alternative**: The plugin could be refactored to use `URI.open()` instead of `open()` for Ruby 3.0+ compatibility

### Test Structure
Tests use the "allocate" pattern to avoid full Cinch plugin initialization, allowing focused unit testing of individual methods without the overhead of the IRC framework.

### Ruby 3.0+ Compatibility
For production use with Ruby 3.0+, the plugin should be updated to replace:
```ruby
open("https://example.com")  # Old way
```
with:
```ruby
URI.open("https://example.com")  # Ruby 3.0+ way
```

## Gems Added

```ruby
group :test do
  gem 'rspec', '~> 3.12'
  gem 'webmock', '~> 3.19'
  gem 'timecop', '~> 0.9'
end
```