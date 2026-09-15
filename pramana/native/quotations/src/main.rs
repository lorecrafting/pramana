//! Finds verbatim text reuse across the corpus.
//!
//! Buddhist commentaries quote their root texts constantly, and the Chinese canon
//! recycles stock passages across works that were compiled centuries apart. Finding
//! those reuses is **deterministic** — no model, no embedding, no judgement — which is
//! why it belongs here rather than in a similarity search.
//!
//! # Why a standalone binary and not a NIF
//!
//! The working set is over a gigabyte for 85.9M characters of Literary Chinese, and a
//! NIF holding that inside the BEAM would put a multi-gigabyte allocation and a long
//! CPU-bound loop inside a scheduler that expects neither. This runs once per bake, so
//! a process boundary costs nothing and buys isolation: if it dies, it dies alone.
//!
//! Input and output are JSONL **files**, the same shape the embedding round trip already
//! uses: text out, results back. Files rather than pipes because the payload is hundreds
//! of megabytes, `System.cmd/3` has no stdin option anyway, and a file left on disk can
//! be inspected when a run surprises you. Postgres stays on the Elixir side, in one
//! language.
//!
//! # Why seed-and-extend rather than a suffix array
//!
//! A suffix array over 258 MB of UTF-8 would work and would give maximal matches
//! directly — roughly 2-3 GB with the LCP array, which fits. Seed-and-extend was chosen
//! because it makes the two decisions that actually matter **explicit and tunable**:
//! the minimum length worth calling a quotation, and the frequency above which a
//! repeated string is boilerplate rather than a citation. In this corpus that second
//! knob is not optional: 如是我聞 opens nearly every sūtra, and a method that cannot
//! dismiss it drowns in matches that mean nothing.
//!
//! # What counts as a match
//!
//! A maximal run of identical characters, at least `min_len` long, occurring in **two
//! different works**. Maximal matters: reporting every 12-character window of a
//! 200-character shared passage would report one quotation as 189 of them. A match is
//! emitted only from the seed at its left edge, which is what makes the output one row
//! per reuse.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::File;
use std::io::{self, BufRead, BufReader, BufWriter, Write};

/// Characters hashed as a seed. Short enough that a real quotation is very unlikely to
/// lack one, long enough that random collisions between unrelated passages are rare.
const SEED_LEN: usize = 12;

/// A seed occurring more often than this is boilerplate — a formula, a refrain, a
/// stock epithet — not a citation. 如是我聞 ("thus have I heard") opens nearly every
/// sūtra in the canon; treating that as text reuse would bury the real findings.
const MAX_SEED_FREQ: usize = 200;

#[derive(Deserialize)]
struct InputWork {
    work: String,
    text: String,
}

#[derive(Serialize)]
struct Match {
    text: String,
    length: usize,
    occurrences: Vec<Occurrence>,
}

#[derive(Serialize, Clone)]
struct Occurrence {
    work: String,
    /// Character offset into the work's concatenated body — NOT a byte offset. The
    /// Elixir side maps this back to a segment URN, and its own offsets are in
    /// characters, so converting here would mean converting back there.
    start: usize,
    end: usize,
}

struct Work {
    name: String,
    chars: Vec<char>,
}

fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.len() < 4 {
        eprintln!("usage: pramana-quotations <min_len> <input.jsonl> <output.jsonl>");
        std::process::exit(2);
    }

    let min_len: usize = args[1].parse().expect("min_len must be a number");
    let works = read_works(&args[2]);
    let total: usize = works.iter().map(|w| w.chars.len()).sum();
    eprintln!(
        "{} work(s), {} characters, seed {} min_len {}",
        works.len(),
        total,
        SEED_LEN,
        min_len
    );

    let index = build_seed_index(&works);
    eprintln!("{} distinct seed(s) worth following", index.len());

    let matches = find_matches(&works, &index, min_len);
    eprintln!("{} maximal match(es)", matches.len());

    let mut out = BufWriter::new(File::create(&args[3]).expect("cannot create output"));
    for m in matches {
        writeln!(out, "{}", serde_json::to_string(&m).unwrap()).unwrap();
    }
    out.flush().unwrap();
}

