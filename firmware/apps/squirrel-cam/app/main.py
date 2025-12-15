#!/usr/bin/env python3
"""
Squirrel Cam - Fetch Blink clips and run animal detection

Requires authenticated credentials.json (run auth.py first).
"""

import os
import json
import asyncio
from pathlib import Path
from datetime import datetime

import aiohttp
from blinkpy.blinkpy import Blink
from blinkpy.auth import Auth

CONFIG_PATH = Path(os.environ.get("CONFIG_PATH", "/data/config.json"))
CREDENTIALS_PATH = Path(os.environ.get("CREDENTIALS_PATH", "/data/credentials.json"))
CLIPS_PATH = Path(os.environ.get("CLIPS_PATH", "/data/clips"))


def log(msg):
    print(f"[squirrel-cam] {msg}", flush=True)


def load_config():
    if CONFIG_PATH.exists():
        return json.load(open(CONFIG_PATH))
    return {"poll_interval_sec": 300}


def load_credentials():
    if not CREDENTIALS_PATH.exists():
        return None
    return json.load(open(CREDENTIALS_PATH))


class SquirrelCam:
    def __init__(self, config: dict):
        self.config = config
        self.blink = None
        self.session = None
        self.last_clip_time = {}

    async def connect(self) -> bool:
        creds = load_credentials()
        if not creds:
            log(f"ERROR: No credentials at {CREDENTIALS_PATH}")
            log("Run: python3 auth.py")
            return False

        if "token" not in creds and "client_id" not in creds:
            log("ERROR: Credentials missing auth token")
            log("Run: python3 auth.py")
            return False

        self.session = aiohttp.ClientSession()
        self.blink = Blink(session=self.session)
        self.blink.auth = Auth(creds, no_prompt=True, session=self.session)

        try:
            await self.blink.start()
        except Exception as e:
            log(f"ERROR: Blink connection failed: {e}")
            return False

        if not self.blink.cameras:
            log("ERROR: No cameras found")
            return False

        log(f"Connected. Cameras: {list(self.blink.cameras.keys())}")
        return True

    async def poll_clips(self):
        await self.blink.refresh()

        for name, camera in self.blink.cameras.items():
            if not camera.clip or not camera.last_motion:
                continue

            if name in self.last_clip_time and camera.last_motion <= self.last_clip_time[name]:
                continue

            self.last_clip_time[name] = camera.last_motion
            clip_path = CLIPS_PATH / f"{name}_{datetime.now():%Y%m%d_%H%M%S}.mp4"

            log(f"Downloading: {name}")
            await camera.video_to_file(str(clip_path))
            log(f"Saved: {clip_path.name}")

            # TODO: Run squirrel detection here
            # detected = self.detect_squirrel(clip_path)

        # Keep only last N clips to prevent storage filling up
        self.cleanup_old_clips()

    def cleanup_old_clips(self, keep: int = 20):
        """Delete oldest clips, keeping only the most recent N."""
        clips = sorted(CLIPS_PATH.glob("*.mp4"), key=lambda p: p.stat().st_mtime)
        to_delete = clips[:-keep] if len(clips) > keep else []
        for clip in to_delete:
            clip.unlink()
            log(f"Deleted old clip: {clip.name}")

    async def run(self):
        CLIPS_PATH.mkdir(parents=True, exist_ok=True)

        if not await self.connect():
            return

        interval = self.config.get("poll_interval_sec", 300)
        log(f"Polling every {interval}s")

        while True:
            try:
                await self.poll_clips()
            except Exception as e:
                log(f"Error: {e}")
            await asyncio.sleep(interval)

    async def cleanup(self):
        if self.session:
            await self.session.close()


async def main():
    log("Starting...")
    cam = SquirrelCam(load_config())
    try:
        await cam.run()
    finally:
        await cam.cleanup()


if __name__ == "__main__":
    asyncio.run(main())
