# Source-record anchor contract

`record_key` identifies a logical source record within one bibliographic
source. It is minted once, opaque, and never derived from a name, line code,
person number, page, OCR position or text hash.

Each rendition produces physical `source_record_occurrence` rows first. An
occurrence may remain unanchored without losing its observations. An accepted
`source_record_anchor_event` connects one occurrence to one existing logical
record; one occurrence can have at most one current accepted target.

An improved OCR rendition is a new occurrence. A verified one-to-one mapping
can accept an anchor to the existing record. Split, merge and replacement
instead mint new logical records and create append-only
`source_record_revision_event` rows. Proposal, acceptance and rejection are
separate versions. Ambiguity is left for editorial review.
