//! Read-only, obfuscated media pack (`Data/media.pak`).
//!
//! Version 2 adds per-entry zstd compression; the reader also accepts version 1
//! packs, which stored every body uncompressed. A plaintext 32-byte header points
//! at an obfuscated index at the end of the file, while every stored body starts
//! at a 16-byte-aligned absolute offset. A fixed 32-byte seed drives a splitmix64
//! XOR stream selected by the byte's absolute offset. That lets the reader
//! decrypt any range without loading the whole pack and avoids the repeating-XOR
//! pattern of a whole-file stream.
//!
//! Only media directories belong in this pack. Databases, maps, saves and mod
//! overlays stay as plain files on disk; [`crate::media_pack`] does not impose
//! that policy itself, the packer's manifest and include filters do.

use std::collections::{HashMap, HashSet};
use std::fmt;
use std::fs::{File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use crate::dxarchive::crc32_for_pack as crc32;

/// Current file magic. The trailing digit is also the format's major version.
pub const MAGIC: [u8; 8] = *b"WOLFMPK2";

/// Version-1 file magic, still accepted by the reader.
pub const MAGIC_V1: [u8; 8] = *b"WOLFMPK1";

/// On-disk format version.
pub const VERSION: u16 = 2;

/// Plaintext header size.
pub const HEADER_SIZE: u64 = 32;

/// Every file body starts at a multiple of this many bytes.
pub const DATA_ALIGNMENT: u64 = 16;

/// Extensions probed when a requested name has none.
pub const PROBE_EXTENSIONS: [&str; 5] = ["png", "jpg", "bmp", "jpeg", "webp"];

/// Fixed 32-byte seed for the deterministic XOR stream.
///
/// This is obfuscation for a read-only media package, not authentication or
/// encryption at rest.
const SEED: [u8; 32] = [
    0x9F, 0x2E, 0x4B, 0xD7, 0x18, 0x63, 0xA5, 0x0C, 0xE4, 0x71, 0x35, 0x8A, 0xC2, 0x5D, 0x90, 0x26,
    0x6B, 0xF3, 0x04, 0xBE, 0x57, 0xA1, 0xD8, 0x39, 0x82, 0x4C, 0xEF, 0x16, 0x75, 0xB0, 0x2D, 0x9A,
];

const STREAM_BLOCK: u64 = 64;
const GOLDEN: u64 = 0x9E37_79B9_7F4A_7C15;
const INDEX_FIXED_V1: usize = 2 + 8 + 8 + 4;
/// v2: path length, offset, stored size, raw size, CRC, codec, reserved.
const INDEX_FIXED: usize = 2 + 8 + 8 + 8 + 4 + 1 + 1;

/// Below this size zstd's frame overhead usually outweighs the saving.
pub const ZSTD_MIN_BYTES: usize = 128;

/// Default zstd level for release media packs.
pub const DEFAULT_ZSTD_LEVEL: i32 = 9;

/// v2 body encoding.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
enum BodyCodec {
    Store = 0,
    Zstd = 1,
}

impl BodyCodec {
    fn from_u8(value: u8) -> Result<Self, MediaPackError> {
        match value {
            0 => Ok(Self::Store),
            1 => Ok(Self::Zstd),
            other => Err(corrupt(format!("unsupported body codec {other}"))),
        }
    }
}

/// How [`MediaPackWriter`] stores entry bodies.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CompressionPolicy {
    /// Store every body verbatim.
    Store,
    /// Compress each body with zstd when that makes the stored body smaller.
    Auto,
}

/// Why a media pack could not be opened, read or written.
#[derive(Debug)]
pub enum MediaPackError {
    /// An open, seek, read or write failed.
    Io {
        /// Path the operation targeted.
        path: PathBuf,
        /// Operating-system error.
        source: std::io::Error,
    },
    /// The pack header or index is malformed.
    Corrupt {
        /// Human-readable description.
        detail: String,
    },
    /// A relative path violates the pack's path rules.
    InvalidPath {
        /// Offending path.
        path: String,
        /// Why it was rejected.
        reason: &'static str,
    },
    /// The same path was supplied twice, including with different case.
    DuplicatePath {
        /// The duplicate path.
        path: String,
    },
    /// A source file is missing or is not a regular file.
    Source {
        /// Requested source path.
        path: PathBuf,
        /// Why it was rejected.
        detail: String,
    },
    /// A body's CRC-32 did not match the index.
    CrcMismatch {
        /// Path named by the index.
        path: String,
        /// CRC stored in the index.
        expected: u32,
        /// CRC computed from the decrypted bytes.
        actual: u32,
    },
    /// The internal file lock was poisoned by a panicking reader.
    LockPoisoned,
}

