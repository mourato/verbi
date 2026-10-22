# Debugging Checklist

## Before You Start

- [ ] **Reproduce the issue**
  - Can you reproduce it consistently?
  - What are the exact steps?
  - What is the expected behavior?

- [ ] **Gather information**
  - Full error message and stack trace
  - OS version and app version
  - Device model (if applicable)
  - Steps to reproduce

- [ ] **Check recent changes**
  - Recent commits that might have caused it
  - Dependency updates
  - Configuration changes

## Initial Investigation

- [ ] **Read the error message completely**
  - Don't skip the stack trace
  - Note error codes and symbols

- [ ] **Check the obvious**
  - Is the API/key/token valid?
  - Is the network working?
  - Are permissions granted?

- [ ] **Simplify the problem**
  - Remove unrelated code
  - Create minimal reproduction case
  - Isolate the failing component

## Common Debugging Areas

### Memory Issues

- [ ] Check for strong reference cycles
- [ ] Verify @State/@Published usage
- [ ] Check for large object allocations
- [ ] Monitor memory growth over time

### Performance Issues

- [ ] Profile with Instruments
- [ ] Check for N+1 queries (if applicable)
- [ ] Look for unnecessary re-renders
- [ ] Verify async operations complete

### Network Issues

- [ ] Verify URL is correct
- [ ] Check headers/authentication
- [ ] Test with curl
- [ ] Check for rate limiting

### Threading Issues

- [ ] Verify @MainActor annotations
- [ ] Check for race conditions
- [ ] Ensure thread-safe access
- [ ] Verify async/await patterns

## Verification

- [ ] The fix resolves the issue
- [ ] No new issues introduced
- [ ] Tests pass with the fix
- [ ] Edge cases are handled
- [ ] Performance is not degraded

## Quick Reference

### Tools to Use

| Issue Type | Tool |
|------------|------|
| CPU profiling | Instruments > Time Profiler |
| Memory leaks | Instruments > Leaks |
| Memory allocations | Instruments > Allocations |
| Network | Charles Proxy, Network tab |
| UI rendering | Instruments > Core Animation |
| Logs | Console.app |

### Common Error Codes

| Code | Meaning | Action |
|------|---------|--------|
| -1 | Unknown error | Check logs |
| 100 | Permission denied | Check entitlements |
| 200 | Network timeout | Check connectivity |
| 300 | Invalid state | Verify object lifecycle |

### Useful Commands

```bash
# Clear derived data
rm -rf ~/Library/Developer/Xcode/DerivedData

# Reset simulator
xcrun simctl erase all

# View device logs
log show --predicate 'process == "Verbi"' --info
```
