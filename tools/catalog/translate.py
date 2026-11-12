"""Entry point for the P026 translation pipeline: `uv run python translate.py run|review|sample|check`."""
from catalog.translate import main

if __name__ == "__main__":
    raise SystemExit(main())
