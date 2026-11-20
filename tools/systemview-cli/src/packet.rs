pub struct Cursor<'a> {
    bytes: &'a [u8],
    pub pos: usize,
}

#[derive(Debug)]
pub struct Packet<'a> {
    pub id: u32,
    pub offset: usize,
    pub payload: &'a [u8],
    pub delta: u32,
}

impl<'a> Cursor<'a> {
    pub fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, pos: 0 }
    }

    pub fn remaining(&self) -> &'a [u8] {
        &self.bytes[self.pos..]
    }

    fn take(&mut self, len: usize) -> Result<&'a [u8], &'static str> {
        let (value, _) = self
            .remaining()
            .split_at_checked(len)
            .ok_or("truncated payload")?;
        self.pos += len;
        Ok(value)
    }

    pub fn uint(&mut self) -> Result<u32, &'static str> {
        let mut result = 0;
        for shift in (0..32).step_by(7) {
            let [byte, ..] = self.remaining() else {
                return Err("truncated integer");
            };
            if shift == 28 && *byte > 15 {
                return Err("integer exceeds 32 bits");
            }
            self.pos += 1;
            result |= u32::from(*byte & 0x7f) << shift;
            if *byte < 0x80 {
                return Ok(result);
            }
        }
        unreachable!("the high byte has no continuation bit")
    }

    pub fn string(&mut self) -> Result<String, &'static str> {
        Ok(String::from_utf8_lossy(self.string_bytes()?).into_owned())
    }

    fn string_bytes(&mut self) -> Result<&'a [u8], &'static str> {
        let mut size = usize::from(self.take(1)?[0]);
        if size == 255 {
            let word = self.take(2)?;
            size = usize::from(u16::from_be_bytes([word[0], word[1]]));
        }
        self.take(size)
    }

    pub fn next_packet(&mut self, base: usize) -> Result<Option<Packet<'a>>, String> {
        while self.remaining().starts_with(&[0; 10]) {
            self.pos += 10;
        }
        if self.remaining().is_empty() {
            return Ok(None);
        }
        let offset = base + self.pos;
        self.packet(offset)
            .map(Some)
            .map_err(|error| format!("byte 0x{offset:x}: {error}"))
    }

    fn packet(&mut self, offset: usize) -> Result<Packet<'a>, &'static str> {
        // Standard IDs have an implied payload layout. Other IDs carry a byte length.
        const SHAPES: [&[u8]; 24] = [
            b"", b"u", b"u", b"", b"u", b"", b"u", b"uu", b"u", b"uus", b"", b"", b"u", b"uu",
            b"s", b"u", b"u", b"", b"", b"u", b"", b"uuuu", b"uus", b"uu",
        ];
        let id = self.uint()?;
        let payload = if let Some(shape) = SHAPES.get(id as usize) {
            let start = self.pos;
            for &field in *shape {
                if field == b'u' {
                    self.uint()?;
                } else {
                    self.string_bytes()?;
                }
            }
            &self.bytes[start..self.pos]
        } else {
            let length = self.uint()? as usize;
            self.take(length)?
        };
        let delta = self.uint()?;
        Ok(Packet {
            id,
            offset,
            payload,
            delta,
        })
    }
}

pub fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write;
    let mut result = String::with_capacity(bytes.len().saturating_mul(2));
    for byte in bytes {
        write!(result, "{byte:02x}").expect("writing to a string cannot fail");
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frames_extended_id_and_consumes_exact_payload_length() {
        let mut bytes = vec![0; 10];
        bytes.extend([0x80, 1, 0x82, 1]);
        bytes.extend([0x85; 130]);
        bytes.extend([0xff, 0xff, 0xff, 0xff, 0x0f, 11, 0]);
        let mut cursor = Cursor::new(&bytes);
        let packet = cursor.next_packet(100).unwrap().unwrap();
        assert_eq!(
            (packet.id, packet.offset, packet.delta),
            (128, 110, u32::MAX)
        );
        assert_eq!(packet.payload, &[0x85; 130]);
        assert_eq!(cursor.next_packet(100).unwrap().unwrap().id, 11);
        assert!(cursor.next_packet(100).unwrap().is_none());
    }

    #[test]
    fn bounds_check_strings_and_varints() {
        let mut cursor = Cursor::new(&[14, 255, 0, 2, b'o', b'k', 0, 2, 42, 0x80]);
        let packet = cursor.next_packet(0).unwrap().unwrap();
        assert_eq!(Cursor::new(packet.payload).string().unwrap(), "ok");
        assert_eq!(
            cursor.next_packet(0).unwrap_err(),
            "byte 0x7: truncated integer"
        );
        assert_eq!(
            Cursor::new(&[0xff, 0xff, 0xff, 0xff, 0x10]).uint(),
            Err("integer exceeds 32 bits")
        );
    }
}
