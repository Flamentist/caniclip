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
}

impl From<std::io::Error> for CoreError {
    fn from(e: std::io::Error) -> Self {
        CoreError::Io { message: e.to_string() }
    }
}
