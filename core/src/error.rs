/// Every error that can cross the FFI boundary. Variants carry owned strings so
/// Swift receives a readable message without any Rust-side panics.
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum CoreError {
    #[error("invalid input: {message}")]
    InvalidInput { message: String },
    #[error("encoding failed: {message}")]
    Encoding { message: String },
    #[error("io error: {message}")]
    Io { message: String },
    #[error("encoder already finished")]
    AlreadyFinished,
    /// The GIF was fully encoded but could not be placed at the requested path;
    /// the finished file is kept at `temp_path` so nothing is lost.
    #[error("could not write output: {message}")]
    OutputUnwritable { message: String, temp_path: String },
}

impl From<std::io::Error> for CoreError {
    fn from(e: std::io::Error) -> Self {
        CoreError::Io { message: e.to_string() }
    }
}
