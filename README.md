<p align="center">
  <img src="https://santoku.dev/logo-santoku-bundle.png" height="64" alt="santoku-bundle">
</p>

# santoku-bundle

Turns a Lua entry script and everything it transitively requires into a single standalone
executable. It scans for `require` calls with lpeg, resolves each module to a file, merges
the Lua sources, generates a C program around them, and invokes the C compiler.

## Documentation

Runnable examples and the full API: [santoku.dev](https://santoku.dev/#santoku-bundle).

For agents and LLM tooling: [llms.txt](https://santoku.dev/llms.txt) for the index,
[llms-full.txt](https://santoku.dev/llms-full.txt) for every documented example.

## License

MIT, see [LICENSE](LICENSE).

