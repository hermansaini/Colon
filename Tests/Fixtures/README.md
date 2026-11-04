# Shared Test Fixtures

Place deterministic fixtures used by more than one package or integration test
under this directory. Package-local fixtures should remain inside the package
that owns them.

Fixtures must contain synthetic data only. Never add captured typed text,
credentials, private messages, or other user content.

`compatibility.html` is a self-contained manual typing fixture for Chrome and
Safari. Open it after installing the updated input source and logging out/in.
It covers plain, multiline, rich, and synthetic password input, with instructions
for shortcuts, replacement, selection, tones, and disabling Colon. It sends and
saves nothing. Record observations in `docs/compatibility-matrix.md`; the fixture
does not automate or certify those checks.