impl fmt::Display for MediaPackError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io { path, source } => write!(f, "cannot access {}: {source}", path.display()),
            Self::Corrupt { detail } => write!(f, "corrupt media pack: {detail}"),
            Self::InvalidPath { path, reason } => {
                write!(f, "invalid media pack path {path:?}: {reason}")
            }
            Self::DuplicatePath { path } => {
                write!(f, "duplicate media pack path (case-insensitive): {path}")
            }
            Self::Source { path, detail } => {
                write!(f, "cannot pack {}: {detail}", path.display())
            }
            Self::CrcMismatch {
                path,
                expected,
                actual,
            } => write!(
                f,
                "media pack CRC mismatch for {path}: expected {expected:08X}, got {actual:08X}"
            ),
            Self::LockPoisoned => write!(f, "media pack file lock is poisoned"),
        }
    }
}

impl std::error::Error for MediaPackError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io { source, .. } => Some(source),
            _ => None,
        }
    }
}

fn corrupt(detail: impl Into<String>) -> MediaPackError {
    MediaPackError::Corrupt {
        detail: detail.into(),
    }
}

fn io_error(path: &Path, source: std::io::Error) -> MediaPackError {
    MediaPackError::Io {
        path: path.to_path_buf(),
        source,
    }
}

/// The canonical path rules shared by the writer and the reader.
///
/// Paths are UTF-8, use `/`, are relative, and contain no empty segment, `.`,
/// `..`, backslash, NUL or colon. The colon rule also rejects Windows drive
/// letters and alternate data streams.
pub fn validate_path(path: &str) -> Result<(), MediaPackError> {
    if path.is_empty() {
        return Err(MediaPackError::InvalidPath {
            path: path.to_owned(),
            reason: "empty path",
        });
    }
    if path.len() > usize::from(u16::MAX) {
        return Err(MediaPackError::InvalidPath {
            path: path.to_owned(),
            reason: "path is longer than 65535 bytes",
        });
    }
    if path.contains('\0') {
        return Err(MediaPackError::InvalidPath {
            path: path.to_owned(),
            reason: "NUL is not allowed",
        });
    }
    if path.contains('\\') {
        return Err(MediaPackError::InvalidPath {
            path: path.to_owned(),
            reason: "backslashes are not allowed; use /",
        });
    }
    if path.contains(':') {
        return Err(MediaPackError::InvalidPath {
            path: path.to_owned(),
            reason: "colon is not allowed in a relative media path",
        });
    }
    if path.starts_with('/') {
        return Err(MediaPackError::InvalidPath {
            path: path.to_owned(),
            reason: "absolute paths are not allowed",
        });
    }
    for segment in path.split('/') {
        if segment.is_empty() {
            return Err(MediaPackError::InvalidPath {
                path: path.to_owned(),
                reason: "empty path segment",
            });
        }
        if segment == "." || segment == ".." {
            return Err(MediaPackError::InvalidPath {
                path: path.to_owned(),
                reason: "dot and dot-dot segments are not allowed",
            });
        }
    }
    Ok(())
}

fn lower_path(path: &str) -> String {
    path.to_lowercase()
}

fn align_up(value: u64, alignment: u64) -> Result<u64, MediaPackError> {
    let mask = alignment - 1;
    value
        .checked_add(mask)
        .map(|rounded| rounded & !mask)
        .ok_or_else(|| corrupt("media pack offset overflow"))
}

fn is_aligned(value: u64, alignment: u64) -> bool {
    value & (alignment - 1) == 0
}

fn has_extension(path: &str) -> bool {
    Path::new(path).extension().is_some()
}

/// Lenient lookup-name normalisation: the pack itself is strict, but callers
/// may pass surrounding whitespace (the game's asset layer already trims it).
fn lookup_name(name: &str) -> Option<String> {
    let name = name.trim();
    validate_path(name).ok()?;
    Some(name.to_owned())
}

/// One file recorded in the pack index.
#[derive(Debug, Clone)]
struct Entry {
    path: String,
    offset: u64,
    /// Bytes occupied by the stored (possibly compressed) body.
    size: u64,
    /// Bytes after decoding, used for allocation and validation.
    raw_size: u64,
    crc: u32,
    codec: BodyCodec,
}

#[derive(Debug, Clone, Copy)]
struct Header {
    version: u16,
    count: u32,
    index_offset: u64,
    index_size: u64,
}

impl Header {
    fn encode(self) -> [u8; HEADER_SIZE as usize] {
        let mut bytes = [0u8; HEADER_SIZE as usize];
        bytes[0..8].copy_from_slice(&MAGIC);
        bytes[8..10].copy_from_slice(&VERSION.to_le_bytes());
        bytes[10..12].copy_from_slice(&0u16.to_le_bytes());
        bytes[12..16].copy_from_slice(&self.count.to_le_bytes());
        bytes[16..24].copy_from_slice(&self.index_offset.to_le_bytes());
        bytes[24..32].copy_from_slice(&self.index_size.to_le_bytes());
        bytes
    }

