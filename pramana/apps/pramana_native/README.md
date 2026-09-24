# Pramāṇa native

Rustler NIF for CJK segmentation using jieba-rs. This is an umbrella dependency of
the Pramāṇa core.

[The Mix manifest](mix.exs) owns Rustler configuration. Source lives in
[native/pramana_native](native/pramana_native). A successful NIF build does not
establish the quality of segmentation for Buddhist vocabulary; retrieval behavior
is evaluated separately.

The standalone text-reuse executable is elsewhere, at
[the quotation scanner](../../native/quotations); it communicates through JSONL files
and is not this NIF.

[Repository map](../../../docs/REPO_MAP.md) · [Testing](../../../docs/TESTING.md)
