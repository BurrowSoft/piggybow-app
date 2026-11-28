#!/usr/bin/env python3
"""A mock of Piggybow's tips server (S1's API) for the AI-tips device rows.

Started by a rows script on the CI runner; the emulator reaches it at
http://10.0.2.2:<port> through the staging-debug-only TIPS_TEST_URL (kind
tips-mock). Python's standard library only.

    tips_mock.py <port> <log.jsonl> <contract.json>

The app's side (S1, as PB Mobile Dev gave it):
  POST /auth/v1/signup                      anonymous sign-in → a session
  POST /auth/v1/token?grant_type=refresh_token
  POST /functions/v1/pig-tip                the contract's body → 200 {"tip","sig"}
                                            (headers x-tip-model, x-tip-usage)
                                            or 204 (no tip today); 401 without
                                            a live token; 400 on a bad body
  POST /functions/v1/pig-tip/report         {"tip","reason","model","sig"} → 204
                                            when tip, model and sig are the
                                            ones served; else 400
  POST /functions/v1/pig-tip/forget         deletes the anonymous user → 204
The rows script's side (from the runner only, 127.0.0.1):
  POST /__mock/mode?m=tip|nosig|timeout|cap|none|error|503   pig-tip's next answers
  POST /__mock/report?m=ok|cap                                report's answers
  GET  /__mock/log                                  every request so far, JSON lines
  POST /__mock/reset                                forget everything

Every request is logged with its path, the anonymous id behind its token,
and, for pig-tip, whether its body passed the contract. A body that fails
gets 400 {"code":"invalid_value"} and an INVALID line: a row reading the log
fails on any.
"""
import base64
import json
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PORT = int(sys.argv[1])
LOG = sys.argv[2]
CONTRACT = json.load(open(sys.argv[3], encoding="utf-8"))

LOCK = threading.Lock()
STATE = {"mode": "tip", "report_mode": "ok", "tokens": {}, "refresh": {},
         "users": set(), "count": 0, "served": {}}  # served: tip text → sig
TIPS = [
    "Try one no-spend day before the weekend.",
    "Look back at what felt worth it this week, and plan one more of those.",
    "Put a small amount toward your goal today, even a little.",
]
REASONS = {"unhelpful", "wrong", "upsetting", "advice", "other"}
MODEL = "mock-model-1"


