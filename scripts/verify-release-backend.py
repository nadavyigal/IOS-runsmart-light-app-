#!/usr/bin/env python3
"""Check the backend configuration inside a built app without user credentials."""
import argparse
import json
import plistlib
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def verify(app):
    info = plistlib.loads((app / "Info.plist").read_bytes())
    base = info.get("SUPABASE_URL", "").rstrip("/")
    key = info.get("SUPABASE_PUBLISHABLE_KEY", "").strip()
    url = urllib.parse.urlparse(base)
    result = {
        "version": info.get("CFBundleShortVersionString"),
        "build": info.get("CFBundleVersion"),
        "backend_host": url.hostname,
        "passed": False,
    }
    if url.scheme != "https" or not key.startswith("sb_publishable_"):
        result["failure"] = "Missing HTTPS backend or publishable client key"
        return result
    request = urllib.request.Request(base + "/auth/v1/settings", headers={"apikey": key})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            settings = json.load(response)
            result["auth_settings_status"] = response.status
    except urllib.error.HTTPError as error:
        result["auth_settings_status"] = error.code
        result["failure"] = "Packaged key rejected by Auth settings endpoint"
        return result
    except (OSError, ValueError):
        result["failure"] = "Could not verify Auth settings; do not upload"
        return result
    providers = settings.get("external", {})
    result["apple_enabled"] = providers.get("apple") is True
    result["email_enabled"] = providers.get("email") is True
    result["passed"] = result["apple_enabled"] and result["email_enabled"]
    if not result["passed"]:
        result["failure"] = "A shipping sign-in provider is disabled"
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, help="Built .app directory")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = verify(args.app)
    text = json.dumps(result, indent=2) + "\n"
    if args.output:
        args.output.write_text(text)
    print(text, end="")
    sys.exit(0 if result["passed"] else 1)
