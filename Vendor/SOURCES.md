# Pinned Emoji Data Sources

These files are build-time inputs. Colon never fetches them at runtime.

## Unicode Emoji 17.0

Source directory: <https://www.unicode.org/Public/17.0.0/emoji/>

- `emoji-test.txt` — `1d8a944f88d7952f7ef7c5167fef3c67995bcae24543949710231b03a201acda`
- `emoji-sequences.txt` — `12cc8267dc33cbd11ed32bcf6fc5dc2ad9c7a77bae1bdfba2f41b1b9b3ead8dd`
- `emoji-zwj-sequences.txt` — `5b25441daed2322b068c5e70cda522946a4f0274df864445a1965a92e5fc5cad`
- License: `Vendor/Unicode/LICENSE.txt`

## CLDR 48

Source tag: <https://github.com/unicode-org/cldr/tree/release-48>

- `common/annotations/en.xml` — `8511aadd046fdba2f0ffe590266ced8bbf48175ad139b2675d85d7141057b235`
- `common/annotationsDerived/en.xml` — `d76bd041c8c9e7b00b716aff8b7d9dbf509877010e191d5efd068be2553e066e`
- License: `Vendor/CLDR/LICENSE`

## gemoji

Repository: <https://github.com/github/gemoji>

- Commit: `0eca75db9301421efc8710baf7a7576793ae452a`
- `db/emoji.json` — `b174ae2aeb321b52f64adb9ff412f966a7f338839d780784dd15dcad702c2dd6`
- License: `Vendor/gemoji/0eca75db9301421efc8710baf7a7576793ae452a/LICENSE`

## Slack-compatible emoji-data

- Repository: <https://github.com/iamcal/emoji-data>
- Commit: `e77759c296ed37beb0dbd63908b43d8619509c6d`
- `emoji.json` — `8736d721991e48c41c57acc46b65e5d32258a45e4bcdebcc6012f420f81e775d`
- License: `Vendor/emoji-data/e77759c296ed37beb0dbd63908b43d8619509c6d/LICENSE`
- Standard shortcodes are merged into existing searchable terms by Unicode identity.
  Existing aliases retain priority; workspace custom emoji and standalone skin-tone
  modifier entries are outside Colon's base-emoji dataset.
