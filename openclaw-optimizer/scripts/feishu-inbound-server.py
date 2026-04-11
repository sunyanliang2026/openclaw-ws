#!/usr/bin/env python3
import json
import os
import re
import subprocess
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path("/home/ubuntu/.openclaw/workspace/openclaw-optimizer")
CONFIG_PATH = Path(os.environ.get("FEISHU_INBOUND_CONFIG", ROOT / "config/inbound-feishu.json"))
RUNTIME_ROOT = Path(os.environ.get("FEISHU_INBOUND_RUNTIME", ROOT / "runtime"))
LOG_DIR = RUNTIME_ROOT / "logs"
EVENT_DIR = RUNTIME_ROOT / "events"
NEW_TASK_SCRIPT = ROOT / "scripts/new-task.sh"
START_TASK_SCRIPT = ROOT / "scripts/start-task.sh"


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_config() -> dict:
    if not CONFIG_PATH.exists():
        raise FileNotFoundError(f"missing config: {CONFIG_PATH}")
    with CONFIG_PATH.open("r", encoding="utf-8") as f:
        cfg = json.load(f)
    return cfg


def json_log(event: str, detail: dict) -> None:
    EVENT_DIR.mkdir(parents=True, exist_ok=True)
    event_file = EVENT_DIR / f"feishu-inbound-events-{time.strftime('%Y%m%d')}.jsonl"
    payload = {"ts": now_iso(), "event": event, "detail": detail}
    with event_file.open("a", encoding="utf-8") as f:
        f.write(json.dumps(payload, ensure_ascii=False) + "\n")


def text_log(msg: str) -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_file = LOG_DIR / f"feishu-inbound-{time.strftime('%Y%m%d')}.log"
    with log_file.open("a", encoding="utf-8") as f:
        f.write(f"[{now_iso()}] {msg}\n")


def parse_message_text(payload: dict) -> str:
    # Feishu event subscription shape
    content = payload.get("event", {}).get("message", {}).get("content")
    if isinstance(content, str):
        try:
            parsed = json.loads(content)
            if isinstance(parsed, dict):
                text = parsed.get("text")
                if isinstance(text, str) and text.strip():
                    return text.strip()
        except json.JSONDecodeError:
            pass

    # Generic shapes
    direct_paths = [
        payload.get("text", {}).get("content"),
        payload.get("content", {}).get("text"),
        payload.get("message", {}).get("text"),
        payload.get("message"),
    ]
    for val in direct_paths:
        if isinstance(val, str) and val.strip():
            return val.strip()

    return ""


def parse_chat_id(payload: dict) -> str:
    return (
        payload.get("event", {}).get("message", {}).get("chat_id")
        or payload.get("chat_id")
        or ""
    )


def slugify(s: str) -> str:
    s = s.strip().lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    s = re.sub(r"-+", "-", s).strip("-")
    return s or "task"


def extract_fields(text: str, cfg: dict) -> dict:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    first = lines[0] if lines else text.strip()

    project = cfg.get("defaultProjectId", "internal-openclaw")
    task_type = cfg.get("defaultType", "backend-feature")
    priority = cfg.get("defaultPriority", "medium")
    title = first
    prompt = text

    for line in lines:
        if line.lower().startswith("project:"):
            project = line.split(":", 1)[1].strip() or project
        elif line.lower().startswith("type:"):
            task_type = line.split(":", 1)[1].strip() or task_type
        elif line.lower().startswith("priority:"):
            priority = line.split(":", 1)[1].strip() or priority
        elif line.lower().startswith("title:"):
            title = line.split(":", 1)[1].strip() or title

    max_title = int(cfg.get("maxTitleLength", 80))
    max_prompt = int(cfg.get("maxPromptLength", 6000))
    title = title[:max_title]
    prompt = prompt[:max_prompt]

    prefix = cfg.get("taskIdPrefix", "req")
    ts = time.strftime("%Y%m%d-%H%M%S")
    task_id = f"{prefix}-{ts}-{slugify(title)[:20]}"

    return {
        "project": project,
        "task_type": task_type,
        "priority": priority,
        "title": title,
        "prompt": prompt,
        "task_id": task_id,
    }


def normalize_chat_target(chat_id: str) -> str:
    chat_id = (chat_id or "").strip()
    if not chat_id:
        return ""
    if chat_id.startswith("chat:"):
        return chat_id
    return f"chat:{chat_id}"