    fn decode(bytes: &[u8; HEADER_SIZE as usize], file_len: u64) -> Result<Self, MediaPackError> {
        let version = u16::from_le_bytes([bytes[8], bytes[9]]);
        let magic: [u8; 8] = bytes[0..8].try_into().expect("header slice is eight bytes");
        match (version, magic) {
            (1, MAGIC_V1) | (2, MAGIC) => {}
            (1 | 2, _) => return Err(corrupt("bad magic for the declared version")),
            _ => {
                return Err(corrupt(format!(
                    "unsupported version {version}, only versions 1 and {VERSION} are readable"
                )))
            }
        }
        let flags = u16::from_le_bytes([bytes[10], bytes[11]]);
        if flags != 0 {
            return Err(corrupt(format!("unsupported header flags 0x{flags:04X}")));
        }
        let count = u32::from_le_bytes([bytes[12], bytes[13], bytes[14], bytes[15]]);
        let index_offset = u64::from_le_bytes([
            bytes[16], bytes[17], bytes[18], bytes[19], bytes[20], bytes[21], bytes[22], bytes[23],
        ]);
        let index_size = u64::from_le_bytes([
            bytes[24], bytes[25], bytes[26], bytes[27], bytes[28], bytes[29], bytes[30], bytes[31],
        ]);
        if index_offset < HEADER_SIZE {
            return Err(corrupt(format!(
                "index offset {index_offset} is before the header"
            )));
        }
        if !is_aligned(index_offset, DATA_ALIGNMENT) {
            return Err(corrupt(format!(
                "index offset {index_offset} is not {DATA_ALIGNMENT}-byte aligned"
            )));
        }
        let end = index_offset
            .checked_add(index_size)
            .ok_or_else(|| corrupt("index range overflow"))?;
        if end != file_len {
            return Err(corrupt(format!(
                "index ends at {end}, but the pack is {file_len} bytes"
            )));
        }
        Ok(Self {
            version,
            count,
            index_offset,
            index_size,
        })
    }
}

/// Random-access byte source used by [`MediaPack`].
///
/// The default implementation is a local [`File`]. Hosts whose data lives
/// inside a package (for example Godot's `res://` on Android) provide their own
/// implementation so the pack can be read without copying it to writable
/// storage first.
pub trait PackSource {
    /// Total number of bytes in the source.
    ///
    /// # Errors
    ///
    /// Propagates the host's metadata/read error.
    fn len(&mut self) -> std::io::Result<u64>;

    /// Fills `buf` with bytes starting at absolute `offset`.
    ///
    /// # Errors
    ///
    /// Returns `UnexpectedEof` when the range is shorter than `buf`, or the
    /// host's seek/read error.
    fn read_exact_at(&mut self, offset: u64, buf: &mut [u8]) -> std::io::Result<()>;
}

impl PackSource for File {
    fn len(&mut self) -> std::io::Result<u64> {
        self.metadata().map(|metadata| metadata.len())
    }

    fn read_exact_at(&mut self, offset: u64, buf: &mut [u8]) -> std::io::Result<()> {
        self.seek(SeekFrom::Start(offset))?;
        self.read_exact(buf)
    }
}

/// A random-access reader for one `media.pak`.
///
/// Opening reads only the header and the index. `read` locks the file, seeks to
/// one entry, reads exactly that entry and verifies its CRC after decryption.
pub struct MediaPack {
    path: PathBuf,
    source: Mutex<Box<dyn PackSource>>,
    entries: Vec<Entry>,
    by_lower_path: HashMap<String, usize>,
}

impl fmt::Debug for MediaPack {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("MediaPack")
            .field("path", &self.path)
            .field("entries", &self.entries.len())
            .finish_non_exhaustive()
    }
}

impl MediaPack {
    /// Opens a pack and loads its index.
    ///
    /// # Errors
    ///
    /// `Io` when the file cannot be opened or read, `Corrupt` when the header,
    /// index or a path is invalid.
    pub fn open(path: impl AsRef<Path>) -> Result<Self, MediaPackError> {
        let path = path.as_ref().to_path_buf();
        let file = File::open(&path).map_err(|source| io_error(&path, source))?;
        Self::open_source(path, Box::new(file))
    }

