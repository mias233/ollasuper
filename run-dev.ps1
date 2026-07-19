# Dev backend launcher. Run from copyai_remote/.
$env:PATH = "C:\Users\test\.cargo\bin;C:\Program Files\nodejs;" + $env:PATH
$env:LOCO_ENV = "development"
$env:DATABASE_URL = "sqlite://qwriter_dev.sqlite?mode=rwc"
$env:JWT_SECRET = "dev-only-do-not-use-in-prod-change-me"
$env:RUST_LOG = "info,copyai=debug"
cargo run --bin copyai-cli start
