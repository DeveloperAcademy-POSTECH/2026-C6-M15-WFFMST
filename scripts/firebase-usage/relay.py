"""기기와 Firebase 에뮬레이터 사이에서 주고받은 양을 기록하는 중계기.

맥 IP의 9099(Auth)·8080(Firestore)·9199(Storage)에서 받아 127.0.0.1의 같은 포트(에뮬레이터)로 넘긴다.
에뮬레이터는 127.0.0.1에서만 열려 있어야 한다. 보통은 `scripts/measure-firebase.sh`가 순서대로 켠다.

- Storage: HTTP 요청마다 동작·경로·바이트·상태를 기록한다.
- Auth·Firestore: 기기별 주고받은 바이트만 센다. Firestore는 gRPC라 요청 단위로 나누지 않는다.

    python3 relay.py --host <맥 IP> --out <md 폴더> --raw <원본 기록 폴더>

md 폴더에는 <날짜_시각>_firebase-usage.md 하나만 두고 3초마다 새로 쓴다.
요청별 원본 기록(<날짜_시각>_traffic.jsonl)은 원본 기록 폴더에 둔다.
"""
import argparse
import asyncio
import json
import os
import signal
import sys
import time
import urllib.parse

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import summary  # noqa: E402

PORTS = {9099: "auth", 8080: "firestore", 9199: "storage"}


class Recorder:
    def __init__(self, out_dir, raw_dir):
        self.stamp = time.strftime("%Y-%m-%d_%H%M")
        os.makedirs(out_dir, exist_ok=True)
        os.makedirs(raw_dir, exist_ok=True)
        self.log_path = os.path.join(raw_dir, f"{self.stamp}_traffic.jsonl")
        self.md_path = os.path.join(out_dir, f"{self.stamp}_firebase-usage.md")
        self.log_file = open(self.log_path, "a", buffering=1)
        # "서비스 기기IP"별 누적. 열려 있는 연결(Firestore 구독 등)도 포함한다.
        self.totals = {}

    def add(self, service, client, key, amount):
        row = self.totals.setdefault(f"{service} {client}", {"uploadBytes": 0, "downloadBytes": 0})
        row[key] += amount

    def log(self, entry):
        entry["time"] = round(time.time(), 3)
        self.log_file.write(json.dumps(entry, ensure_ascii=False) + "\n")

    def write_markdown(self):
        text = summary.render(self.log_path, self.stamp, self.totals)
        with open(self.md_path, "w") as file:
            file.write(text)

    async def write_markdown_forever(self):
        while True:
            await asyncio.sleep(3)
            self.write_markdown()


async def pump(reader, writer, on_bytes):
    try:
        while data := await reader.read(65536):
            on_bytes(len(data))
            writer.write(data)
            await writer.drain()
    except (ConnectionError, asyncio.IncompleteReadError):
        pass
    finally:
        writer.close()


async def forward_message(reader, writer):
    """HTTP 메시지 하나(헤더 + 본문)를 그대로 넘기고 (첫 줄, 헤더, 전체 바이트, 본문 바이트)를 돌려준다."""
    head = await reader.readuntil(b"\r\n\r\n")
    writer.write(head)
    lines = head.decode("latin-1").split("\r\n")
    headers = {}
    for line in lines[1:]:
        if ":" in line:
            name, value = line.split(":", 1)
            headers[name.strip().lower()] = value.strip()
    body = 0
    if headers.get("transfer-encoding", "").lower() == "chunked":
        while True:
            size_line = await reader.readuntil(b"\r\n")
            writer.write(size_line)
            size = int(size_line.split(b";")[0].strip(), 16)
            writer.write(await reader.readexactly(size + 2))
            body += size
            if size == 0:
                break
    else:
        remaining = body = int(headers.get("content-length", "0") or 0)
        while remaining:
            data = await reader.read(min(remaining, 65536))
            if not data:
                raise asyncio.IncompleteReadError(b"", remaining)
            writer.write(data)
            remaining -= len(data)
    await writer.drain()
    return lines[0], headers, len(head) + body, body


