#!/usr/bin/env python3
"""
Squirrel Cam - Fetch Blink clips and run animal detection

Polls Blink cameras for new motion clips, downloads them, and runs detection.
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
TWO_FA_PATH = Path(os.environ.get("TWO_FA_PATH", "/data/2fa_code.txt"))
CLIPS_PATH = Path(os.environ.get("CLIPS_PATH", "/data/clips"))

LOG_PREFIX = "[squirrel-cam]"


def log(msg):
    print(f"{LOG_PREFIX} {msg}", flush=True)


def load_config():
    if CONFIG_PATH.exists():
        return json.load(open(CONFIG_PATH))
    return {
        "poll_interval_sec": 300,
        "detection_threshold": 0.5,
        "classes": ["squirrel", "chipmunk", "bird", "cat", "raccoon"],
    }


def load_credentials():
    if CREDENTIALS_PATH.exists():
        return json.load(open(CREDENTIALS_PATH))
    return None


def save_credentials(creds: dict):
    CREDENTIALS_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(CREDENTIALS_PATH, "w") as f:
        json.dump(creds, f, indent=2)
    log("Credentials/token saved")


class SquirrelCam:
    def __init__(self, config: dict):
        self.config = config
        self.blink = None
        self.session = None
        self.last_clip_time = {}

    async def setup_blink(self) -> bool:
        creds = load_credentials()
        if not creds:
            log("No credentials found at " + str(CREDENTIALS_PATH))
            log("Create credentials.json with:")
            log('  {"username": "email@example.com", "password": "your_password"}')
            return False

        # Create aiohttp session
        if self.session is None or self.session.closed:
            self.session = aiohttp.ClientSession()

        self.blink = Blink(session=self.session)
        auth = Auth(creds, no_prompt=True, session=self.session)
        self.blink.auth = auth

        try:
            await self.blink.start()
        except Exception as e:
            err_str = str(e).lower()
            err_type = type(e).__name__

            # Check for 2FA requirement
            if "2fa" in err_str or "2fa" in err_type.lower() or "key" in err_str:
                return await self._handle_2fa()

            log(f"Blink auth failed: {e}")
            return False

        # Check if 2FA is needed by looking for key_required attribute
        try:
            if hasattr(self.blink.auth, 'key_required') and self.blink.auth.key_required:
                return await self._handle_2fa()
        except Exception:
            pass

        # Check if we actually have cameras (indicates successful auth)
        if not self.blink.cameras:
            log("No cameras found - may need 2FA")
            return await self._handle_2fa()

        # Save updated credentials (includes refreshed token)
        save_credentials(self.blink.auth.login_attributes)

        log(f"Connected to Blink. Found {len(self.blink.cameras)} cameras:")
        for name in self.blink.cameras:
            log(f"  - {name}")
        return True

    async def _handle_2fa(self) -> bool:
        """Handle 2FA verification."""
        log("2FA required - check your email/SMS for verification code")

        # Check if 2FA code file exists
        if TWO_FA_PATH.exists():
            code = TWO_FA_PATH.read_text().strip()
            if code:
                log(f"Found 2FA code: {code[:2]}****")
                try:
                    await self.blink.auth.send_auth_key(self.blink, code)
                    await self.blink.setup_post_verify()
                    save_credentials(self.blink.auth.login_attributes)
                    TWO_FA_PATH.unlink()  # Delete code file after use
                    log("2FA verification successful!")

                    if self.blink.cameras:
                        log(f"Found {len(self.blink.cameras)} cameras")
                        return True
                    return True
                except Exception as e:
                    log(f"2FA verification failed: {e}")
                    TWO_FA_PATH.unlink(missing_ok=True)
                    return False

        log(f"Waiting for 2FA code...")
        log(f"  echo 'YOUR_CODE' > {TWO_FA_PATH}")
        return False

    async def fetch_new_clips(self):
        """Check for new motion clips and download them."""
        await self.blink.refresh()

        for name, camera in self.blink.cameras.items():
            clip_url = camera.clip
            if not clip_url:
                continue

            last_motion = camera.last_motion
            if not last_motion:
                continue

            # Skip if we've already processed this clip
            last_seen = self.last_clip_time.get(name)
            if last_seen and last_motion <= last_seen:
                continue

            self.last_clip_time[name] = last_motion

            # Download clip
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            clip_path = CLIPS_PATH / f"{name}_{timestamp}.mp4"

            log(f"Downloading clip from {name}...")
            await camera.video_to_file(str(clip_path))
            log(f"Saved: {clip_path.name}")

            self.process_clip(clip_path)

    def process_clip(self, clip_path: Path):
        """Run detection on a clip."""
        # TODO: Implement actual inference
        log(f"Processing {clip_path.name} (stub mode)")

        if hash(clip_path.name) % 3 == 0:
            log(f"🐿️ Squirrel detected in {clip_path.name}!")

    async def run(self):
        CLIPS_PATH.mkdir(parents=True, exist_ok=True)

        # Auth loop - retry until successful, with longer delays to avoid 2FA spam
        retry_count = 0
        while not await self.setup_blink():
            retry_count += 1
            delay = min(30 * retry_count, 300)  # Increase delay, max 5 min
            log(f"Retrying in {delay}s...")
            await asyncio.sleep(delay)

        poll_interval = self.config.get("poll_interval_sec", 300)
        log(f"Polling every {poll_interval}s for new clips")

        while True:
            try:
                await self.fetch_new_clips()
            except Exception as e:
                log(f"Error fetching clips: {e}")

            await asyncio.sleep(poll_interval)

    async def cleanup(self):
        if self.session and not self.session.closed:
            await self.session.close()


async def main():
    log("Starting...")
    config = load_config()
    log(f"Config: poll_interval={config.get('poll_interval_sec')}s")

    cam = SquirrelCam(config)
    try:
        await cam.run()
    finally:
        await cam.cleanup()


if __name__ == "__main__":
    asyncio.run(main())