fn read_works(path: &str) -> Vec<Work> {
    let file = File::open(path).expect("cannot open input");
    let mut works = Vec::new();

    for line in BufReader::new(file).lines() {
        let line = line.expect("read");
        if line.trim().is_empty() {
            continue;
        }
        let input: InputWork = serde_json::from_str(&line).expect("malformed input line");
        works.push(Work {
            name: input.work,
            chars: input.text.chars().collect(),
        });
    }

    works
}

/// Maps each seed hash to the positions where it occurs, dropping seeds that are too
/// common to be evidence of anything.
///
/// Two passes rather than one: counting first means the position lists are only built
/// for seeds that survive the frequency filter, which is most of the memory saved.
fn build_seed_index(works: &[Work]) -> HashMap<u64, Vec<(usize, usize)>> {
    let mut counts: HashMap<u64, u32> = HashMap::new();

    for work in works {
        for (hash, _) in seeds(&work.chars) {
            *counts.entry(hash).or_insert(0) += 1;
        }
    }

    let mut index: HashMap<u64, Vec<(usize, usize)>> = HashMap::new();

    for (w, work) in works.iter().enumerate() {
        for (hash, pos) in seeds(&work.chars) {
            match counts.get(&hash) {
                // A seed occurring once cannot be reuse; one occurring thousands of
                // times is a formula.
                Some(&n) if n > 1 && (n as usize) <= MAX_SEED_FREQ => {
                    index.entry(hash).or_default().push((w, pos));
                }
                _ => {}
            }
        }
    }

    index
}

fn seeds(chars: &[char]) -> impl Iterator<Item = (u64, usize)> + '_ {
    chars
        .windows(SEED_LEN)
        .enumerate()
        .map(|(pos, window)| (hash(window), pos))
}

/// FNV-1a over the characters. Not cryptographic and does not need to be — a collision
/// costs a wasted comparison, which the extension step rejects, never a wrong result.
fn hash(chars: &[char]) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for c in chars {
        let mut v = *c as u32;
        for _ in 0..4 {
            h ^= (v & 0xff) as u64;
            h = h.wrapping_mul(0x100_0000_01b3);
            v >>= 8;
        }
    }
    h
}

fn find_matches(
    works: &[Work],
    index: &HashMap<u64, Vec<(usize, usize)>>,
    min_len: usize,
) -> Vec<Match> {
    let mut matches: Vec<Match> = Vec::new();

    for positions in index.values() {
        for (i, &(wa, pa)) in positions.iter().enumerate() {
            for &(wb, pb) in positions.iter().skip(i + 1) {
                // Reuse means one text quoting ANOTHER. A work repeating itself is a
                // different phenomenon — refrains, formulaic repetition within a sūtra —
                // and mixing the two would swamp the graph with self-matches.
                if wa == wb {
                    continue;
                }

                if let Some(m) = extend(works, wa, pa, wb, pb, min_len) {
                    matches.push(m);
                }
            }
        }
    }

    matches
}

/// Grows a seed hit to the maximal identical run around it.
///
/// Returns `None` unless the seed sits at the match's **left edge** — that is, unless
/// the preceding characters differ. Every seed inside a shared passage would otherwise
/// rediscover the same match, and a 200-character quotation would be reported 189
/// times.
fn extend(
    works: &[Work],
    wa: usize,
    pa: usize,
    wb: usize,
    pb: usize,
    min_len: usize,
) -> Option<Match> {
    let a = &works[wa].chars;
    let b = &works[wb].chars;

    if pa > 0 && pb > 0 && a[pa - 1] == b[pb - 1] {
        return None;
    }

    let mut len = 0;
    while pa + len < a.len() && pb + len < b.len() && a[pa + len] == b[pb + len] {
        len += 1;
    }

    if len < min_len {
        return None;
    }

    Some(Match {
        text: a[pa..pa + len].iter().collect(),
        length: len,
        occurrences: vec![
            Occurrence {
                work: works[wa].name.clone(),
                start: pa,
                end: pa + len,
            },
            Occurrence {
                work: works[wb].name.clone(),
                start: pb,
                end: pb + len,
            },
        ],
    })
}
