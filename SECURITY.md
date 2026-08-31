# Security Policy

## Scope

This repository ships shell scripts, a Python evaluation harness, and a source
patch for third-party projects. Security issues we care about:

- Anything in `scripts/` or `eval/` that could execute unintended code or leak
  data (e.g. unsafe handling of downloaded or generated content).
- Weaknesses in the offline asset mirroring (`fetch-offline-assets.sh`) —
  in particular anything that would let mirrored files differ from their
  upstream CDN versions.
- Malicious model outputs reaching the app at runtime (generated HTML/JS is
  untrusted by construction; hardening ideas welcome).

Out of scope: the OpenMAIC application itself (report upstream) and the model
weights (see the HuggingFace repos).

## Supply-chain hygiene for users

- The only binary this repo asks you to download is the GGUF weight file —
  verify it against the sha256 published in the README before use.
- `fetch-offline-assets.sh` mirrors KaTeX from the app's own `node_modules`
  (pinned by its lockfile) and fetches Tailwind/CodeMirror runtime files over
  HTTPS from their official CDNs; review the script before running it, as you
  should with any setup script.

## Reporting a vulnerability

Email **contact@cogevol.com** with `[security] CogEvol-4B repo` in the
subject. Please include reproduction steps and, where relevant, the commit the
issue applies to. We aim to respond within a few days. Do not open a public
issue for security problems.
