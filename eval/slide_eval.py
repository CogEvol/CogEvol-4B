#!/usr/bin/env python3
"""CogEvol-4B slide-modality evaluation.

Sends each case's messages to a local llama-server (OpenAI-compatible API),
validates the slide scene-graph JSON contract, and reports speed stats.

Contract: top-level object with `elements` (list) and `background` (object).

Usage:
  python3 slide_eval.py --port 8081 --data samples/slide_briefs_sample.jsonl --out out_slide
Generation params are fixed to the published setup: temperature 0, max_tokens 8192,
thinking disabled via chat_template_kwargs (requires llama-server started with --jinja).
"""
import argparse, json, os, re, statistics, sys, time, urllib.request

os.environ.setdefault("no_proxy", "127.0.0.1,localhost")


def strip_think(t: str) -> str:
    t = re.sub(r"<think>.*?</think>", "", t, flags=re.DOTALL)
    if "</think>" in t:
        t = t[t.index("</think>") + len("</think>"):]
    return t.strip()


def extract_json(text: str):
    m = re.search(r"```(?:json)?\s*(\{.*\})\s*```", text, re.DOTALL)
    if m:
        return m.group(1)
    i, j = text.find("{"), text.rfind("}")
    return text[i:j + 1] if i != -1 and j > i else None


def validate(text: str):
    try:
        obj = json.loads(extract_json(strip_think(text)))
    except Exception as e:
        return False, None, f"json_parse_error: {e}"
    if (not isinstance(obj, dict) or "elements" not in obj or "background" not in obj
            or not isinstance(obj["elements"], list)):
        return False, obj, "missing_elements_or_background"
    return True, obj, None


def post(port, messages, max_tokens=8192, timeout=900):
    payload = {
        "messages": messages,
        "temperature": 0,
        "max_tokens": max_tokens,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as r:
        d = json.loads(r.read())
    return (d["choices"][0]["message"].get("content") or ""), d.get("usage") or {}, time.time() - t0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8081)
    ap.add_argument("--data", default=os.path.join(os.path.dirname(__file__), "samples/slide_briefs_sample.jsonl"))
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "out_slide"))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    rows = [json.loads(l) for l in open(args.data)]
    summary = []
    for i, r in enumerate(rows):
        tid = r.get("topic_id", f"case_{i}")
        try:
            content, usage, dur = post(args.port, r["messages"])
        except Exception as e:
            print(f"[{i+1}/{len(rows)}] {tid} REQUEST_FAIL {e}")
            summary.append({"topic_id": tid, "ok": False, "error": str(e)})
            continue
        ok, obj, err = validate(content)
        ct = usage.get("completion_tokens")
        rec = {"topic_id": tid, "topic": r.get("topic", ""), "ok": ok, "error": err,
               "elements": len(obj["elements"]) if ok else None,
               "completion_tokens": ct, "duration_s": round(dur, 1),
               "tok_per_s": round(ct / dur, 1) if ct and dur > 0 else None}
        summary.append(rec)
        if ok:
            json.dump(obj, open(os.path.join(args.out, tid + ".json"), "w"), ensure_ascii=False, indent=1)
        print(f"[{i+1}/{len(rows)}] {tid} {'OK' if ok else 'FAIL:' + str(err)} "
              f"elems={rec['elements']} tok={ct} {dur:.0f}s {rec['tok_per_s']}t/s")

    valid = [s for s in summary if s.get("ok")]
    stats = {"n": len(rows), "json_valid": len(valid),
             "tok_per_s_mean": round(statistics.mean([s["tok_per_s"] for s in valid]), 1) if valid else None,
             "duration_s_mean": round(statistics.mean([s["duration_s"] for s in valid]), 1) if valid else None,
             "detail": summary}
    json.dump(stats, open(os.path.join(args.out, "summary.json"), "w"), ensure_ascii=False, indent=1)
    print(f"\n===== slides: contract {len(valid)}/{len(rows)} | mean {stats['tok_per_s_mean']} t/s | "
          f"{stats['duration_s_mean']}s per slide =====")
    sys.exit(0 if len(valid) == len(rows) else 1)


if __name__ == "__main__":
    main()
