# Contributing to CogEvol-4B

Thanks for your interest in improving this repository!

## What this repo is

Code only — serving scripts, the OpenMAIC integration patch, and evaluation
tooling for the [CogEvol-4B](https://huggingface.co/CogEvol/CogEvol-4B) model
(weights on HuggingFace, Apache 2.0). Everything here targets **reproducibility
on a laptop**: no GPU cluster, no API keys, no cloud dependencies.

## Ground rules

- **Keep the two READMEs in sync.** `README.md` and `README_zh.md` must describe
  the same behavior. A change to one is a change to the other.
- **Keep numbers honest.** Performance figures, validation counts and the GGUF
  sha256 in the READMEs come from measured runs. If you change flags or scripts
  in a way that affects them, re-measure and update — or say so in the PR.
- **Keep scripts dependency-free.** Shell scripts use POSIX-ish bash + `curl`;
  Python eval scripts are stdlib-only on purpose (they must run on a bare
  laptop). Adding a pip dependency needs a strong reason.
- **Patch changes must state their base.** If you touch
  `patches/openmaic-live/*.patch`, record which commit it was generated
  against and update the compatibility note in README §7.

## Before opening a PR

```bash
bash -n scripts/*.sh                 # shell syntax
python3 -m py_compile eval/*.py      # python syntax
python3 eval/slide_eval.py --help    # imports cleanly
python3 - <<'EOF'                    # sample data parses
import json, glob
for p in glob.glob("eval/samples/*.jsonl"):
    rows = [json.loads(l) for l in open(p)]
    assert rows, p
    print(p, len(rows))
EOF
git apply --stat patches/openmaic-live/openmaic-live-offline-on-device.patch  # diff parses
```

CI runs the same checks on every push and pull request.

If your change affects serving or generation quality, ideally also run the
3-case smoke eval against a live server (README §9) and include the output in
the PR.

## Issues

- Model/weights questions → [HF discussions](https://huggingface.co/CogEvol/CogEvol-4B-Q4_K_M-GGUF/discussions)
- App bugs (OpenMAIC itself) → [upstream](https://github.com/THU-MAIC/OpenMAIC/issues)
- This repo's scripts / patch / eval → [GitHub issues here](https://github.com/CogEvol/CogEvol-4B/issues)

Security problems: please follow [SECURITY.md](SECURITY.md) instead of opening
a public issue.
