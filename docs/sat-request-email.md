# Correspondence with the SAT Daizōkyō Text Database Committee

> Draft correspondence and supporting notes, not a sent message or evidence of permission. Verify recipient, licensing scope and current acquisition status before use.

**Status: the first request was SENT on 2026-08-15.** No reply as of 2026-08-29. Note it
landed during Obon, when Japanese universities are largely closed, so fourteen days is not
yet a silence worth reading into. The follow-up below is drafted for **mid-September** and
is again a human decision to send.

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


---

# Follow-up, drafted 2026-08-29 — send from mid-September if there is still no reply

**Why this one is different from a reminder.** It does three things the first could not:
it thanks them for data we are now actually using, it cites their own CC BY-SA 4.0 release
as the precedent for the ask, and it replaces an open-ended request with a **small, bounded,
easy-to-approve alternative**.

That last point is the substance, and the number was **measured, then corrected**. An
earlier draft said 28,800 requests, on the assumption that the reader is paginated. It is
not: `satdb2018pre.php?...&useid={work}_{vol}_{fascicle}` returns an entire **fascicle** per
request — one probe came back at 321 KB carrying line ids from `0001a01` onward. The corpus
measures **145.4 fascicles per Taishō volume** across the 56 volumes it already holds, so 29
volumes is about **4,200 requests**, not 28,800.

    requests           ~4,200 (one per fascicle)
    transferred        ~1.3 GB of HTML, yielding ~44M characters of text
    at 1 req / 3 s     ~3.5 hours
    at 1 req / 5 s     ~6 hours

The first letter declined to crawl on the grounds that it would be an unreasonable load. At
four thousand requests over an afternoon that is simply not true, and saying so plainly is
better than repeating an over-cautious claim: what is missing is permission, not capacity.

## Subject

```
Re: 大正新脩大藏經テキストデータ（第56–84巻）の一括提供のお願い / Follow-up: request for SAT text data (vols. 56–84)
```

## Body

```
SAT大蔵経テキストデータベース委員会 御中

八月十五日にお送りいたしました件につきまして、改めてご連絡申し上げます。お盆の時期
に重なり、ご多忙のところ恐縮でございました。

まず、御礼を申し上げます。貴研究会と国文学研究資料館が CC BY-SA 4.0 にて公開されて
おります「日本撰述部 底本調査」のデータを拝受し、活用させていただいております。出典
は両機関を明記のうえ表示いたします。第2185番から第2346番までの百四十四典籍につき、
底本・所蔵機関・請求記号を辿れるようになりましたことは、本プロジェクトにとって大き
な意味がございます。

その上で、改めて第56–84巻のテキストデータについてお願い申し上げます。上記の底本調査
が CC BY-SA 4.0 で公開されていることに鑑み、同じ日本撰述部のテキストにつきましても、
同様の条件でご提供いただけないでしょうか。

一括でのご提供が難しい場合、代替案として、貴サイトのテキスト表示機能を通じて、
**低速での取得**をお許しいただくことは可能でしょうか。巻単位での取得となりますため、
リクエスト数は約四千二百回、時間にして数時間程度と見込んでおります。三秒から五秒に
一回程度の間隔で取得いたしますので、貴サービスへの負荷は軽微かと存じます。取得時間帯
のご指定、間隔のご指示など、条件を付していただければ、それに従います。

前便でも申し上げましたとおり、非営利の学術目的に限り利用し、CC BY-SA 4.0 に従って
出典を検索結果ごとに明示いたします。本文そのものの再配布は予定しておりません。

ご多忙のところ恐れ入りますが、ご検討賜れますと幸いです。

レイモンド・ルオン
raymond.n.luong@gmail.com

────────────────────────────────────────

Dear SAT Daizōkyō Text Database Committee,

I am following up on my message of 15 August. I realise it arrived during Obon, and I
apologise for adding to a busy period.

First, my thanks. I have obtained and am using the base-text survey of the Japanese-composed
section (日本撰述部 底本調査) that your group and the National Institute of Japanese
Literature publish under CC BY-SA 4.0, and I attribute both creators. Being able to trace
144 works — Taishō 2185 to 2346 — back to the manuscript each was edited from, and to the
institution holding it, is genuinely valuable to this project.

With that in mind, I would like to renew my request for the text of Taishō volumes 56–84.
Given that you already publish the base-text survey for this same section under CC BY-SA
4.0, would the text of that section be available on the same terms?

If a bulk copy is not practical, may I ask about an alternative: would you permit a
**slow, rate-limited retrieval** through your text display interface? Because your reader
returns a whole fascicle per request, this comes to roughly **4,200 requests** — a few hours
at one request every three to five seconds, not a sustained crawl. I would gladly work to
any constraint you set: a fixed interval, a restricted time of day, or a schedule of your
choosing.

As before, use would be non-commercial and scholarly only, attribution would follow
CC BY-SA 4.0 on every result, and I would not redistribute the text itself.

Thank you again for making this material available at all.

With respect,

Raymond Luong
raymond.n.luong@gmail.com
```

## If there is still no answer

Silence is an answer to plan around, not to keep re-asking. Two options that do not require
SAT, and one that is not an option:

- **Report the gap precisely rather than fill it.** `Pramana.Coverage` already states the
  547-work absence on every affected query; the base-text survey lets 144 of them be
  described rather than merely counted. That is honest and it is available today.
- **Formally move #14 out of the Phase 2 gate**, so the gate can be tagged. `docs/PLAN.md`
  already contemplates this — *"withheld until #14 resolves or is formally moved"* — and a
  gate withheld indefinitely on a dependency nobody controls stops carrying information.
- **Not an option: fetching anyway.** The first letter said, in writing, that we would not
  crawl. The licence would permit it; the commitment does not. Ask, or do without.
