# Changelog

## Unreleased

  - Rails 7.2 support: `ar_after_transaction` is now `>= 0.12.0, < 2` (0.10.0 only allowed ActiveRecord < 7.2). Tested on ActiveRecord 7.2.3.2 with ar_after_transaction 1.1.0
  - Versions now get `created_at` when the change happened (the record's `updated_at` for creates/updates, the current time otherwise) instead of when the background job ran, so ordering by `created_at` reflects change order
  - Fixed `record_update_columns` referencing an undefined `force`. Like PaperTrail it no longer checks `changed_notably?`, since `update_columns` skips dirty-tracking, which previously meant no version was written (see #14)

## 1.2.0

  - When async is false we want to fall back to the original logic (#11 thanks @erf530)
  - ar_after_transaction got updated for 7.1 Rails support (#10 thanks @caelanpthomas and @jeanpauldejong)
  - Introduced a ton of standardization with rubocop

## 1.1.0

I forgot to put any details here

## 1.0.1

I have no idea, I'll find out

## 1.0.0

  - Initial release
