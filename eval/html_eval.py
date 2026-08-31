#!/usr/bin/env python3
"""CogEvol-4B interactive-HTML modality evaluation.

For each case {case_id, widget_type, prompt} this script resolves the matching
system prompt from an OpenMAIC checkout, streams a generation from the local
llama-server, extracts the self-contained HTML, and writes it out.

Usage:
  python3 html_eval.py --port 8081 \
      --templates /path/to/OpenMAIC \
      --data samples/html_cases_sample.jsonl --out out_html

--templates accepts any of: the OpenMAIC repo root, its legacy
`lib/prompts/templates` directory, or the current
`packages/@openmaic/generation/templates` directory — the script detects which.

Published setup: temperature 0, top_p 1, max_tokens 16384, seed 20260723,
thinking disabled (server must run with --jinja).
"""
import argparse, json, os, re, time, urllib.request

os.environ.setdefault("no_proxy", "127.0.0.1,localhost")

# candidate template roots, tried in order, relative to the --templates value
_TEMPLATE_ROOTS = (
    ".",                                                # .../lib/prompts/templates (legacy) or .../packages/@openmaic/generation/templates
    "lib/prompts/templates",                            # repo root, pre-Aug-2026 layout
    "packages/@openmaic/generation/templates",          # repo root, current layout
)


def resolve_system_prompt(templates_dir: str, widget_type: str) -> str:
    """Load templates/{type}-content/system.md; strip {{#if x}}...{{/if}} blocks
    and expand {{snippet:name}} from templates/snippets/."""
    path = None
    for root in _TEMPLATE_ROOTS:
        cand = os.path.join(templates_dir, root, f"{widget_type}-content", "system.md")
        if os.path.exists(cand):
            path = cand
            templates_dir = os.path.join(templates_dir, root)
            break
    if path is None:
        raise FileNotFoundError(
            f"no {widget_type}-content/system.md under {templates_dir} "
            f"(looked in: {', '.join(_TEMPLATE_ROOTS)})")
    text = open(path, encoding="utf-8").read()
    text = re.sub(r"\{\{#if \w+\}\}[\s\S]*?\{\{/if\}\}", "", text)
    def expand(m):
        name = m.group(1)
        snip = os.path.join(templates_dir, "snippets", f"{name}.md")
        return open(snip, encoding="utf-8").read() if os.path.exists(snip) else f"[snippet {name} not found]"
    return re.sub(r"\{\{snippet:(\w+)\}\}", expand, text)


def extract_html(text: str):
    m = re.search(r"```html\s*([\s\S]*?)\s*```", text)
    if m:
        return m.group(1)
    m = re.search(r"<!DOCTYPE html[\s\S]*", text, re.I)
    if m:
        return m.group(0)
    m = re.search(r"<html[\s\S]*", text, re.I)
    return m.group(0) if m else None


def stream(port, system, prompt, max_tokens=16384, timeout=1800):
    payload = {"messages": [{"role": "system", "content": system},
                            {"role": "user", "content": prompt}],
               "temperature": 0, "top_p": 1, "max_tokens": max_tokens,
               "seed": 20260723,
               "chat_template_kwargs": {"enable_thinking": False},
               "stream": True}
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    t0, buf = time.time(), []
    with urllib.request.urlopen(req, timeout=timeout) as r:
        for raw in r:
            line = raw.decode("utf-8", "ignore").strip()
            if not line.startswith("data: ") or line == "data: [DONE]":
                continue
            delta = json.loads(line[6:])["choices"][0].get("delta", {})
            c = delta.get("content") or ""
            if c:
                buf.append(c)
    return "".join(buf), time.time() - t0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8081)
    ap.add_argument("--templates", required=True,
                    help="OpenMAIC checkout root (or a templates dir inside it)")
    ap.add_argument("--data", default=os.path.join(os.path.dirname(__file__), "samples/html_cases_sample.jsonl"))
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "out_html"))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    rows = [json.loads(l) for l in open(args.data)]
    summary = []
    for i, r in enumerate(rows):
        cid, wtype = r["case_id"], r["widget_type"]
        try:
            system = resolve_system_prompt(args.templates, wtype)
        except FileNotFoundError as e:
            print(f"[{i+1}/{len(rows)}] {cid} NO_TEMPLATE {e}")
            continue
        try:
            text, dur = stream(args.port, system, r["prompt"])
        except Exception as e:
            print(f"[{i+1}/{len(rows)}] {cid} REQUEST_FAIL {e}")
            summary.append({"case_id": cid, "widget_type": wtype, "ok": False, "error": str(e)})
            continue
        html = extract_html(text)
        ok = bool(html and len(html) > 500)
        if ok:
            open(os.path.join(args.out, cid + ".html"), "w", encoding="utf-8").write(html)
        rec = {"case_id": cid, "widget_type": wtype, "ok": ok,
               "chars": len(text), "html_chars": len(html) if html else 0,
               "duration_s": round(dur, 1)}
        summary.append(rec)
        print(f"[{i+1}/{len(rows)}] {cid} {'OK' if ok else 'FAIL'} "
              f"{rec['html_chars']} chars html / {len(text)} total · {dur:.0f}s")

    good = [s for s in summary if s["ok"]]
    json.dump({"n": len(rows), "html_ok": len(good), "detail": summary},
              open(os.path.join(args.out, "summary.json"), "w"), ensure_ascii=False, indent=1)
    print(f"\n===== html: {len(good)}/{len(rows)} extracted → {args.out}/ =====")


if __name__ == "__main__":
    main()
