use std::io::{self, Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::time::{Duration, Instant};

pub enum Transport {
    Ip,
    Rtt,
    UartBridge,
}

impl Transport {
    fn handshake(&self, socket: &mut TcpStream) -> io::Result<()> {
        let prefix = match self {
            Self::Ip => {
                let mut hello = [0; 32];
                let greeting = b"SEGGER SystemView V4.10.02";
                hello[..greeting.len()].copy_from_slice(greeting);
                socket.write_all(&hello)?;
                socket.read_exact(&mut hello)?;
                return validate_hello(&hello, b"SEGGER SystemView V");
            }
            Self::UartBridge => b"SV\x04\x00",
            Self::Rtt => return Ok(()),
        };
        socket.write_all(prefix)?;
        let mut hello = [0; 4];
        socket.read_exact(&mut hello)?;
        validate_hello(&hello, b"SV")
    }

    fn command(&self, socket: &mut TcpStream, id: u8) -> io::Result<()> {
        match self {
            Self::Ip => socket.write_all(&[1, id]),
            Self::Rtt | Self::UartBridge => socket.write_all(&[id]),
        }
    }
}

fn validate_hello(received: &[u8], expected: &[u8]) -> io::Result<()> {
    if received.starts_with(expected) {
        Ok(())
    } else {
        Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "invalid SystemView hello",
        ))
    }
}

pub fn capture(
    address: &str,
    transport: Transport,
    duration: Duration,
    output: &mut impl Write,
) -> io::Result<()> {
    let timeout = Duration::from_secs(3);
    let mut error = io::Error::new(
        io::ErrorKind::InvalidInput,
        "address resolved to no endpoints",
    );
    let mut connection = None;
    for address in address.to_socket_addrs()? {
        match TcpStream::connect_timeout(&address, timeout) {
            Ok(socket) => {
                connection = Some(socket);
                break;
            }
            Err(err) => error = err,
        }
    }
    let mut socket = connection.ok_or(error)?;
    socket.set_read_timeout(Some(timeout))?;
    socket.set_write_timeout(Some(timeout))?;
    transport.handshake(&mut socket)?;
    let deadline = Instant::now().checked_add(duration).ok_or_else(|| {
        io::Error::new(io::ErrorKind::InvalidInput, "capture duration is too large")
    })?;
    transport.command(&mut socket, 1)?;
    let recording = copy_until(&mut socket, output, deadline);
    if matches!(recording, Ok((_, false))) {
        output.flush()?;
        return Err(io::Error::new(
            io::ErrorKind::UnexpectedEof,
            "target closed the connection during recording",
        ));
    }
    let stop = transport.command(&mut socket, 2);
    let (recorded, _) = recording?;
    stop?;
    let (drained, _) = copy_until(
        &mut socket,
        output,
        Instant::now() + Duration::from_millis(500),
    )?;
    if recorded == 0 && drained == 0 {
        return Err(io::Error::new(
            io::ErrorKind::UnexpectedEof,
            "target produced no trace bytes",
        ));
    }
    output.flush()
}

// A closed connection has no more events to drain or a target to stop.
fn copy_until(
    socket: &mut TcpStream,
    output: &mut impl Write,
    deadline: Instant,
) -> io::Result<(usize, bool)> {
    let mut buffer = [0; 8192];
    let mut written = 0usize;
    loop {
        let Some(remaining) = deadline.checked_duration_since(Instant::now()) else {
            return Ok((written, true));
        };
        socket.set_read_timeout(Some(remaining.max(Duration::from_millis(1))))?;
        match socket.read(&mut buffer) {
            Ok(0) => return Ok((written, false)),
            Ok(count) => {
                output.write_all(&buffer[..count])?;
                written = written.saturating_add(count);
            }
            Err(error)
                if matches!(
                    error.kind(),
                    io::ErrorKind::WouldBlock
                        | io::ErrorKind::TimedOut
                        | io::ErrorKind::Interrupted
                ) =>
            {
                continue;
            }
            Err(error) => return Err(error),
        }
    }
}
