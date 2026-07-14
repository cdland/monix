"""newsbot chat — Q&A in the News room, answered by headless claude.

Companion to the digest timer (same account, same room): family messages
in the News room each become one `claude -p` run with web search, seeded
with the most recent digest for context. So "more on story 3", "sources
for that?", or "any news about X?" all work — including topics the
digest doesn't cover.

Containment: claude gets ONLY WebSearch/WebFetch (no shell, no repo, no
Matrix credentials — this process holds those and only ever posts to the
one room). Chat text steers searches, nothing else. Idempotent event
handling per the remy/budgetbot pattern.
"""

import asyncio
import json
import logging
import os
import sqlite3
import subprocess
import time

from nio import AsyncClient, RoomMessageText

log = logging.getLogger("newsbot-chat")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

HS_URL = os.environ["BOT_HS_URL"]
USER_ID = os.environ["MATRIX_USER"]
PASSWORD = os.environ["MATRIX_PASSWORD"]
INVITE_USERS = [u for u in os.environ.get("BOT_INVITE_USERS", "").split(",") if u]
ROOM_NAME = os.environ.get("BOT_ROOM_NAME", "News")
STATE_DIR = os.environ.get("BOT_STATE", "/var/lib/newsbot")
CLAUDE_MODEL = os.environ.get("CLAUDE_MODEL", "sonnet")
ROOM_ID_FILE = os.path.join(STATE_DIR, "room-id")
LAST_DIGEST = os.path.join(STATE_DIR, "last-digest.txt")

START_MS = int(time.time() * 1000)

INSTRUCTIONS = """You are the news desk bot in a family's private chat room.
Answer the family member's question below. Use web search — never answer
news questions from memory. When asked for more detail on a story, fetch
and read 1-2 actual articles. When asked for sources, give bare URLs.
Plain text only (no markdown syntax), concise (under ~200 words unless
they clearly want depth), neutral tone. If the question isn't about news
or current events, answer briefly and helpfully anyway.

EXCEPTION: if (and only if) the message asks you to generate, rerun, or
post the full news digest itself ("give me the evening digest again",
"run a fresh digest", "post the morning digest") — do NOT search or
answer. Reply with EXACTLY [[DIGEST morning]] or [[DIGEST evening]]
(the slot they named, else whichever fits the current time) and nothing
else. A question ABOUT a digest story is a normal question, not this.

Output ONLY the reply text."""


def db_connect():
    db = sqlite3.connect(os.path.join(STATE_DIR, "chat.db"))
    db.row_factory = sqlite3.Row
    db.executescript("""
        CREATE TABLE IF NOT EXISTS processed(event_id TEXT PRIMARY KEY, ts INTEGER);
        CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT);
    """)
    db.commit()
    return db


def meta_get(db, k):
    row = db.execute("SELECT v FROM meta WHERE k=?", (k,)).fetchone()
    return row["v"] if row else None


def meta_set(db, k, v):
    db.execute("INSERT INTO meta(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v", (k, v))
    db.commit()


def ask_claude(question, sender):
    digest = ""
    try:
        with open(LAST_DIGEST) as f:
            digest = f.read()[:6000]
    except OSError:
        pass
    prompt = INSTRUCTIONS
    prompt += time.strftime("\n\nRight now it is %A %H:%M.")
    if digest:
        prompt += f"\n\nThe most recent digest posted to the room (context):\n{digest}"
    prompt += f"\n\nQuestion from {sender}:\n{question}"
    out = subprocess.run(
        ["claude", "-p", "--model", CLAUDE_MODEL,
         "--allowedTools", "WebSearch,WebFetch"],
        input=prompt, capture_output=True, text=True, timeout=600)
    if out.returncode != 0:
        raise RuntimeError(f"claude exited {out.returncode}: {out.stderr[:300]}")
    return out.stdout.strip()


class Bot:
    def __init__(self):
        self.db = db_connect()
        self.client = AsyncClient(HS_URL, USER_ID)
        self.room_id = None
        # One question at a time: answers arrive in the order asked, and a
        # question storm can't fan out into parallel claude runs.
        self.lock = asyncio.Lock()

    async def send(self, text):
        await self.client.room_send(self.room_id, "m.room.message",
                                    {"msgtype": "m.notice", "body": text})

    async def on_message(self, room, event):
        if room.room_id != self.room_id or event.sender == self.client.user_id:
            return
        if self.db.execute("SELECT 1 FROM processed WHERE event_id=?",
                           (event.event_id,)).fetchone():
            return
        self.db.execute("INSERT INTO processed(event_id,ts) VALUES(?,?)",
                        (event.event_id, int(time.time())))
        self.db.commit()
        # Answer questions missed while down (up to 1h — a stale news
        # answer is worse than none), never anything predating the bot.
        if event.server_timestamp < START_MS - 3600 * 1000:
            return
        text = event.body.strip()
        if not text:
            return
        sender = event.sender.split(":")[0].lstrip("@")
        async with self.lock:
            log.info("question from %s: %r", sender, text[:80])
            try:
                reply = await asyncio.to_thread(ask_claude, text, sender)
                if reply.startswith("[[DIGEST"):
                    slot = "evening" if "evening" in reply else "morning"
                    # Stamp the request; a systemd path unit fires the
                    # digest service, which consumes the slot and posts.
                    with open(os.path.join(STATE_DIR, "run-digest.flag"), "w") as f:
                        f.write(slot)
                    await self.send(f"🗞 on it — fresh {slot} digest in a few minutes")
                    return
                await self.send(reply[:8000] or "(came back empty — try rephrasing?)")
            except Exception:
                log.exception("answer failed")
                await self.send("(that one broke on my end — it's logged)")

    async def ensure_room(self):
        """Share the digest script's room: use its stamp if present, else
        create the room ourselves and stamp it (whoever runs first wins)."""
        if os.path.exists(ROOM_ID_FILE):
            with open(ROOM_ID_FILE) as f:
                self.room_id = f.read().strip()
            return
        resp = await self.client.room_create(
            name=ROOM_NAME, invite=INVITE_USERS,
            topic="Morning and evening news digests.")
        if not getattr(resp, "room_id", None):
            raise SystemExit(f"room create failed: {resp}")
        self.room_id = resp.room_id
        with open(ROOM_ID_FILE, "w") as f:
            f.write(self.room_id)
        log.info("created room %s (%s)", ROOM_NAME, self.room_id)

    async def run(self):
        tok, dev = meta_get(self.db, "access_token"), meta_get(self.db, "device_id")
        if tok and dev:
            self.client.restore_login(USER_ID, dev, tok)
            whoami = await self.client.whoami()
            if getattr(whoami, "user_id", None) != USER_ID:
                tok = None
        if not (tok and dev):
            resp = await self.client.login(PASSWORD, device_name="newsbot-chat")
            if not getattr(resp, "access_token", None):
                raise SystemExit(f"login failed: {resp}")
            meta_set(self.db, "access_token", resp.access_token)
            meta_set(self.db, "device_id", resp.device_id)
        await self.ensure_room()
        await self.client.join(self.room_id)
        self.client.add_event_callback(self.on_message, RoomMessageText)
        log.info("newsbot chat up as %s in %s", USER_ID, self.room_id)
        await self.client.sync_forever(timeout=30000, full_state=True)


if __name__ == "__main__":
    asyncio.run(Bot().run())