async def relay_storage(recorder, client_reader, client_writer, server_reader, server_writer, client):
    # 응답은 요청 순서대로 온다. 요청 정보를 줄 세워 두고 응답이 오면 짝지어 기록한다.
    pending = asyncio.Queue()

    async def requests():
        try:
            while True:
                first, headers, total, body = await forward_message(client_reader, server_writer)
                method, target = first.split(" ")[:2]
                parsed = urllib.parse.urlsplit(target)
                query = urllib.parse.parse_qs(parsed.query)
                await pending.put({
                    "service": "storage", "client": client, "method": method,
                    "path": urllib.parse.unquote(parsed.path),
                    "name": query.get("name", [""])[0],
                    "alt": query.get("alt", [""])[0],
                    "uploadCommand": headers.get("x-goog-upload-command", ""),
                    "requestBytes": total, "requestBody": body,
                })
        except (asyncio.IncompleteReadError, ConnectionError, ValueError):
            await pending.put(None)
            server_writer.close()

    async def responses():
        try:
            while (entry := await pending.get()) is not None:
                first, _, total, body = await forward_message(server_reader, client_writer)
                while first.split(" ")[1] == "100":  # 100 Continue 다음에 실제 응답이 온다
                    first, _, more, body = await forward_message(server_reader, client_writer)
                    total += more
                entry.update({"status": int(first.split(" ")[1]), "responseBytes": total, "responseBody": body})
                recorder.add("storage", client, "uploadBytes", entry["requestBytes"])
                recorder.add("storage", client, "downloadBytes", total)
                recorder.log(entry)
        except (asyncio.IncompleteReadError, ConnectionError, ValueError):
            pass
        finally:
            client_writer.close()

    await asyncio.gather(requests(), responses())


def handler(recorder, port):
    service = PORTS[port]

    async def handle(client_reader, client_writer):
        client = client_writer.get_extra_info("peername")[0]
        try:
            server_reader, server_writer = await asyncio.open_connection("127.0.0.1", port)
        except OSError:
            client_writer.close()
            return
        if service == "storage":
            await relay_storage(recorder, client_reader, client_writer, server_reader, server_writer, client)
            return
        counter = {"uploadBytes": 0, "downloadBytes": 0}

        def on_bytes(key):
            def count(amount):
                counter[key] += amount
                recorder.add(service, client, key, amount)
            return count

        started = time.time()
        await asyncio.gather(
            pump(client_reader, server_writer, on_bytes("uploadBytes")),
            pump(server_reader, client_writer, on_bytes("downloadBytes")),
        )
        recorder.log({"service": service, "client": client, "connection": True,
                      "seconds": round(time.time() - started, 1), **counter})

    return handle


async def main():
    parser = argparse.ArgumentParser(description="Firebase 에뮬레이터 사용량 측정 중계기")
    parser.add_argument("--host", required=True, help="기기가 접속할 맥 IP")
    parser.add_argument("--out", required=True, help="md를 남길 폴더")
    parser.add_argument("--raw", required=True, help="요청별 원본 기록(jsonl)을 둘 폴더")
    args = parser.parse_args()

    recorder = Recorder(args.out, args.raw)
    servers = [await asyncio.start_server(handler(recorder, port), args.host, port) for port in PORTS]
    print(f"중계기: {args.host}:{list(PORTS)} → 127.0.0.1", flush=True)
    print(f"기록: {recorder.md_path}", flush=True)
    # 끌 때(Ctrl+C) 마지막 몇 초도 md에 남긴다.
    stop = asyncio.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        asyncio.get_running_loop().add_signal_handler(sig, stop.set)
    writer = asyncio.create_task(recorder.write_markdown_forever())
    await stop.wait()
    writer.cancel()
    for server in servers:
        server.close()
    recorder.write_markdown()
    print(f"기록을 남겼습니다: {recorder.md_path}", flush=True)


if __name__ == "__main__":
    asyncio.run(main())
