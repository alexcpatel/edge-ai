#!/usr/bin/env python3
"""
Blink authentication - exactly following official blinkpy quickstart.

Usage: python3 auth.py <email> <password>
"""

import sys
import json
import asyncio
from pathlib import Path

import aiohttp
from blinkpy.blinkpy import Blink
from blinkpy.auth import Auth

CREDENTIALS_PATH = Path("/data/credentials.json")


async def authenticate(email: str, password: str):
    print(f"Authenticating {email}...")

    async with aiohttp.ClientSession() as session:
        blink = Blink(session=session)
        auth = Auth({"username": email, "password": password}, no_prompt=True, session=session)
        blink.auth = auth

        try:
            await blink.start()
        except Exception as e:
            # Use the built-in 2FA prompt from blinkpy
            print(f"2FA required (exception: {type(e).__name__})")
            await blink.prompt_2fa()

        if not blink.cameras:
            print("ERROR: No cameras found")
            return False

        # Save credentials with token
        CREDENTIALS_PATH.parent.mkdir(parents=True, exist_ok=True)
        with open(CREDENTIALS_PATH, "w") as f:
            json.dump(blink.auth.login_attributes, f, indent=2)

        print(f"Success! Saved to {CREDENTIALS_PATH}")
        print(f"Cameras: {list(blink.cameras.keys())}")
        return True


def main():
    if len(sys.argv) != 3:
        print("Usage: python3 auth.py <email> <password>")
        sys.exit(1)

    try:
        success = asyncio.run(authenticate(sys.argv[1], sys.argv[2]))
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\nCancelled")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
