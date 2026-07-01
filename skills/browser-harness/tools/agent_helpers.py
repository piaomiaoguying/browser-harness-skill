"""Background-mode for browser-harness.

Put this file at the same directory level as your browser-harness scripts.
Then at the top of every script add a single line BEFORE any other import:

    import os; os.environ["BH_BACKGROUND"] = "1"

The monkey-patch uses Runtime.evaluate to set BH_BACKGROUND in the daemon's
process before switch_tab / new_tab are called, so no file deployment is needed.

When BH_BACKGROUND=1:
  - switch_tab() skips Target.activateTarget — no OS focus change, no visible tab switch
  - new_tab() passes background=True — new tabs open behind the current tab
  - All other helpers (js, click_at_xy, capture_screenshot, etc.) are CDP-native
    and work identically in background tabs.
"""
import os
from browser_harness.helpers import cdp, _send, _mark_tab as _mark

if os.environ.get("BH_BACKGROUND") != "1":
    switch_tab = None
    new_tab = None
else:
    from browser_harness.helpers import current_tab as _current_tab
    from browser_harness.helpers import goto_url as _goto_url

    def switch_tab(target):
        """switch_tab without Target.activateTarget — session bind only."""
        target_id = (
            (target.get("targetId") or target.get("target_id"))
            if isinstance(target, dict)
            else target
        )
        try:
            cdp(
                "Runtime.evaluate",
                expression=(
                    "if(document.title.startsWith('\\uD83D\\uDC34 '))"
                    "document.title=document.title.slice(3)"
                ),
            )
        except Exception:
            pass
        sid = cdp("Target.attachToTarget", targetId=target_id, flatten=True)["sessionId"]
        _send({"meta": "set_session", "session_id": sid, "target_id": target_id})
        _mark()
        return sid

    def new_tab(url="about:blank"):
        """new_tab — creates tab in background, never activates."""
        if url != "about:blank":
            try:
                cur = _current_tab()
                cur_url = cur.get("url") or ""
                if cur_url in ("", "about:blank") or cur_url.startswith("about:blank#"):
                    _goto_url(url)
                    return cur.get("targetId") or cur.get("target_id")
            except Exception:
                pass
        tid = cdp("Target.createTarget", url="about:blank", background=True)["targetId"]
        switch_tab(tid)
        if url != "about:blank":
            _goto_url(url)
        return tid
