use std::collections::BTreeMap;

pub struct Recording<'a> {
    pub metadata: BTreeMap<String, String>,
    pub cores: Vec<Core<'a>>,
}

pub struct Core<'a> {
    pub id: u32,
    pub offset: usize,
    pub bytes: &'a [u8],
}

impl<'a> Recording<'a> {
    pub fn parse(bytes: &'a [u8]) -> Result<Self, String> {
        let mut offset = 0;
        let mut metadata = BTreeMap::new();
        let mut core_offsets = Vec::new();
        if bytes.starts_with(b";\n;") || bytes.starts_with(b";\r\n;") {
            loop {
                let rest = &bytes[offset..];
                let len = rest
                    .iter()
                    .position(|&byte| byte == b'\n')
                    .ok_or("unterminated recording header")?;
                let line = rest[..len]
                    .strip_prefix(b";")
                    .ok_or("expected a recording header line")?;
                let line = String::from_utf8_lossy(line);
                let line = line.trim();
                let first = offset == 0;
                offset += len + 1;
                if line.is_empty() {
                    if first {
                        continue;
                    }
                    break;
                }
                if let Some(value) = line.strip_prefix("Offset Core") {
                    let (id, start) = value
                        .split_once(char::is_whitespace)
                        .ok_or("invalid core offset in recording header")?;
                    let id = id.parse::<u32>().map_err(|_| "invalid core ID")?;
                    let start = start
                        .trim()
                        .parse::<usize>()
                        .map_err(|_| "invalid core offset")?;
                    if core_offsets.iter().any(|&(previous, _)| previous == id) {
                        return Err(format!("duplicate core ID {id}"));
                    }
                    core_offsets.push((id, start));
                } else {
                    let (key, value) = line.split_once(char::is_whitespace).unwrap_or((line, ""));
                    metadata.insert(key.to_owned(), value.trim().to_owned());
                }
            }
        }

        let stream = &bytes[offset..];
        if stream.is_empty() {
            return Err("recording has no packet data".into());
        }
        if core_offsets.is_empty() {
            core_offsets.push((0, 0));
        }
        core_offsets.sort_by_key(|&(_, start)| start);
        if core_offsets[0].1 != 0 {
            return Err("first core must begin at the start of the packet data".into());
        }

        let mut cores = Vec::new();
        for (index, &(id, start)) in core_offsets.iter().enumerate() {
            let end = core_offsets
                .get(index + 1)
                .map_or(stream.len(), |entry| entry.1);
            if start >= end || end > stream.len() {
                return Err(format!("invalid byte range for core {id}"));
            }
            cores.push(Core {
                id,
                offset: offset + start,
                bytes: &stream[start..end],
            });
        }
        Ok(Self { metadata, cores })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn core_offsets_are_relative_to_the_end_of_the_header() {
        let header = b";\r\n; Title Test\r\n; Offset Core0 0\r\n; Offset Core3 2\r\n;\r\n";
        let mut bytes = header.to_vec();
        bytes.extend([10, 0, 11, 0]);
        let recording = Recording::parse(&bytes).unwrap();
        assert_eq!(recording.metadata["Title"], "Test");
        assert_eq!(recording.cores[0].bytes, [10, 0]);
        assert_eq!(recording.cores[1].id, 3);
        assert_eq!(recording.cores[1].offset, header.len() + 2);
        assert_eq!(recording.cores[1].bytes, [11, 0]);
        assert!(Recording::parse(&bytes[..header.len() + 2]).is_err());
    }

    #[test]
    fn a_raw_event_with_id_59_is_not_a_recording_header() {
        let stream = [59, 0, 10];
        let recording = Recording::parse(&stream).unwrap();
        assert!(recording.metadata.is_empty());
        assert_eq!(recording.cores[0].bytes, stream);
    }
}
