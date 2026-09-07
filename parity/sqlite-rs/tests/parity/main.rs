// Copyright 2026 Schuberg Philis
// SPDX-License-Identifier: Apache-2.0
//! Parity harness entry point. Run via `make test-parity`
//! (`cargo test --test parity`) — the third leg of the testing triad
//! alongside tier contracts (#69) and the fixture corpus (#72's Refs:
//! `.openspec/specs/001-architecture/spec.md` Req 3,
//! `.openspec/specs/004-corpus/spec.md` Req 4).
//!
//! Where `tests/corpus` diffs against committed fixtures and a pinned
//! oracle at the library level, this suite runs the SAME statement
//! against both engines side by side, one integration target per value
//! block (`v01.rs` … `v12.rs`), comparing five dimensions per case (see
//! `driver.rs`). See issue #72.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::panic,
    clippy::arithmetic_side_effects
)]

// `oracle`/`harness` were shared with sqlite-rs's tests/corpus via
// `#[path]`; here they are local copies pointed at the sibling checkout's
// fixtures (see oracle::sqlite_rs_repo).
#[allow(dead_code)]
mod harness;
#[allow(dead_code)]
mod oracle;

// `ParityCase`/`run_case` are exercised by v02 onward, now that a query
// engine exists to drive them through; `#[allow(dead_code)]` covers
// `unix_vfs_open_ok`, still unused pending a v-block that needs it.
#[allow(dead_code)]
mod driver;

mod v01;
mod v02;
mod v03;
mod v04;
mod v05;
mod v06;
mod v07;
mod v08;
mod v09;
mod v10;
mod v11;
mod v12;
