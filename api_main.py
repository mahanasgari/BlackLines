from __future__ import annotations

import logging
import os

import uvicorn

logging.basicConfig(
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    level=logging.INFO,
)


def main() -> None:
    host = os.getenv("API_HOST", "127.0.0.1")
    port = int(os.getenv("API_PORT", "8105"))
    uvicorn.run("app.api:app", host=host, port=port, reload=False)


if __name__ == "__main__":
    main()
