# Draft: bulk-data request to the SAT Daizōkyō Text Database Committee

**Status: DRAFT, not sent.** Sending is a human decision — this is a request to a
university research group, and it should go out under a real name.

- **To:** `sat@l.u-tokyo.ac.jp`
- **From:** raymond.n.luong@gmail.com
- **Why:** SAT publishes no bulk download and no documented API; the site directs bulk
  enquiries to this address. See `docs/SOURCES.md` and task #14.

Two versions below. The Japanese one is likely to get a better response — this is a
Japanese university project — but the committee publishes in English too, so either is
reasonable. Sending both in one message (Japanese first, English below) is the usual
courtesy and is what the combined draft does.

---

## Subject

```
大正新脩大藏經テキストデータ（第56–84巻）の一括提供のお願い / Request for bulk access to SAT text data (vols. 56–84)
```

---

## Body

```
SAT大蔵経テキストデータベース委員会 御中

はじめまして。レイモンド・ルオン（Raymond Luong）と申します。

私は現在、仏典を対象とした非営利・オープンソースの検索基盤を個人で開発しております。
この基盤の目的は、引用の出所を厳密に保持することにあります。すなわち、検索結果の一つ
一つについて、それがインド撰述の翻訳経典なのか、中国撰述の注釈なのか、日本撰述の宗派
的著作なのかを明示し、利用者が典拠を printed edition に遡って確認できるようにするもの
です。

現在はCBETA（大正蔵1–55巻・85巻）を収録しておりますが、まさにその欠落部分である
第56–84巻——すなわち日本撰述の宗派的著作群——を欠いております。この部分を貴データベース
以外から入手する手段が見当たらず、ご連絡差し上げた次第です。

つきましては、第56–84巻（可能であれば全85巻）のテキストデータを、既に公開されている
CC BY-SA 4.0 の条件のもとで、一括して頂くことは可能でしょうか。ウェブサイトを機械的に
巡回することは貴サービスへの負担となり不適切と考え、まずは正規の手続きとしてお願い申し
上げる次第です。

利用条件について、以下を遵守いたします。

・非営利の学術目的に限定して利用いたします。
・CC BY-SA 4.0 に従い、出典（SAT大蔵経テキストデータベース、大蔵出版株式会社）を
  検索結果ごとに明示いたします。
・本プロジェクトが公開するのは処理パイプライン（ソースコード）のみであり、
  テキスト本文そのものを再配布することは予定しておりません。
・貴委員会が付されるご条件があれば、それに従います。

ご多忙のところ恐縮ですが、ご検討のほどよろしくお願い申し上げます。
技術的な形式（TEI/XML等）やご条件について、詳細を伺えますと幸いです。

レイモンド・ルオン
raymond.n.luong@gmail.com

---

Dear SAT Daizōkyō Text Database Committee,

My name is Raymond Luong. I am writing to ask about obtaining a bulk copy of the SAT
text data.

I am building a non-commercial, open-source retrieval system for Buddhist canonical
texts. Its purpose is to keep the provenance of every citation explicit: whether a
passage comes from an Indic text in Chinese translation, a Chinese-composed commentary,
or a Japanese-composed sectarian work — and to let a reader check any citation against
the printed edition it came from.

The corpus currently holds CBETA, which covers Taishō volumes 1–55 and 85. The gap is
exactly volumes 56–84 — the Japanese-composed sectarian corpus (Shingon, Tendai,
Nichiren, Zen). As far as I can find, SAT is the only source that publishes this
material, and I could not locate a bulk download or a documented API.

Would it be possible to obtain the text data for volumes 56–84 (or all 85 volumes) as a
bulk copy, under the CC BY-SA 4.0 terms already granted? I did not want to crawl the
online reader: that would place an unreasonable load on your service, so I am asking
through the proper channel first.

I would of course comply with the licence and with any conditions you attach:

- Non-commercial, scholarly use only.
- Attribution to the SAT Daizōkyō Text Database and Daizō Shuppan on every result, as
  CC BY-SA 4.0 requires.
- The project publishes its processing pipeline as open source; it does not redistribute
  the text itself.

I would be glad to hear what format the data is available in (TEI/XML or otherwise) and
what conditions would apply.

Thank you for your time, and for making this material available at all.

With respect,

Raymond Luong
raymond.n.luong@gmail.com
```

---

## Notes before sending

- **Check the address.** It was published on the SAT site as `sat at l.u-tokyo.ac.jp`
  (obfuscated against scrapers); confirm it is current before sending.
- **The ask is deliberately narrow** — volumes 56–84 — with the whole set as an
  alternative. A smaller request is easier to say yes to.
- **The claim that we do not redistribute the text is load-bearing.** It is currently
  true (`sources/local/*/text/` and `raw/` are gitignored; we publish the pipeline).
  If that ever changes, this promise has to change with it.
- If they decline or do not reply, `Pramana.Coverage` already states the gap in every
  survey response, so the corpus stays honest about what it does not contain.
