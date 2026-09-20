# FR-07 candidate v4 self-withdrawal

Candidate v4 (`8d2447e73dd29fdacc797ddea7fd47ab32299efe`, tree
`2c8467430faf53d0aa676048ddd963ed727296db`) was withdrawn by the implementation owner
on 2026-09-13 before an independent verdict. Its source, evidence record and all earlier
history remain unchanged.

The owner disclosed two concrete acceptance gaps after freeze:

1. The attributed WAL xSync fixture used an ordinary candidate transaction. The governing
   sync design required a complete protected `transact_verified` bundle so the fault also
   exercised atomic effect, claim, reservation and ledger rows.
2. SQLite constraints covered the retained ledger row shape, but startup lacked the focused
   diagnosis's explicit typed semantic validator rejecting the unsupported child-generation
   form.

The ordinary-reopen branch also compared the pre-fault snapshot when the command was absent
but did not then execute the required same-command retry. Review was held; no PASS or
independent v4 review is claimed. V5 corrects these items with protected ordinary and
hard-exit fixtures, complete table/snapshot assertions, retry in both recovery outcomes and
typed ledger startup fencing.
