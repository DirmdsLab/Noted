#!/usr/bin/env python3

import asyncio
import json
import uuid
import websockets

HOST = "127.0.0.1"
WS_PORT = 5090
TCP_PORT = 5091

extension = None
extension_lock = asyncio.Lock()
pending = {}


async def websocket_handler(websocket):
    global extension

    async with extension_lock:
        old = extension
        extension = websocket

    if old is not None and old is not websocket:
        try:
            await old.close()
        except Exception:
            pass

    print("[SERVER] Extension connected")

    try:
        async for raw in websocket:
            try:
                message = json.loads(raw)
            except Exception:
                continue

            request_id = message.get("id")

            if request_id is None:
                continue

            future = pending.pop(request_id, None)

            if future is not None and not future.done():
                future.set_result(message)

    except websockets.exceptions.ConnectionClosed:
        pass
    except Exception as error:
        print("[SERVER] WebSocket error:", error)

    finally:
        async with extension_lock:
            if extension is websocket:
                extension = None

        for request_id, future in list(pending.items()):
            if not future.done():
                future.set_exception(
                    RuntimeError("Extension terputus")
                )

        pending.clear()

        print("[SERVER] Extension disconnected")


async def send_command(command):
    async with extension_lock:
        ws = extension

    if ws is None:
        raise RuntimeError(
            "Extension belum terhubung. "
            "Buka ChatGPT lalu jalankan connectterminal()"
        )

    request_id = command["id"]

    loop = asyncio.get_running_loop()
    future = loop.create_future()

    pending[request_id] = future

    try:
        await ws.send(json.dumps(command))

        return await asyncio.wait_for(
            future,
            timeout=65
        )

    except Exception:
        pending.pop(request_id, None)
        raise


async def terminal_client(reader, writer):
    try:
        data = await asyncio.wait_for(
            reader.readline(),
            timeout=5
        )

        if not data:
            return

        text = data.decode(
            "utf-8",
            errors="replace"
        ).rstrip("\r\n")

        if not text:
            return

        print(
            "[SERVER] Terminal:",
            repr(text)
        )

        request_id = str(uuid.uuid4())

        if text == "__NEW_SESSION__":
            command = {
                "id": request_id,
                "type": "NEW_SESSION"
            }
        else:
            command = {
                "id": request_id,
                "type": "CHAT",
                "text": text
            }

        try:
            result = await send_command(command)

            if result.get("ok"):
                output = result.get("text", "")

                writer.write(
                    output.encode("utf-8")
                )

                writer.write(b"\n")

            else:
                error = result.get(
                    "error",
                    "Unknown error"
                )

                writer.write(
                    (
                        "ERROR: " +
                        error +
                        "\n"
                    ).encode("utf-8")
                )

        except asyncio.TimeoutError:
            writer.write(
                b"ERROR: Timeout menunggu response\n"
            )

        except Exception as error:
            writer.write(
                (
                    "ERROR: " +
                    str(error) +
                    "\n"
                ).encode("utf-8")
            )

        await writer.drain()

    except asyncio.TimeoutError:
        writer.write(
            b"ERROR: TCP timeout\n"
        )

        try:
            await writer.drain()
        except Exception:
            pass

    except Exception as error:
        print(
            "[SERVER] TCP error:",
            error
        )

    finally:
        writer.close()

        try:
            await writer.wait_closed()
        except Exception:
            pass


async def main():
    print(
        f"[SERVER] WebSocket: ws://{HOST}:{WS_PORT}"
    )

    print(
        f"[SERVER] Terminal TCP: {HOST}:{TCP_PORT}"
    )

    ws_server = await websockets.serve(
        websocket_handler,
        HOST,
        WS_PORT
    )

    tcp_server = await asyncio.start_server(
        terminal_client,
        HOST,
        TCP_PORT
    )

    print("[SERVER] Ready")

    try:
        await asyncio.gather(
            ws_server.wait_closed(),
            tcp_server.serve_forever()
        )

    except asyncio.CancelledError:
        pass

    finally:
        tcp_server.close()
        await tcp_server.wait_closed()

        ws_server.close()
        await ws_server.wait_closed()


if __name__ == "__main__":
    asyncio.run(main())