def run_cmd(args: list[str]) -> tuple[int, str, str]:
    p = subprocess.run(args, capture_output=True, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()


class Handler(BaseHTTPRequestHandler):
    server_version = "OpenClawFeishuInbound/1.0"

    def _reply(self, status: int, body: dict) -> None:
        raw = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self) -> None:
        cfg = self.server.cfg
        parsed = urlparse(self.path)
        expected_path = cfg.get("path", "/feishu/webhook")
        if parsed.path != expected_path:
            self._reply(404, {"ok": False, "error": "not_found"})
            return

        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            self._reply(400, {"ok": False, "error": "empty_body"})
            return

        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw.decode("utf-8"))
        except Exception:
            self._reply(400, {"ok": False, "error": "invalid_json"})
            return

        # Feishu URL verification handshake
        if payload.get("type") == "url_verification" and "challenge" in payload:
            self._reply(200, {"challenge": payload["challenge"]})
            return

        query = parse_qs(parsed.query or "")
        token_from_q = (query.get("token") or [""])[0]
        token_from_h = self.headers.get("X-OpenClaw-Token", "")
        token_from_payload = str(payload.get("token", ""))
        expected_token = str(cfg.get("authToken", "")).strip()
        if expected_token:
            provided = token_from_h or token_from_q or token_from_payload
            if provided != expected_token:
                json_log("feishu_inbound_rejected", {"reason": "token_mismatch"})
                self._reply(403, {"ok": False, "error": "forbidden"})
                return

        chat_id = parse_chat_id(payload)
        allowed = cfg.get("allowedChatIds") or []
        if allowed and chat_id and chat_id not in allowed:
            json_log("feishu_inbound_rejected", {"reason": "chat_not_allowed", "chatId": chat_id})
            self._reply(403, {"ok": False, "error": "chat_not_allowed"})
            return

        text = parse_message_text(payload)
        if not text:
            self._reply(400, {"ok": False, "error": "text_not_found"})
            return

        fields = extract_fields(text, cfg)
        completion_notify = cfg.get("completionNotify") or {}
        notify_enabled = bool(completion_notify.get("enabled", False))
        notify_channel = str(completion_notify.get("channel", "feishu") or "feishu")
        notify_account = str(completion_notify.get("account", "main") or "main")
        notify_target = str(completion_notify.get("target", "") or "")
        auto_from_chat = bool(completion_notify.get("autoFromChat", True))
        if auto_from_chat and chat_id:
            notify_enabled = True
            notify_target = normalize_chat_target(chat_id)

        new_task_args = [
            str(NEW_TASK_SCRIPT),
            "--project",
            fields["project"],
            "--task-id",
            fields["task_id"],
            "--title",
            fields["title"],
            "--type",
            fields["task_type"],
            "--priority",
            fields["priority"],
            "--prompt",
            fields["prompt"],
        ]
        if notify_enabled and notify_target:
            new_task_args.extend(
                [
                    "--notify-channel",
                    notify_channel,
                    "--notify-account",
                    notify_account,
                    "--notify-target",
                    notify_target,
                ]
            )
        rc, out, err = run_cmd(new_task_args)
        if rc != 0:
            detail = {"taskId": fields["task_id"], "stdout": out, "stderr": err}
            json_log("feishu_inbound_task_create_failed", detail)
            self._reply(500, {"ok": False, "error": "task_create_failed", "detail": detail})
            return

        started = False
        start_out = ""
        start_err = ""
        if bool(cfg.get("autoStart", True)):
            rc2, start_out, start_err = run_cmd([str(START_TASK_SCRIPT), fields["task_id"]])
            started = rc2 == 0
            if not started:
                json_log(
                    "feishu_inbound_task_start_failed",
                    {"taskId": fields["task_id"], "stdout": start_out, "stderr": start_err},
                )

        detail = {
            "taskId": fields["task_id"],
            "project": fields["project"],
            "type": fields["task_type"],
            "priority": fields["priority"],
            "notifyEnabled": notify_enabled,
            "notifyTarget": notify_target if notify_enabled else "",
            "autoStart": bool(cfg.get("autoStart", True)),
            "started": started,
        }
        json_log("feishu_inbound_task_created", detail)
        text_log(f"created task from feishu: {detail}")
        self._reply(
            200,
            {
                "ok": True,
                "taskId": fields["task_id"],
                "project": fields["project"],
                "started": started,
                "notifyEnabled": notify_enabled,
                "notifyTarget": notify_target if notify_enabled else "",
                "createOutput": out,
                "startOutput": start_out,
                "startError": start_err,
            },
        )

    def log_message(self, fmt: str, *args) -> None:
        text_log(fmt % args)


def main() -> None:
    cfg = load_config()
    if not cfg.get("enabled", False):
        raise SystemExit("inbound-feishu disabled: set config/inbound-feishu.json enabled=true")
    host = cfg.get("bindHost", "127.0.0.1")
    port = int(cfg.get("bindPort", 8787))
    server = ThreadingHTTPServer((host, port), Handler)
    server.cfg = cfg
    text_log(f"feishu inbound server started on {host}:{port}{cfg.get('path','/feishu/webhook')}")
    server.serve_forever()


if __name__ == "__main__":
    main()
