use std::{fs, path::Path};

use crate::{FLASH_BASE, FLASH_SIZE, Result};

pub(super) fn read(path: &Path) -> Result<Vec<u8>> {
    decode(&fs::read_to_string(path)?)
}

fn decode(text: &str) -> Result<Vec<u8>> {
    let mut image = Vec::new();
    let mut upper = 0usize;
    let mut finished = false;
    let mut reset_covered = false;
    let mut reset_address = None;
    for (index, line) in text.lines().enumerate() {
        if finished || !line.starts_with(':') || line.len() < 11 || line.len() % 2 == 0 {
            return Err(format!("invalid Intel HEX line {}", index + 1).into());
        }
        let payload = &line.as_bytes()[1..];
        let record = payload
            .as_chunks::<2>()
            .0
            .iter()
            .map(|pair| -> Result<u8> { Ok(u8::from_str_radix(std::str::from_utf8(pair)?, 16)?) })
            .collect::<Result<Vec<_>>>()?;
        if record.len() != usize::from(record[0]) + 5
            || record.iter().copied().fold(0u8, u8::wrapping_add) != 0
        {
            return Err(
                format!("invalid Intel HEX length or checksum at line {}", index + 1).into(),
            );
        }
        let address = usize::from(u16::from_be_bytes([record[1], record[2]]));
        let data = &record[4..record.len() - 1];
        match (record[3], address, data) {
            (0, _, bytes) if !bytes.is_empty() => {
                let base = upper + address;
                let offset = base
                    .checked_sub(FLASH_BASE as usize)
                    .ok_or("Intel HEX record starts below flash")?;
                if offset + bytes.len() > FLASH_SIZE || offset < image.len() {
                    return Err("Intel HEX record overlaps data or exceeds flash".into());
                }
                if image.is_empty() && (offset != 0 || bytes.len() < 8) {
                    return Err("Intel HEX is missing the first eight flash bytes".into());
                }
                if image.is_empty() {
                    reset_address = Some(u32::from_le_bytes(bytes[4..8].try_into()?) as usize & !1);
                }
                reset_covered |=
                    reset_address.is_some_and(|pc| (base..base + bytes.len()).contains(&pc));
                image.resize(offset, 0xff);
                image.extend_from_slice(bytes);
            }
            (1, 0, []) => finished = true,
            (4, 0, [high, low]) => upper = usize::from(u16::from_be_bytes([*high, *low])) << 16,
            (5, 0, [_, _, _, _]) => {}
            _ => return Err(format!("unsupported Intel HEX record at line {}", index + 1).into()),
        }
    }
    if !finished || !reset_covered {
        return Err("Intel HEX is missing EOF or the reset target bytes".into());
    }
    Ok(image)
}

#[cfg(test)]
mod tests {
    use super::decode;

    const SPLIT: &str = concat!(
        ":020000040800F2\r\n",
        ":10000000F8FF04201D010208130C0508010C050867\r\n",
        ":020000040802F0\r\n",
        ":02011C0000BF22\r\n",
        ":040000050802011DCF\r\n",
        ":00000001FF\r\n",
    );

    #[test]
    fn split_hex_preserves_vectors_and_gap() {
        let image = decode(SPLIT).unwrap();
        assert_eq!(
            &image[..8],
            &[0xf8, 0xff, 0x04, 0x20, 0x1d, 0x01, 0x02, 0x08]
        );
        assert!(image[16..0x2011c].iter().all(|byte| *byte == 0xff));
        assert_eq!(&image[0x2011c..], &[0x00, 0xbf]);
    }

    #[test]
    fn split_hex_rejects_corrupt_or_missing_text() {
        assert!(decode(&SPLIT.replace(":02011C0000BF22", ":02011C0000BE22")).is_err());
        assert!(decode(&SPLIT.replace(":02011C0000BF22\r\n", "")).is_err());
    }
}
