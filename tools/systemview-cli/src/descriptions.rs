use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::Path;

#[derive(Default)]
pub struct Descriptions(BTreeMap<String, BTreeMap<u32, Definition>>);

pub struct Definition {
    pub symbol: String,
    pub signature: String,
}

impl Descriptions {
    pub fn load(dir: &Path) -> io::Result<Self> {
        let mut descriptions = BTreeMap::new();
        for entry in fs::read_dir(dir)? {
            let entry = entry?;
            let filename = entry.file_name();
            let Some(name) = filename
                .to_str()
                .and_then(|name| name.strip_prefix("SYSVIEW_"))
                .and_then(|name| name.strip_suffix(".txt"))
            else {
                continue;
            };
            let text = fs::read(entry.path())?;
            let text = String::from_utf8_lossy(&text);
            let definitions = text
                .lines()
                .filter_map(|line| {
                    let (id, tail) = line.trim().split_once(char::is_whitespace)?;
                    let id = id
                        .strip_prefix("0x")
                        .map_or_else(|| id.parse(), |hex| u32::from_str_radix(hex, 16))
                        .ok()?;
                    let tail = tail.trim();
                    let (symbol, signature) =
                        tail.split_once(char::is_whitespace).unwrap_or((tail, ""));
                    Some((
                        id,
                        Definition {
                            symbol: symbol.to_owned(),
                            signature: signature.trim().to_owned(),
                        },
                    ))
                })
                .collect();
            descriptions.insert(name.to_owned(), definitions);
        }
        Ok(Self(descriptions))
    }

    pub fn lookup(&self, name: &str, version: Option<&str>, id: u32) -> Option<&Definition> {
        version
            .and_then(|version| self.0.get(&format!("{name}_{version}")))
            .or_else(|| self.0.get(name))?
            .get(&id)
    }
}
