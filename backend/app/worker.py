"""
The background worker: delivers reminders at their time and reads captured files.

    python -m app.worker

Run it next to the API (same DATABASE_URL and settings). Several workers can run at once;
the job queue makes sure each job is taken by only one of them.
"""

import asyncio
import logging
import signal

from app.database import AsyncSessionLocal
from app.services import jobs
from app.services.capture_jobs import PROCESS, capture_failed, process_capture
from app.services.delivery import deliver_reminder
from app.services.scheduling import DELIVER

HANDLERS = {DELIVER: deliver_reminder, PROCESS: process_capture}
ON_FAILURE = {PROCESS: capture_failed}


async def _main() -> None:
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stop.set)  # finish the current job, then exit
        except (NotImplementedError, RuntimeError):
            pass  # Windows: Ctrl+C still stops the process
    await jobs.run_forever(AsyncSessionLocal, HANDLERS, on_failure=ON_FAILURE, stop=stop)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    asyncio.run(_main())


if __name__ == "__main__":
    main()