    /// Opens a pack from a caller-provided random-access source.
    ///
    /// `label` is used only in diagnostics and error messages. This is the
    /// entry point for package-internal media such as Godot's Android
    /// `res://android_data/media.pak.blob`.
    ///
    /// # Errors
    ///
    /// `Io` when the source cannot be read, `Corrupt` when the header, index
    /// or a path is invalid.
    pub fn open_source(
        label: impl Into<PathBuf>,
        source: Box<dyn PackSource>,
    ) -> Result<Self, MediaPackError> {
        let path = label.into();
        let mut source = source;
        let file_len = source.len().map_err(|source| io_error(&path, source))?;
        if file_len < HEADER_SIZE {
            return Err(corrupt(format!(
                "file is {file_len} bytes, shorter than the {HEADER_SIZE}-byte header"
            )));
        }
        let mut header_bytes = [0u8; HEADER_SIZE as usize];
        source
            .read_exact_at(0, &mut header_bytes)
            .map_err(|source| io_error(&path, source))?;
        let header = Header::decode(&header_bytes, file_len)?;
        let count = usize::try_from(header.count)
            .map_err(|_| corrupt("entry count does not fit this platform"))?;
        let index_size = usize::try_from(header.index_size)
            .map_err(|_| corrupt("index size does not fit this platform"))?;
        let fixed_size = if header.version == 1 {
            INDEX_FIXED_V1
        } else {
            INDEX_FIXED
        };
        if count > index_size / fixed_size {
            return Err(corrupt(format!(
                "entry count {count} cannot fit in a {}-byte index",
                header.index_size
            )));
        }
        let mut index = vec![0u8; index_size];
        source
            .read_exact_at(header.index_offset, &mut index)
            .map_err(|source| io_error(&path, source))?;
        xor_bytes(&mut index, header.index_offset);
        let entries = parse_index(&index, count, header.index_offset, header.version)?;
        let mut by_lower_path = HashMap::with_capacity(entries.len());
        for (index, entry) in entries.iter().enumerate() {
            by_lower_path.insert(lower_path(&entry.path), index);
        }
        Ok(Self {
            path,
            source: Mutex::new(source),
            entries,
            by_lower_path,
        })
    }

    /// Number of indexed files.
    #[must_use]
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// True when the pack contains no files.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Canonical paths in index order.
    pub fn paths(&self) -> impl Iterator<Item = &str> {
        self.entries.iter().map(|entry| entry.path.as_str())
    }

    /// Reads one file by UTF-8 path.
    ///
    /// Lookup is case-insensitive. When `name` has no extension, the five
    /// media extensions are probed in [`PROBE_EXTENSIONS`] order. A missing
    /// file is `Ok(None)`, while an existing body with a bad CRC is an error.
    ///
    /// # Errors
    ///
    /// `Io` for a failed seek/read, `CrcMismatch` for damaged contents, and
    /// `LockPoisoned` if a previous reader panicked while holding the file.
    pub fn read(&self, name: &str) -> Result<Option<Vec<u8>>, MediaPackError> {
        let Some(name) = lookup_name(name) else {
            return Ok(None);
        };
        let Some(index) = self.find(&name) else {
            return Ok(None);
        };
        self.read_entry(index)
    }

    fn find(&self, name: &str) -> Option<usize> {
        let lower = lower_path(name);
        if let Some(&index) = self.by_lower_path.get(&lower) {
            return Some(index);
        }
        if !has_extension(name) {
            for extension in PROBE_EXTENSIONS {
                let probe = format!("{lower}.{extension}");
                if let Some(&index) = self.by_lower_path.get(&probe) {
                    return Some(index);
                }
            }
        }
        None
    }

    fn read_entry(&self, index: usize) -> Result<Option<Vec<u8>>, MediaPackError> {
        let entry = &self.entries[index];
        let size = usize::try_from(entry.size)
            .map_err(|_| corrupt(format!("{} is too large for this platform", entry.path)))?;
        let mut bytes = vec![0u8; size];
        let mut source = self
            .source
            .lock()
            .map_err(|_| MediaPackError::LockPoisoned)?;
        source
            .read_exact_at(entry.offset, &mut bytes)
            .map_err(|source| io_error(&self.path, source))?;
        drop(source);
        xor_bytes(&mut bytes, entry.offset);
        if entry.codec == BodyCodec::Zstd {
            let capacity = usize::try_from(entry.raw_size)
                .map_err(|_| corrupt(format!("{} is too large for this platform", entry.path)))?;
            bytes = rusty_zstd::decompress(&bytes).map_err(|error| {
                corrupt(format!("{} has an invalid zstd body: {error}", entry.path))
            })?;
            if bytes.len() != capacity {
                return Err(corrupt(format!(
                    "{} decoded to {} bytes, expected {capacity}",
                    entry.path,
                    bytes.len()
                )));
            }
        } else if entry.size != entry.raw_size {
            return Err(corrupt(format!(
                "{} stores {} bytes but declares a {} byte body",
                entry.path, entry.size, entry.raw_size
            )));
        }
        let actual = crc32(&bytes);
        if actual != entry.crc {
            return Err(MediaPackError::CrcMismatch {
                path: entry.path.clone(),
                expected: entry.crc,
                actual,
            });
        }
        Ok(Some(bytes))
    }
}

