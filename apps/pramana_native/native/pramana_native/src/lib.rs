//! Native kernels for Pramāṇa.
//!
//! See `docs/ELIXIR.md`, exception #1. Only CPU-bound work with no viable BEAM
//! implementation belongs here. Today that is CJK word segmentation: Classical
//! Chinese has no whitespace, so `String.split/1` is always wrong, and lexical
//! search under-recalls badly without proper segmentation.
//!
//! Segmentation is needed at BOTH bake time and query time, which is why it is an
//! in-process NIF rather than a port. The separate suffix-array text-reuse job
//! (Phase 6) is deliberately NOT a NIF: its working set is multiple gigabytes and
//! does not belong inside the BEAM VM.

use jieba_rs::Jieba;
use std::sync::OnceLock;

/// Loading jieba's dictionary is expensive, so do it once per VM rather than per call.
fn jieba() -> &'static Jieba {
    static JIEBA: OnceLock<Jieba> = OnceLock::new();
    JIEBA.get_or_init(Jieba::new)
}

/// Segments Chinese text into words.
///
/// Marked `DirtyCpu`: dictionary-based segmentation of a long passage can run past
/// the ~1ms budget a normal NIF must respect, and blocking a scheduler thread would
/// stall unrelated work across the node.
#[rustler::nif(schedule = "DirtyCpu")]
fn segment(text: &str) -> Vec<String> {
    jieba()
        .cut(text, false)
        .into_iter()
        .map(String::from)
        .collect()
}

/// Segments in "search" mode, which also emits shorter sub-words.
///
/// Better recall for indexing, worse precision — appropriate for building a lexical
/// index, not for displaying a tokenization to a user.
#[rustler::nif(schedule = "DirtyCpu")]
fn segment_for_search(text: &str) -> Vec<String> {
    jieba()
        .cut_for_search(text, false)
        .into_iter()
        .map(String::from)
        .collect()
}

/// Round-trips a string through Rust unchanged.
///
/// Exists to prove the FFI boundary preserves multi-byte characters exactly. Han
/// variants and plane-2 rare glyphs are semantically meaningful in a critical
/// edition, and silent corruption at a language boundary is exactly the class of bug
/// this project cannot tolerate.
#[rustler::nif]
fn echo(text: String) -> String {
    text
}

rustler::init!("Elixir.PramanaNative");
