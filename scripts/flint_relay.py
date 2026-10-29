#!/usr/bin/env python3
"""flint_relay.py: expose Flint on the LAN. `rec serve` binds loopback only (its `--port` is a "loopback port", there is no host
flag), so this relays TCP from RELAY_HOST:RELAY_PORT (default 0.0.0.0:11502) to 127.0.0.1:UPSTREAM_PORT (default 11500, rec).
Bytes only: rec's API key still applies to every request, and the traffic is plain HTTP (anyone who can read LAN traffic can read
the key). Run by launchd (scripts/install_launchd.sh). Stdlib only."""
import asyncio, os, sys, time

HOST = os.environ.get("RELAY_HOST", "0.0.0.0")
PORT = int(os.environ.get("RELAY_PORT", "11502"))
UP = int(os.environ.get("UPSTREAM_PORT", "11500"))


def log(msg):
    print(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} {msg}", flush=True)


async def pipe(r, w):
    try:
        while data := await r.read(65536):
            w.write(data)
            await w.drain()
    except (ConnectionError, asyncio.CancelledError):
        pass
    finally:
        try:
            w.write_eof()  # half-close: let the other direction finish
        except (OSError, RuntimeError):
            pass


async def handle(cr, cw):
    peer = cw.get_extra_info("peername")
    try:
        ur, uw = await asyncio.open_connection("127.0.0.1", UP)
    except OSError as e:
        log(f"{peer}: upstream 127.0.0.1:{UP} unavailable ({e})")
        cw.close()
        return
    try:
        await asyncio.gather(pipe(cr, uw), pipe(ur, cw))
    finally:
        for w in (uw, cw):
            w.close()


async def main():
    server = await asyncio.start_server(handle, HOST, PORT, reuse_address=True)
    log(f"relaying {HOST}:{PORT} -> 127.0.0.1:{UP}")
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(0)