fn parse_index(
    index: &[u8],
    count: usize,
    index_offset: u64,
    version: u16,
) -> Result<Vec<Entry>, MediaPackError> {
    let mut entries = Vec::with_capacity(count);
    let mut seen = HashSet::with_capacity(count);
    let mut cursor = 0usize;
    let fixed_size = if version == 1 {
        INDEX_FIXED_V1
    } else {
        INDEX_FIXED
    };
    for number in 0..count {
        if index.len().saturating_sub(cursor) < fixed_size {
            return Err(corrupt(format!(
                "entry {number} is truncated at index byte {cursor}"
            )));
        }
        let path_len = usize::from(u16::from_le_bytes([index[cursor], index[cursor + 1]]));
        cursor += 2;
        let offset = read_u64(index, cursor)?;
        cursor += 8;
        let size = read_u64(index, cursor)?;
        cursor += 8;
        let (raw_size, crc, codec) = if version == 1 {
            let crc = read_u32(index, cursor)?;
            cursor += 4;
            (size, crc, BodyCodec::Store)
        } else {
            let raw_size = read_u64(index, cursor)?;
            cursor += 8;
            let crc = read_u32(index, cursor)?;
            cursor += 4;
            let codec = BodyCodec::from_u8(index[cursor])?;
            cursor += 1;
            let flags = index[cursor];
            cursor += 1;
            if flags != 0 {
                return Err(corrupt(format!(
                    "entry {number} uses unsupported index flags 0x{flags:02X}"
                )));
            }
            (raw_size, crc, codec)
        };
        let end = cursor
            .checked_add(path_len)
            .ok_or_else(|| corrupt("index path range overflow"))?;
        if end > index.len() {
            return Err(corrupt(format!(
                "entry {number} path is truncated at index byte {cursor}"
            )));
        }
        let path = std::str::from_utf8(&index[cursor..end])
            .map_err(|_| corrupt(format!("entry {number} path is not UTF-8")))?
            .to_owned();
        cursor = end;
        validate_path(&path)?;
        if version == 1 && codec != BodyCodec::Store {
            return Err(corrupt(format!("{path} declares compression in a v1 pack")));
        }
        if codec == BodyCodec::Store && raw_size < size {
            return Err(corrupt(format!(
                "{path} stores {size} bytes but declares a {raw_size} byte body"
            )));
        }
        if codec == BodyCodec::Zstd && raw_size < ZSTD_MIN_BYTES as u64 {
            return Err(corrupt(format!(
                "{path} declares an implausibly small zstd body"
            )));
        }
        if !seen.insert(lower_path(&path)) {
            return Err(MediaPackError::DuplicatePath { path });
        }
        if offset < HEADER_SIZE {
            return Err(corrupt(format!(
                "{path} starts at {offset}, inside the header"
            )));
        }
        if !is_aligned(offset, DATA_ALIGNMENT) {
            return Err(corrupt(format!(
                "{path} starts at unaligned offset {offset}"
            )));
        }
        let body_end = offset
            .checked_add(size)
            .ok_or_else(|| corrupt(format!("{path} body range overflows")))?;
        if body_end > index_offset {
            return Err(corrupt(format!(
                "{path} body ends at {body_end}, past the index at {index_offset}"
            )));
        }
        entries.push(Entry {
            path,
            offset,
            size,
            raw_size,
            crc,
            codec,
        });
    }
    if cursor != index.len() {
        return Err(corrupt(format!(
            "index has {} trailing byte(s)",
            index.len() - cursor
        )));
    }
    Ok(entries)
}

fn read_u32(bytes: &[u8], offset: usize) -> Result<u32, MediaPackError> {
    let slice = bytes
        .get(offset..offset + 4)
        .ok_or_else(|| corrupt("truncated u32 in index"))?;
    Ok(u32::from_le_bytes([slice[0], slice[1], slice[2], slice[3]]))
}

fn read_u64(bytes: &[u8], offset: usize) -> Result<u64, MediaPackError> {
    let slice = bytes
        .get(offset..offset + 8)
        .ok_or_else(|| corrupt("truncated u64 in index"))?;
    Ok(u64::from_le_bytes([
        slice[0], slice[1], slice[2], slice[3], slice[4], slice[5], slice[6], slice[7],
    ]))
}

/// Summary returned by [`MediaPackWriter::write`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PackStats {
    /// Number of files written.
    pub files: usize,
    /// Number of bodies stored with zstd.
    pub compressed_files: usize,
    /// Sum of the source file sizes.
    pub bytes: u64,
    /// Size of the finished pack, including header, padding and index.
    pub output_bytes: u64,
}

/// Builds a pack from source files.
///
/// Additions are sorted by canonical path at write time, so adding the same
/// files in a different order produces byte-identical output.
#[derive(Debug, Clone)]
pub struct MediaPackWriter {
    files: Vec<SourceFile>,
    compression: CompressionPolicy,
    zstd_level: i32,
}