def log(entry):
    entry["t"] = time.strftime("%H:%M:%S", time.gmtime())
    with LOCK, open(LOG, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


def b64(d):
    return base64.urlsafe_b64encode(json.dumps(d).encode()).rstrip(b"=").decode()


def session(sub):
    access = ".".join([b64({"alg": "none", "typ": "JWT"}),
                       b64({"sub": sub, "is_anonymous": True, "role": "authenticated"}),
                       "mock"])
    refresh = uuid.uuid4().hex
    STATE["tokens"][access] = sub
    STATE["refresh"][refresh] = sub
    return {"access_token": access, "token_type": "bearer", "expires_in": 3600,
            "refresh_token": refresh, "user": {"id": sub, "is_anonymous": True}}


def contract_problems(body):
    """What's wrong with a pig-tip body, against the contract; [] when right."""
    c = CONTRACT
    p = []
    if not isinstance(body, dict):
        return ["not an object"]
    allowed = set(c["required"]) | set(c["optional"])
    p += [f"extra field {k}" for k in body if k not in allowed]
    p += [f"missing {k}" for k in c["required"] if k not in body]

    def is_int(v):
        return isinstance(v, int) and not isinstance(v, bool)

    if "language" in body and body["language"] not in c["languages"]:
        p.append(f"language {body['language']!r}")
    w = body.get("weekday")
    if "weekday" in body and not (is_int(w) and c["weekday"]["min"] <= w <= c["weekday"]["max"]):
        p.append(f"weekday {w!r}")
    shares = body.get("category_shares", {})
    if not isinstance(shares, dict):
        p.append("category_shares not an object")
    else:
        bad = [k for k in shares if k not in c["category_keys"]]
        p += [f"category key {k!r}" for k in bad]
        if len([k for k in shares if k != "yours"]) > c["max_built_in_categories"]:
            p.append("more than the top built-in categories")
        p += [f"share {k}={v!r}" for k, v in shares.items()
              if not (is_int(v) and c["percent"]["min"] <= v <= c["percent"]["max"])]
    feel = body.get("feelings", {})
    if not isinstance(feel, dict):
        p.append("feelings not an object")
    else:
        p += [f"feeling {k!r}" for k in feel if k not in c["feelings"]]
        p += [f"feeling count {k}={v!r}" for k, v in feel.items() if not (is_int(v) and v >= 0)]
    for k in ("saves", "active_goals"):
        if k in body and not (is_int(body[k]) and body[k] >= 0):
            p.append(f"{k} {body[k]!r}")
    for k in ("plan_percent", "goal_percent"):
        if k in body and not (is_int(body[k]) and c["percent"]["min"] <= body[k] <= c["percent"]["max"]):
            p.append(f"{k} {body[k]!r}")
    picks = body.get("picks", [])
    if not isinstance(picks, list) or any(x not in c["picks"] for x in picks):
        p.append(f"picks {picks!r}")
    return p


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):  # the JSON log is the record
        pass

    def reply(self, code, body=None, headers=None):
        data = b"" if body is None else json.dumps(body).encode()
        self.send_response(code)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        if body is not None:
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if data:
            self.wfile.write(data)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        try:
            return json.loads(raw) if raw else None
        except ValueError:
            return "<not json>"

    def sub(self):
        auth = self.headers.get("Authorization", "")
        tok = auth[7:] if auth.startswith("Bearer ") else ""
        with LOCK:
            s = STATE["tokens"].get(tok)
            return s if s in STATE["users"] else None

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/__mock/log" and self.client_address[0] == "127.0.0.1":
            data = open(LOG, "rb").read() if __import__("os").path.exists(LOG) else b""
            self.send_response(200)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        self.reply(404, {"code": "not_found"})

    def do_POST(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        local = self.client_address[0] == "127.0.0.1"
        if u.path == "/__mock/mode" and local:
            STATE["mode"] = (q.get("m") or ["tip"])[0]
            return self.reply(204)
        if u.path == "/__mock/report" and local:
            STATE["report_mode"] = (q.get("m") or ["ok"])[0]
            return self.reply(204)
        if u.path == "/__mock/reset" and local:
            with LOCK:
                STATE.update(tokens={}, refresh={}, users=set(), count=0, mode="tip",
                             report_mode="ok", served={})
            open(LOG, "w").close()
            return self.reply(204)
        has_key = bool(self.headers.get("apikey"))
        body = self.body()
        if u.path == "/auth/v1/signup":
            sub = str(uuid.uuid4())
            with LOCK:
                STATE["users"].add(sub)
                s = session(sub)
            log({"path": u.path, "apikey": has_key, "id": sub})
            return self.reply(200, s)
        if u.path == "/auth/v1/token" and q.get("grant_type") == ["refresh_token"]:
            rt = body.get("refresh_token") if isinstance(body, dict) else None
            with LOCK:
                sub = STATE["refresh"].get(rt)
                ok = sub in STATE["users"]
                s = session(sub) if ok else None
            log({"path": u.path + "?refresh", "apikey": has_key, "id": sub, "ok": ok})
            return self.reply(200, s) if ok else self.reply(400, {"code": "invalid_grant"})
        sub = self.sub()
        if u.path == "/functions/v1/pig-tip":
            if not sub:
                log({"path": u.path, "apikey": has_key, "id": None, "code": 401})
                return self.reply(401, {"code": "unauthorized"})
            probs = contract_problems(body)
            if probs:
                log({"path": u.path, "id": sub, "code": 400, "INVALID": probs, "body": body})
                return self.reply(400, {"code": "invalid_value"})
            mode = STATE["mode"]
            entry = {"path": u.path, "apikey": has_key, "id": sub, "mode": mode,
                     "region": self.headers.get("x-region"), "body": body}
            if mode == "timeout":
                log({**entry, "code": "held 20 s"})
                time.sleep(20)
                return self.reply(204)
            if mode == "cap":
                log({**entry, "code": 429})
                return self.reply(429, {"code": "cap"})
            if mode == "error":
                log({**entry, "code": 500})
                return self.reply(500, {"code": "error"})
            if mode == "503":
                log({**entry, "code": 503})
                return self.reply(503, {"code": "unavailable"})
            if mode == "none":
                log({**entry, "code": 204})
                return self.reply(204)
            with LOCK:
                tip = TIPS[STATE["count"] % len(TIPS)]
                STATE["count"] += 1
                sig = f"mock-sig-{STATE['count']}"
                STATE["served"][tip] = sig
            headers = {"x-tip-model": MODEL, "x-tip-usage": "in=120;out=18"}
            if mode == "nosig":  # a 200 without a usable sig: the app's own tip
                log({**entry, "code": 200, "tip": tip, "sig": None})
                return self.reply(200, {"tip": tip}, headers)
            log({**entry, "code": 200, "tip": tip, "sig": sig})
            return self.reply(200, {"tip": tip, "sig": sig}, headers)
        if u.path == "/functions/v1/pig-tip/report":
            with LOCK:
                served = dict(STATE["served"])
            ok = (sub and isinstance(body, dict)
                  and set(body) == {"tip", "reason", "model", "sig"}
                  and isinstance(body["tip"], str) and 1 <= len(body["tip"]) <= 400
                  and body["reason"] in REASONS and body["model"] == MODEL
                  and served.get(body["tip"]) == body["sig"])
            if ok and STATE["report_mode"] == "cap":
                log({"path": u.path, "id": sub, "code": 429, "report": body})
                return self.reply(429, {"code": "cap"})
            log({"path": u.path, "id": sub, "code": 204 if ok else 400, "report": body})
            return self.reply(204) if ok else self.reply(400, {"code": "invalid_value"})
        if u.path == "/functions/v1/pig-tip/forget":
            with LOCK:
                if sub:
                    STATE["users"].discard(sub)
            log({"path": u.path, "id": sub, "code": 204 if sub else 401})
            return self.reply(204) if sub else self.reply(401, {"code": "unauthorized"})
        log({"path": u.path, "code": 404})
        self.reply(404, {"code": "not_found"})


if __name__ == "__main__":
    open(LOG, "a").close()
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
