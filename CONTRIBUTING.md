# Contributing to Rediz

Thank you for your interest in contributing to **Rediz**, the Redis client for Zig!

We welcome contributions of all kinds — whether it's fixing a bug, adding a feature, improving performance, or enhancing documentation.

---

## Getting Started

1. **Fork** the repository
2. **Clone** your fork locally
3. Create a new **feature branch**:
   ```sh
   git checkout -b feature/my-awesome-thing
   ```
4. Make your changes
5. Run the tests:
   ```sh
   zig test src/tests.zig
   ```
6. Commit and push:
   ```sh
   git push origin feature/my-awesome-thing
   ```
7. Open a **Pull Request** on GitHub

---

## Code Guidelines

- Use idiomatic Zig (`zig fmt` will help)
- Keep functions focused and low-level if possible
- Prefer clear naming over comments
- Avoid unnecessary allocations unless justified
- Use `std.testing` for test coverage

---

## Contributions We Love

- Adding new Redis command support (e.g. `DEL`, `HGETALL`, `INCR`)
- Improving protocol parsing (RESP arrays, errors, etc.)
- Memory usage improvements
- Useful test cases and example apps

---

## Questions?

Feel free to open an issue or start a GitHub discussion if you’re unsure about anything before submitting a PR.

Thanks again! 🎉