#[derive(Debug, Clone)]
struct SourceFile {
    path: String,
    source: PathBuf,
}

impl MediaPackWriter {
    /// An empty builder.
    #[must_use]
    pub fn new() -> Self {
        Self {
            files: Vec::new(),
            compression: CompressionPolicy::Auto,
            zstd_level: DEFAULT_ZSTD_LEVEL,
        }
    }

    /// Selects whether bodies may be zstd-compressed.
    pub fn set_compression(&mut self, compression: CompressionPolicy) {
        self.compression = compression;
    }

    /// Sets the zstd compression level used by [`CompressionPolicy::Auto`].
    pub fn set_zstd_level(&mut self, level: i32) {
        self.zstd_level = level;
    }

    /// Adds one file under its pack-relative canonical path.
    ///
    /// Duplicate paths are rejected case-insensitively. The source must exist
    /// when the pack is written; checking here also catches most typos early.
    ///
    /// # Errors
    ///
    /// `InvalidPath`, `DuplicatePath`, or `Source` when the file is absent.
    pub fn add_file(
        &mut self,
        path: impl Into<String>,
        source: impl Into<PathBuf>,
    ) -> Result<(), MediaPackError> {
        let path = path.into();
        validate_path(&path)?;
        let lower = lower_path(&path);
        if self
            .files
            .iter()
            .any(|existing| lower_path(&existing.path) == lower)
        {
            return Err(MediaPackError::DuplicatePath { path });
        }
        let source = source.into();
        check_source(&source)?;
        self.files.push(SourceFile { path, source });
        Ok(())
    }

    /// Number of files added.
    #[must_use]
    pub fn len(&self) -> usize {
        self.files.len()
    }

    /// True when no files were added.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.files.is_empty()
    }

    /// Writes the whole pack.
    ///
    /// # Errors
    ///
    /// `Source` when a source disappeared or is not a regular file, and `Io`
    /// when the destination cannot be created or written.
    pub fn write(&self, output: impl AsRef<Path>) -> Result<PackStats, MediaPackError> {
        let output = output.as_ref();
        let mut files = self.files.clone();
        files.sort_by(|left, right| left.path.cmp(&right.path));
        let mut out = OpenOptions::new()
            .create(true)
            .truncate(true)
            .read(true)
            .write(true)
            .open(output)
            .map_err(|source| io_error(output, source))?;
        out.write_all(&[0u8; HEADER_SIZE as usize])
            .map_err(|source| io_error(output, source))?;

        let mut entries = Vec::with_capacity(files.len());
        let mut offset = HEADER_SIZE;
        let mut source_bytes = 0u64;
        let mut compressed_files = 0usize;
        for file in &files {
            check_source(&file.source)?;
            let bytes =
                std::fs::read(&file.source).map_err(|source| io_error(&file.source, source))?;
            let raw_size = u64::try_from(bytes.len())
                .map_err(|_| corrupt(format!("{} is too large", file.path)))?;
            source_bytes = source_bytes
                .checked_add(raw_size)
                .ok_or_else(|| corrupt("total source size overflow"))?;
            let crc = crc32(&bytes);
            let (codec, mut stored) = match self.compression {
                CompressionPolicy::Store => (BodyCodec::Store, bytes),
                CompressionPolicy::Auto if bytes.len() >= ZSTD_MIN_BYTES => {
                    let compressed =
                        rusty_zstd::compress(&bytes, self.zstd_level).map_err(|error| {
                            MediaPackError::Source {
                                path: file.source.clone(),
                                detail: format!("zstd compression failed: {error}"),
                            }
                        })?;
                    if compressed.len() < bytes.len() {
                        compressed_files += 1;
                        (BodyCodec::Zstd, compressed)
                    } else {
                        (BodyCodec::Store, bytes)
                    }
                }
                CompressionPolicy::Auto => (BodyCodec::Store, bytes),
            };
            let size = u64::try_from(stored.len())
                .map_err(|_| corrupt(format!("{} is too large", file.path)))?;
            out.seek(SeekFrom::Start(offset))
                .map_err(|source| io_error(output, source))?;
            xor_bytes(&mut stored, offset);
            out.write_all(&stored)
                .map_err(|source| io_error(output, source))?;
            entries.push(Entry {
                path: file.path.clone(),
                offset,
                size,
                raw_size,
                crc,
                codec,
            });
            let body_end = offset
                .checked_add(size)
                .ok_or_else(|| corrupt("data offset overflow"))?;
            let next = align_up(body_end, DATA_ALIGNMENT)?;
            if next > body_end {
                let padding = usize::try_from(next - body_end)
                    .map_err(|_| corrupt("padding does not fit this platform"))?;
                out.write_all(&[0u8; DATA_ALIGNMENT as usize][..padding])
                    .map_err(|source| io_error(output, source))?;
            }
            offset = next;
        }

        let index_offset = align_up(offset, DATA_ALIGNMENT)?;
        if index_offset > offset {
            let padding = usize::try_from(index_offset - offset)
                .map_err(|_| corrupt("index padding does not fit this platform"))?;
            out.write_all(&[0u8; DATA_ALIGNMENT as usize][..padding])
                .map_err(|source| io_error(output, source))?;
        }
        let mut index = encode_index(&entries)?;
        let index_size =
            u64::try_from(index.len()).map_err(|_| corrupt("index size does not fit in u64"))?;
        xor_bytes(&mut index, index_offset);
        out.seek(SeekFrom::Start(index_offset))
            .map_err(|source| io_error(output, source))?;
        out.write_all(&index)
            .map_err(|source| io_error(output, source))?;

        let count =
            u32::try_from(entries.len()).map_err(|_| corrupt("more than 4,294,967,295 files"))?;
        let header = Header {
            version: VERSION,
            count,
            index_offset,
            index_size,
        };
        out.seek(SeekFrom::Start(0))
            .map_err(|source| io_error(output, source))?;
        out.write_all(&header.encode())
            .map_err(|source| io_error(output, source))?;
        out.flush().map_err(|source| io_error(output, source))?;
        Ok(PackStats {
            files: entries.len(),
            compressed_files,
            bytes: source_bytes,
            output_bytes: index_offset
                .checked_add(index_size)
                .ok_or_else(|| corrupt("output size overflow"))?,
        })
    }
}

