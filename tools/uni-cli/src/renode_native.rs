use std::env;
use std::ffi::{CStr, CString, c_char, c_int, c_void};
use std::io::{self, Write};
use std::mem;
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::ptr::{self, NonNull};
use std::sync::{Mutex, PoisonError};

use crate::{Result, tool};

const RTLD_NOW: c_int = 2;
const RTLD_GLOBAL: c_int = 0x100;
const GREETING: &[u8] = b"Hello, UNI Clicker from Rust!\r\nHello, UNI Clicker from Rust!\r\n";

// The managed runtime can retain the callback for the lifetime of this process.
static UART: Mutex<Vec<u8>> = Mutex::new(Vec::new());

#[link(name = "dl")]
unsafe extern "C" {
    fn dlopen(path: *const c_char, flags: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    fn dlerror() -> *const c_char;
}

type Preload = unsafe extern "C" fn() -> c_int;
type Init = unsafe extern "C" fn(*const c_char, i32, i32) -> c_int;
type Exec = unsafe extern "C" fn(*const c_char, *mut c_char, i32, *mut c_char, i32) -> c_int;
type UartRead = extern "C" fn(*mut c_void, c_char);
type UartWrite = unsafe extern "C" fn(c_char);
type AddUart = unsafe extern "C" fn(
    UartRead,
    *mut Option<UartWrite>,
    *const c_char,
    *const c_char,
    *mut c_void,
    *const c_char,
) -> c_int;

struct Library(NonNull<c_void>);

impl Library {
    fn open(path: &Path, flags: c_int) -> Result<Self> {
        let name = CString::new(path.as_os_str().as_bytes())?;
        // The two libraries stay loaded because DNNE and the managed runtime retain function pointers.
        let handle = unsafe { dlopen(name.as_ptr(), flags | RTLD_NOW) };
        NonNull::new(handle)
            .map(Self)
            .ok_or_else(|| format!("could not load {}: {}", path.display(), loader_error()).into())
    }

    fn symbol(&self, name: &CStr) -> Result<*mut c_void> {
        let symbol = unsafe { dlsym(self.0.as_ptr(), name.as_ptr()) };
        if symbol.is_null() {
            return Err(format!(
                "missing librenode export {}: {}",
                name.to_string_lossy(),
                loader_error()
            )
            .into());
        }
        Ok(symbol)
    }
}

fn loader_error() -> String {
    let error = unsafe { dlerror() };
    if error.is_null() {
        return "no loader detail available".into();
    }
    // dlerror owns the string until the next dynamic-loader call on this thread.
    unsafe { CStr::from_ptr(error) }
        .to_string_lossy()
        .into_owned()
}

fn library_path() -> Result<PathBuf> {
    let path = if let Some(path) = env::var_os("UNI_LIBRENODE") {
        PathBuf::from(path)
    } else {
        let runner = PathBuf::from(tool("RENODE", ".cache/tools/renode/renode"));
        runner
            .canonicalize()
            .map_err(|error| format!("could not locate Renode at {}: {error}", runner.display()))?
            .with_file_name("platform-lib")
            .join("linux-x64/librenode.so")
    };
    path.canonicalize().map_err(|error| format!(
        "could not locate {}: {error}. Use a complete portable Renode installation or set UNI_LIBRENODE",
        path.display()
    ).into())
}

struct Renode {
    exec: Exec,
    add_uart: AddUart,
}

impl Renode {
    fn start(path: &Path) -> Result<Self> {
        // The portable library expects the host to provide libstdc++ symbols.
        Library::open(Path::new("libstdc++.so.6"), RTLD_GLOBAL)?;
        let library = Library::open(path, 0)?;
        // These signatures match the Renode 1.17.0 librenode.h and dnne.h exports.
        let preload = unsafe {
            mem::transmute::<*mut c_void, Preload>(library.symbol(c"try_preload_runtime")?)
        };
        let init = unsafe { mem::transmute::<*mut c_void, Init>(library.symbol(c"renode_init")?) };
        let exec = unsafe {
            mem::transmute::<*mut c_void, Exec>(library.symbol(c"renode_exec_command_ex")?)
        };
        let add_uart = unsafe {
            mem::transmute::<*mut c_void, AddUart>(library.symbol(c"renode_add_uart_analyzer")?)
        };

        let status = unsafe { preload() };
        if status != 0 {
            return Err(format!(
                "librenode could not load its .NET runtime (status {status:#010x})"
            )
            .into());
        }
        // A null script and negative ports start a headless monitor without listeners.
        let status = unsafe { init(ptr::null(), -1, -1) };
        if status != 0 {
            return Err(format!("renode_init failed with status {status}").into());
        }
        Ok(Self { exec, add_uart })
    }

    fn command(&self, command: &str) -> Result<String> {
        let input = CString::new(command)?;
        let mut output = [0u8; 4096];
        let mut errors = [0u8; 4096];
        let status = unsafe {
            (self.exec)(
                input.as_ptr(),
                output.as_mut_ptr().cast(),
                output.len() as i32,
                errors.as_mut_ptr().cast(),
                errors.len() as i32,
            )
        };
        if status != 0 {
            let detail = CStr::from_bytes_until_nul(&errors)?.to_string_lossy();
            let transcript = CStr::from_bytes_until_nul(&output)?.to_string_lossy();
            let diagnostic = if detail.trim().is_empty() {
                transcript.trim()
            } else {
                detail.trim()
            };
            return Err(
                format!("Renode command {command:?} failed ({status}): {diagnostic}").into(),
            );
        }
        Ok(CStr::from_bytes_until_nul(&output)?
            .to_string_lossy()
            .into_owned())
    }

    fn capture_uart(&self) -> Result<()> {
        let status = unsafe {
            (self.add_uart)(
                receive_uart,
                ptr::null_mut(),
                c"uni-clicker".as_ptr(),
                c"sysbus.usart6".as_ptr(),
                ptr::null_mut(),
                ptr::null(),
            )
        };
        if status != 0 {
            return Err(
                format!("could not attach librenode analyzer to USART6 (status {status})").into(),
            );
        }
        Ok(())
    }
}

extern "C" fn receive_uart(_context: *mut c_void, byte: c_char) {
    let mut uart = UART.lock().unwrap_or_else(PoisonError::into_inner);
    // Keep one extra byte so the comparison also catches an unexpected third greeting.
    if uart.len() <= GREETING.len() {
        uart.push(byte as u8);
    }
}

pub(super) fn check_rust(elf: &Path) -> Result<()> {
    if !elf.is_file() {
        return Err(format!("missing {}. Run make rust first", elf.display()).into());
    }
    // Renode initializes its own search path. Resolve the project's files before starting it.
    let platform = monitor_path(Path::new("sim/uni-clicker.repl"))?;
    let elf = monitor_path(elf)?;
    let path = library_path()?;
    println!("Embedding {}", path.display());
    let renode = Renode::start(&path)?;
    renode.command(r#"mach create "uni-clicker""#)?;

    let check = run_rust(&renode, &platform, &elf);
    let remove = renode.command(r#"mach rem "uni-clicker""#);
    check.and(remove.map(|_| ()))
}

fn monitor_path(path: &Path) -> Result<String> {
    let absolute = path.canonicalize()?;
    let name = absolute.to_str().ok_or("Renode requires a UTF-8 path")?;
    if name.contains("\"\"\"") {
        return Err(format!("Renode cannot quote path {name:?}").into());
    }
    // The Monitor's triple-quoted token preserves spaces and literal backslashes.
    Ok(format!("\"\"\"{name}\"\"\""))
}

pub(super) fn run_script(script: &Path) -> Result<()> {
    let script = monitor_path(script)?;
    let path = library_path()?;
    println!("Embedding {}", path.display());
    let renode = Renode::start(&path)?;
    let output = renode.command(&format!("include {script}"))?;
    print!("{output}");
    Ok(())
}

fn run_rust(renode: &Renode, platform: &str, elf: &str) -> Result<()> {
    renode.command(&format!("machine LoadPlatformDescription {platform}"))?;
    renode.command(&format!("sysbus LoadELF {elf}"))?;
    renode.command("cpu VectorTableOffset 0x08000000")?;
    renode.capture_uart()?;

    for (duration, expected) in [("0.6", 0x80), ("0.6", 0), ("0.5", 0x80)] {
        renode.command(&format!(r#"emulation RunFor "{duration}""#))?;
        let response = renode.command("sysbus ReadDoubleWord 0x40020c14")?;
        let output = u32::from_str_radix(
            response
                .trim()
                .strip_prefix("0x")
                .ok_or("missing GPIOD ODR value")?,
            16,
        )?;
        if output & (1 << 7) != expected {
            return Err(format!("unexpected PD7 state in GPIOD ODR {output:#010x}").into());
        }
    }

    let uart = UART.lock().unwrap_or_else(PoisonError::into_inner);
    if uart.as_slice() != GREETING {
        return Err(format!(
            "unexpected USART6 output {:?}",
            String::from_utf8_lossy(&uart)
        )
        .into());
    }
    io::stdout().write_all(&uart)?;
    println!("PD7 at 0.6, 1.2, and 1.7 virtual seconds: high, low, high");
    Ok(())
}
