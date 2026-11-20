"""USART6 test cases shared by the Renode script and the live UART runner."""

READY = b"READY 115200 8N1\r\n"
PONG = b"OK pong\r\n"
BURST = 10
SINGLES = [
    (b"pi", b""),
    (b"ng\n", PONG),
    (b"led on\r\n", b"OK led on\r\n"),
    (b"status\n", b"OK led=on dropped=0 errors=0\r\n"),
    (b"wat\n", b"ERR unknown\r\n"),
    (b"pi\rng\n", b"ERR malformed\r\n"),
    (b"ping\x00\n", b"ERR malformed\r\n"),
    (b"a" * 24 + b"\n", b"ERR malformed\r\n"),
    (b"\n", b"ERR malformed\r\n"),
    (b"led off\n", b"OK led off\r\n"),
]