fn check_source(path: &Path) -> Result<(), MediaPackError> {
    if !path.is_file() {
        return Err(MediaPackError::Source {
            path: path.to_path_buf(),
            detail: "not an existing regular file".to_owned(),
        });
    }
    Ok(())
}

fn encode_index(entries: &[Entry]) -> Result<Vec<u8>, MediaPackError> {
    let mut size = 0usize;
    for entry in entries {
        size = size
            .checked_add(INDEX_FIXED)
            .and_then(|value| value.checked_add(entry.path.len()))
            .ok_or_else(|| corrupt("index size overflow"))?;
    }
    let mut index = Vec::with_capacity(size);
    for entry in entries {
        let path = entry.path.as_bytes();
        let path_len = u16::try_from(path.len()).map_err(|_| MediaPackError::InvalidPath {
            path: entry.path.clone(),
            reason: "path is longer than 65535 bytes",
        })?;
        index.extend_from_slice(&path_len.to_le_bytes());
        index.extend_from_slice(&entry.offset.to_le_bytes());
        index.extend_from_slice(&entry.size.to_le_bytes());
        index.extend_from_slice(&entry.raw_size.to_le_bytes());
        index.extend_from_slice(&entry.crc.to_le_bytes());
        index.push(entry.codec as u8);
        index.push(0);
        index.extend_from_slice(path);
    }
    Ok(index)
}

/// XOR one byte range with the fixed offset-indexed stream.
fn xor_bytes(bytes: &mut [u8], absolute_offset: u64) {
    let mut done = 0usize;
    while done < bytes.len() {
        let absolute = absolute_offset.wrapping_add(done as u64);
        let block = absolute / STREAM_BLOCK;
        let within = usize::try_from(absolute % STREAM_BLOCK).unwrap_or(0);
        let stream = stream_block(block);
        let take = (STREAM_BLOCK as usize - within).min(bytes.len() - done);
        for index in 0..take {
            bytes[done + index] ^= stream[within + index];
        }
        done += take;
    }
}

