## Summary

<!-- What does this change do, and why? -->

## Verification

<!-- What you ran to prove it works, e.g.:
     bash -n scripts/*.sh; python3 -m py_compile eval/*.py;
     tested end-to-end on <device>; CI green -->

- [ ] Shell scripts still parse (`bash -n scripts/*.sh`)
- [ ] Eval scripts still import and run (`python3 eval/slide_eval.py --help`)
- [ ] Sample JSONL still parses
- [ ] README.md and README_zh.md updated together (they must stay in sync)
- [ ] If the OpenMAIC patch changed: base commit compatibility note updated (README §7)
