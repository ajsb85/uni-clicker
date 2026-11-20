use std::collections::BTreeMap;

use serde_json::{Value, json};

use crate::descriptions::{Definition, Descriptions};
use crate::packet::{Cursor, Packet, hex};

#[derive(Default)]
pub struct State {
    pub system: BTreeMap<String, String>,
    pub timestamp_hz: Option<u32>,
    pub cpu_hz: Option<u32>,
    pub tasks: BTreeMap<u32, String>,
    pub interrupts: BTreeMap<u32, String>,
    pub resources: BTreeMap<u32, String>,
    markers: BTreeMap<u32, String>,
    data: BTreeMap<u32, (String, u32)>,
    modules: BTreeMap<u32, (String, Option<String>)>,
}

pub struct Event {
    pub kind: &'static str,
    pub data: Value,
}

impl State {
    pub fn decode(&mut self, packet: &Packet<'_>, descriptions: &Descriptions) -> Event {
        self.decode_payload(packet, descriptions)
            .unwrap_or_else(|error| Event {
                kind: "undecoded",
                data: json!({"reason": error, "payload_hex": hex(packet.payload)}),
            })
    }

    fn decode_payload(
        &mut self,
        packet: &Packet<'_>,
        descriptions: &Descriptions,
    ) -> Result<Event, &'static str> {
        let mut p = Cursor::new(packet.payload);
        let (kind, data) = match packet.id {
            0 => ("nop", json!({})),
            1 => ("overflow", json!({"dropped": p.uint()?})),
            2 => {
                let id = p.uint()?;
                (
                    "isr_enter",
                    json!({"irq": id, "name": self.interrupts.get(&id)}),
                )
            }
            3 => ("isr_exit", json!({})),
            4 | 6 | 7 | 8 | 29 => {
                let id = p.uint()?;
                let kind = match packet.id {
                    4 => "task_start_exec",
                    6 => "task_start_ready",
                    7 => "task_stop_ready",
                    8 => "task_create",
                    _ => "task_terminate",
                };
                if packet.id == 8 {
                    self.tasks.remove(&id);
                }
                let mut data = json!({"task_id": id, "name": self.tasks.get(&id)});
                if packet.id == 7 {
                    data["cause"] = json!(p.uint()?);
                }
                (kind, data)
            }
            5 => ("task_stop_exec", json!({})),
            9 => {
                let id = p.uint()?;
                let priority = p.uint()?;
                let name = p.string()?;
                let data = json!({"task_id": id, "priority": priority, "name": name});
                self.tasks.insert(id, name);
                ("task_info", data)
            }
            10 => ("trace_start", json!({})),
            11 => ("trace_stop", json!({})),
            12 => ("systime_cycles", json!({"cycles": p.uint()?})),
            13 => {
                let low = u64::from(p.uint()?);
                let high = u64::from(p.uint()?);
                ("systime_us", json!({"microseconds": (high << 32) | low}))
            }
            14 => {
                let text = p.string()?;
                for info in text.split(',') {
                    let Some((key, value)) = info.split_once('=') else {
                        continue;
                    };
                    let key = key.trim();
                    let value = value.trim();
                    if let Some(irq) = key.strip_prefix("I#").and_then(|n| n.parse::<u32>().ok()) {
                        self.interrupts.insert(irq, value.to_owned());
                    } else {
                        self.system.insert(key.to_owned(), value.to_owned());
                    }
                }
                ("system_description", json!({"text": text}))
            }
            15 | 16 => {
                let id = p.uint()?;
                let kind = if packet.id == 15 {
                    "mark_start"
                } else {
                    "mark_stop"
                };
                (
                    kind,
                    json!({"marker_id": id, "name": self.markers.get(&id)}),
                )
            }
            17 => ("idle", json!({})),
            18 => ("isr_to_scheduler", json!({})),
            19 => {
                let id = p.uint()?;
                (
                    "timer_enter",
                    json!({"timer_id": id, "name": self.resources.get(&id)}),
                )
            }
            20 => ("timer_exit", json!({})),
            21 => (
                "stack_info",
                json!({
                    "task_id": p.uint()?, "base": p.uint()?, "size": p.uint()?, "used": p.uint()?
                }),
            ),
            22 => {
                let module_id = p.uint()?;
                let event_offset = p.uint()?;
                let text = p.string()?;
                let mut name = None;
                let mut version = None;
                for info in text.split(',') {
                    if let Some(value) = info.strip_prefix("M=") {
                        name = Some(value.to_owned());
                    } else if let Some(value) = info.strip_prefix("V=") {
                        version = Some(value.to_owned());
                    }
                }
                if name.is_none() && !text.contains('=') {
                    name = Some(text.clone());
                }
                if let Some(name) = &name {
                    self.modules
                        .insert(event_offset, (name.clone(), version.clone()));
                }
                (
                    "module_description",
                    json!({
                        "module_id": module_id, "event_offset": event_offset,
                        "name": name, "version": version, "text": text
                    }),
                )
            }
            23 => {
                let id = p.uint()?;
                let raw = p.uint()?;
                let mut data = json!({"data_id": id, "raw": raw});
                if let Some((name, value_type)) = self.data.get(&id) {
                    data["name"] = json!(name);
                    data["value"] = match value_type {
                        0 => json!(raw),
                        1 => json!(raw as i32),
                        2 => json!(f32::from_bits(raw)),
                        _ => Value::Null,
                    };
                }
                ("data_sample", data)
            }
            24 => {
                let hz = p.uint()?;
                let cpu_hz = p.uint()?;
                let base = p.uint()?;
                let shift = p.uint()?;
                self.timestamp_hz = Some(hz).filter(|&hz| hz != 0);
                self.cpu_hz = Some(cpu_hz);
                (
                    "init",
                    json!({"timestamp_hz": hz, "cpu_hz": cpu_hz, "ram_base": base, "id_shift": shift}),
                )
            }
            25 => {
                let id = p.uint()?;
                let name = p.string()?;
                let data = json!({"resource_id": id, "name": name});
                self.resources.insert(id, name);
                ("name_resource", data)
            }
            26 => {
                let text = p.string()?;
                let options = p.uint()?;
                let count = p.uint()?;
                if count as usize > p.remaining().len() {
                    return Err("truncated print arguments");
                }
                let args = (0..count)
                    .map(|_| p.uint())
                    .collect::<Result<Vec<_>, _>>()?;
                (
                    "print",
                    json!({"text": text, "options": options, "args": args}),
                )
            }
            27 => ("num_modules", json!({"count": p.uint()?})),
            28 => {
                let id = p.uint()?;
                let returning = if p.remaining().is_empty() {
                    None
                } else {
                    Some(p.uint()?)
                };
                let mut data = json!({"call_id": id, "return_raw": returning});
                self.describe_call(descriptions, id, &mut data);
                ("api_return", data)
            }
            31 => self.extended(&mut p)?,
            id if id >= 32 => {
                p.pos = packet.payload.len();
                let mut data = json!({"payload_hex": hex(packet.payload)});
                self.describe_call(descriptions, id, &mut data);
                ("api_call", data)
            }
            _ => {
                p.pos = packet.payload.len();
                ("unknown", json!({"payload_hex": hex(packet.payload)}))
            }
        };
        let mut data = data;
        if !p.remaining().is_empty() {
            data["extra_hex"] = json!(hex(p.remaining()));
        }
        Ok(Event { kind, data })
    }

    fn extended(&mut self, p: &mut Cursor<'_>) -> Result<(&'static str, Value), &'static str> {
        let id = p.uint()?;
        Ok(match id {
            0 => {
                let marker = p.uint()?;
                (
                    "mark",
                    json!({"marker_id": marker, "name": self.markers.get(&marker)}),
                )
            }
            1 => {
                let id = p.uint()?;
                let name = p.string()?;
                let data = json!({"marker_id": id, "name": name});
                self.markers.insert(id, name);
                ("name_marker", data)
            }
            2 => (
                "heap_define",
                json!({
                    "heap_id": p.uint()?, "base_id": p.uint()?, "size_units": p.uint()?,
                    "metadata_bytes": p.uint()?
                }),
            ),
            3 | 4 => {
                let mut data = json!({
                    "heap_id": p.uint()?, "block_id": p.uint()?, "size_units": p.uint()?
                });
                if id == 4 {
                    data["tag"] = json!(p.uint()?);
                }
                ("heap_alloc", data)
            }
            5 => (
                "heap_free",
                json!({"heap_id": p.uint()?, "block_id": p.uint()?}),
            ),
            6 => {
                let id = p.uint()?;
                let name = p.string()?;
                let value_type = if p.remaining().is_empty() {
                    0
                } else {
                    p.uint()?
                };
                let mut data = json!({"data_id": id, "name": name, "value_type": value_type});
                for field in ["offset", "range_min", "range_max"] {
                    if p.remaining().is_empty() {
                        break;
                    }
                    data[field] = json!(p.uint()? as i32);
                }
                if !p.remaining().is_empty() {
                    data["scale"] = json!(f32::from_bits(p.uint()?));
                }
                if !p.remaining().is_empty() {
                    data["unit"] = json!(p.string()?);
                }
                self.data.insert(id, (name, value_type));
                ("register_data", data)
            }
            7 => (
                "print_elf",
                json!({"address": p.uint()?, "options": p.uint()?}),
            ),
            _ => ("extended", json!({"extended_id": id})),
        })
    }

    fn describe_call(&self, descriptions: &Descriptions, id: u32, data: &mut Value) {
        let definition: Option<&Definition> =
            if let Some((&offset, (module, version))) = self.modules.range(..=id).next_back() {
                data["module"] = json!(module);
                data["module_event_id"] = json!(id - offset);
                descriptions.lookup(module, version.as_deref(), id - offset)
            } else {
                self.system
                    .get("O")
                    .and_then(|os| descriptions.lookup(os, None, id))
            };
        if let Some(definition) = definition {
            data["symbol"] = json!(definition.symbol);
            if !definition.signature.is_empty() {
                data["signature"] = json!(definition.signature);
            }
        }
    }
}