fn stream_block(block: u64) -> [u8; STREAM_BLOCK as usize] {
    let mut state = block.wrapping_mul(GOLDEN);
    for word in SEED.chunks_exact(8) {
        let seed_word = u64::from_le_bytes([
            word[0], word[1], word[2], word[3], word[4], word[5], word[6], word[7],
        ]);
        state = state.wrapping_add(seed_word).wrapping_mul(GOLDEN);
        state ^= state >> 29;
    }
    let mut out = [0u8; STREAM_BLOCK as usize];
    for chunk in out.chunks_exact_mut(8) {
        state = state.wrapping_add(GOLDEN);
        let mut value = state;
        value = (value ^ (value >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        value = (value ^ (value >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        value ^= value >> 31;
        chunk.copy_from_slice(&value.to_le_bytes());
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn path_rules_reject_escapes_and_noncanonical_names() {
        for path in [
            "",
            "/absolute.png",
            "../escape.png",
            "Picture/../../escape.png",
            "Picture\\escape.png",
            "C:/Windows/system32/x.png",
            "Picture//x.png",
            "Picture/./x.png",
            "Picture/x.png\0",
            "Picture/",
        ] {
            assert!(
                validate_path(path).is_err(),
                "{path:?} should have been rejected"
            );
        }
        validate_path("Picture/妹 テスト.png").expect("UTF-8 relative path");
    }

    #[test]
    fn stream_is_offset_stable_and_not_a_repeating_block() {
        let original = (0u8..128).collect::<Vec<_>>();
        let mut whole = original.clone();
        xor_bytes(&mut whole, 37);
        for start in 0..whole.len() {
            let end = (start + 23).min(whole.len());
            let mut part = original[start..end].to_vec();
            xor_bytes(&mut part, 37 + start as u64);
            assert_eq!(part, whole[start..end], "range starting at {start}");
        }
        assert_ne!(whole[0..32], whole[32..64]);
    }

    #[test]
    fn zstd_entries_round_trip_and_only_compress_when_smaller() {
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("target/test-scratch/media-pack-zstd");
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).expect("scratch dir");
        let source = root.join("compressible.bin");
        std::fs::write(&source, vec![b'A'; 4096]).expect("source");
        let destination = root.join("packed.pak");

        let mut writer = MediaPackWriter::new();
        writer
            .add_file("Picture/compressible.bin", &source)
            .expect("add");
        let stats = writer.write(&destination).expect("write pack");
        assert_eq!(stats.files, 1);
        assert_eq!(stats.compressed_files, 1);
        assert!(stats.output_bytes < stats.bytes / 4);

        let reader = MediaPack::open(&destination).expect("open pack");
        assert_eq!(
            reader
                .read("Picture/compressible.bin")
                .expect("read")
                .expect("present"),
            vec![b'A'; 4096]
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn version_one_packs_remain_readable() {
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("target/test-scratch/media-pack-v1");
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).expect("scratch dir");
        let path = root.join("v1.pak");
        write_v1_fixture(&path, "Picture/legacy.bin", b"version one body");

        let reader = MediaPack::open(&path).expect("open v1 pack");
        assert_eq!(
            reader
                .read("Picture/legacy.bin")
                .expect("read")
                .expect("present"),
            b"version one body"
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn host_provided_source_reads_without_a_local_file() {
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("target/test-scratch/media-pack-host-source");
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).expect("scratch dir");
        let source = root.join("picture.bin");
        std::fs::write(&source, b"host source body").expect("source");
        let destination = root.join("packed.pak");
        let mut writer = MediaPackWriter::new();
        writer.add_file("Picture/host.bin", &source).expect("add");
        writer.write(&destination).expect("write pack");
        let bytes = std::fs::read(&destination).expect("read pack");
        let _ = std::fs::remove_dir_all(&root);

        let reader = MediaPack::open_source(
            "res://android_data/media.pak.blob",
            Box::new(CursorSource(std::io::Cursor::new(bytes))),
        )
        .expect("open host source");
        assert_eq!(
            reader
                .read("Picture/host.bin")
                .expect("read")
                .expect("present"),
            b"host source body"
        );
    }

    struct CursorSource(std::io::Cursor<Vec<u8>>);

    impl PackSource for CursorSource {
        fn len(&mut self) -> std::io::Result<u64> {
            Ok(self.0.get_ref().len() as u64)
        }

        fn read_exact_at(&mut self, offset: u64, buf: &mut [u8]) -> std::io::Result<()> {
            self.0.set_position(offset);
            self.0.read_exact(buf)
        }
    }

    fn write_v1_fixture(path: &Path, relative: &str, body: &[u8]) {
        let offset = HEADER_SIZE;
        let index_offset = align_up(offset + body.len() as u64, DATA_ALIGNMENT).expect("align");
        let mut packed = vec![0u8; index_offset as usize];
        packed[0..8].copy_from_slice(&MAGIC_V1);
        packed[8..10].copy_from_slice(&1u16.to_le_bytes());
        packed[12..16].copy_from_slice(&1u32.to_le_bytes());
        packed[16..24].copy_from_slice(&index_offset.to_le_bytes());

        let body_start = offset as usize;
        packed[body_start..body_start + body.len()].copy_from_slice(body);
        xor_bytes(&mut packed[body_start..body_start + body.len()], offset);

        let mut index = Vec::new();
        index.extend_from_slice(&(relative.len() as u16).to_le_bytes());
        index.extend_from_slice(&offset.to_le_bytes());
        index.extend_from_slice(&(body.len() as u64).to_le_bytes());
        index.extend_from_slice(&crc32(body).to_le_bytes());
        index.extend_from_slice(relative.as_bytes());
        packed[24..32].copy_from_slice(&(index.len() as u64).to_le_bytes());
        xor_bytes(&mut index, index_offset);
        packed.extend_from_slice(&index);
        std::fs::write(path, packed).expect("write v1 fixture");
    }
}
