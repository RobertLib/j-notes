# ASO: the reasoning, the competition, and the alternatives

Numbers in brackets are character counts. The limits are 30 for the name, 30 for
the subtitle and 100 for keywords.

Every figure in the tables below was read from Apple's own search endpoints on
30 August 2026 — the iTunes Search API for names, developers and rating counts,
Apple's search-suggestion endpoint for what people actually type, and the app
pages themselves for subtitles. Nothing here is an estimate from a third-party
ASO tool except where it says so.

## Where the listing stands today

```
Name       J-Notes                                    (7)
Subtitle   (empty)                                    (0)
Keywords   (unknown from outside)
Live since 3 September 2022, version 1.1.0, 1 rating, Productivity, free
```

Two of those lines are the whole problem.

**The name indexes two words, and one of them is a letter.** Apple splits on
non-alphanumerics, so `J-Notes` is indexed as *j* + *notes* — and *notes* is the
head term of the category, which this app cannot win on its own (see below). The
other 23 characters of the strongest ranking field in the listing are unspent.

**The subtitle is empty.** It is the second-strongest signal after the name and
the line people actually read in search results, and 30 characters of it are
sitting unused. Filling it in is the single cheapest ranking change available to
this app, and it needs no new build — the subtitle can be edited with any
version update.

There is one constraint on the name: the Home Screen name is `J-Notes`
(`INFOPLIST_KEY_CFBundleDisplayName`, the same in both languages) and Apple
requires the store name not to differ from it in *meaning*. Keeping `J-Notes` at
the front and spending the rest on head terms satisfies that and costs nothing —
the brand is first, the keywords follow it.

## What we are up against

Ratings are the US storefront. "Money" is how the app is paid for.

| App | Subtitle | Developer | Ratings | Money |
|---|---|---|---|---|
| Microsoft OneNote | Capture Notes, Ideas and Memos | Microsoft | 1 060 098 | Free + IAP |
| Notes | (none) | Apple | 633 223 | Free, preinstalled |
| Notability: AI Notes & Planner | Daily notebook & study journal | Ginger Labs | 454 100 | Free + sub |
| Goodnotes: AI Notes, Docs, PDF | Note taking, Planner & Journal | Goodnotes | 446 947 | Free + IAP |
| Notion: Notes, Tasks, AI | Plan, organize, track projects | Notion Labs | 89 911 | Free + sub |
| Evernote: AI Notes & Notebook | Tasks, memo & lists organizer | Evernote | 77 347 | Free + sub |
| n+otes | **Quick, easy note, private lock** | RIEU Limited | 45 300 | Free + IAP |
| Google Keep - Notes and lists | Notes and lists | Google | 28 973 | Free |
| Notepad: Easy Notes & Memos | Simple Notebook & Writing Pad | 1381802 Ontario | 27 845 | Free + IAP to $39.99 |
| Notebook – Notes, Notepad | Journal, Voice Memo & To-Do | Zoho | 23 847 | Free + IAP |
| Secure Notepad | Private Notes with Password | Dmytro Vynokurov | 13 194 | Free + IAP |
| Inkpad Notepad - Notes - To do | **(none)** | Workpail | 8 568 | Free + IAP |
| Sticky Notes & Color Widget | Simple Note Checklist Reminder | Hive 5 Studio | 6 628 | Free + sub |
| Notepad - Simple Notes & Memo | Open Fast to Jot Notes & Lists | Komorebi | 6 488 | Free + IAP |
| Standard Notes | End-to-end encrypted notes | Standard Notes | 3 711 | Free + sub |
| Lock Notes - Passcode Protect | Protect your notes w/ password | JulyApps | 1 154 | Free + IAP |
| Notesnook: Private notepad | Encrypted notes & secure vault | Streetwriters | 642 | Free + sub |

Six things follow from that table.

**We cannot win the head terms.** *note* measures at difficulty 88 / traffic 89
on Applyra's US index, and the ratings column explains why: the top three apps in
the category have between four hundred thousand and a million ratings each, and
one of them is preinstalled on the device. A one-rating app does not rank on
*notes*, *notepad* or *note taking* whatever it puts in its name. It already has
*notes* for free inside `J-Notes`; the rest of the budget goes elsewhere.

**Everybody in this category charges, and this app does not.** Every single app
in the table above except Google Keep monetises with a subscription, an in-app
purchase or ads — the "simple notepad" tier included, at up to $39.99. J-Notes
has no StoreKit code at all. That is a conversion lever rather than a keyword one
(see below), and it belongs in the subtitle, on a screenshot caption and in the
first line of the description.

**The long tail here is unusually reachable.** Apple's own search suggestions —
the terms it offers as you type, ordered by popularity — show dense clusters of
tiny apps sitting on exactly the intents this app serves:

| Typed | What Apple suggests |
|---|---|
| `notes widget` | notes widget free · lock screen notes widget · sticky notes widget free · shared notes widget |
| `private notes` | private notes and secret diary · private notes lock: notepad · **private notes: offline notepad** · minoo - private notes |
| `notes lock` | notes lock – password note · secret notes lock & to do list · easy notes lock · private notes - locknotes |
| `secure notes` | secure notes with passwords or biometrics · secure notes - memo and lists · localvault: secure notes |
| `notes reminder` | notes reminders · notepad - daily notes reminder · notty - notes & reminders · pinpoint: notes & reminders |
| `drawing notes` | drawing notes · drawing notes - noteit widget |

The apps ranking on those phrases have hundreds to low thousands of ratings, not
hundreds of thousands. *private notes: offline notepad* being a suggested phrase
at all is the clearest possible statement that the niche exists and is being
searched for by name.

**One competitor is already standing exactly where we want to stand.** `n+otes`
has 45 300 ratings and the subtitle *"Quick, easy note, private lock"* — the
private-lock angle, played well, at a scale this app cannot match head-on. It is
worth reading as a validation rather than a wall: it charges (in-app purchases),
it has no drawing, no map, no reminders and no Lock Screen widgets, and its own
name is unsearchable. The way past it is the combination — *lock* **and**
*offline* **and** *free* **and** *draw* — not the lock on its own. Note also
`Inkpad Notepad`, 8 568 ratings and **no subtitle at all**: leaving that field
empty is a common enough mistake that it is worth being the app that does not.

**"Drawing notes" is nearly empty, and this app has real drawing.** Apple returns
*two* suggestions for it. PencilKit with pen, marker and pencil, a photo
background and pinch-to-zoom is not something the notepad tier of the category
has, and it is not something the handwriting tier (Goodnotes, Notability,
Noteshelf) reaches down into. It costs one keyword and one word of the name.

**And one thing that is *not* true here, unlike the sister projects.** In
solitaire, *no ads* was a keyword as well as a promise — searching it returns a
visible cluster of apps whose whole name is that promise. In notes it is not:
Apple's suggestions for `notes no ads` return a single unrelated app. So *no ads*
earns its place in the subtitle for **conversion** — it is what makes someone tap
this result instead of the ad-supported one above it — and no keyword characters
are spent chasing it.

## The Czech storefront is nearly empty, and that is the opportunity

| CZ name | Developer | CZ ratings | Money |
|---|---|---|---|
| Poznámky | Apple | 3 350 | preinstalled |
| Poznámky+ | SINGFISH | 1 512 | IAP to 499 Kč, nine AI purchases |
| Poznámky: poznámkový blok | Orange dog | 789 | ads, 249 Kč to remove |
| CollaNote: Poznámky & PDF | Zauberberg Lab | 207 | Free + IAP |
| Samolepicí a Poznámkové Bločky | Hive 5 Studio | 76 | Free + sub |
| Poznámky - Jednoduchý blok | Komorebi | 59 | Free + IAP |
| Notepad: Jednoduché poznámky | 1381802 Ontario | 37 | Free + IAP |
| Inkpad - Poznámky a seznamy | Workpail | 16 | Free + IAP |

The whole localised Czech notes market tops out at 1 512 ratings for the largest
third-party app, against 633 223 for Apple's own app in the US. Three findings
shaped `cs/`:

- **Czech search is genuinely thin here.** Apple's suggestion endpoint returns
  *nothing* for `zápisník` and only voice-recorder apps for `poznámky` — the
  index has barely enough Czech query volume to build suggestions from. That
  cuts both ways: less traffic, but also almost no competition for a listing
  that is actually written in Czech rather than machine-translated.
- **More competitors localise here than in the card-game category.** Eight of
  them carry a Czech name, which is more than solitaire faced — but they are all
  ad-supported or AI-subscription apps. *Bez reklam* is the differentiator in
  Czech even more sharply than in English.
- **`poznámky` and `poznámkový` are separate tokens.** Apple's Czech stemming is
  not reliable enough to assume otherwise, which is why the name carries
  *poznámky* and the keyword list carries *poznámkový* and *blok* separately.
  The same reasoning puts *zámek* in the keyword list even though the subtitle
  says *zámkem*: one is what the app does, the other is what people type.

## What is in use

```
en-US   J-Notes: Notepad, Lock, Draw   (28)   Private, offline, no ads ever    (29)
en-GB   J-Notes: Notepad, Lock, Draw   (28)   Secure, offline, no ads ever     (28)
cs      J-Notes: Poznámky a zápisník   (28)   Se zámkem, offline, bez reklam   (30)
```

Between the name and the subtitle, `en-US` indexes *j, notes, notepad, lock,
draw, private, offline, no, ads, ever* — and because Apple combines terms within
a locale, that assembles *private notes*, *offline notes*, *notes lock*, *lock
notes*, *private notepad*, *offline notepad*, *drawing notes*, *notepad no ads*
and *private notes offline* without spending a single keyword character on any of
them. Every one of those is a phrase Apple's own suggestion endpoint confirms
people type.

The listy `Name: A, B, C` shape is not a compromise — it is the category
convention. *Notion: Notes, Tasks, AI*, *Goodnotes: AI Notes, Docs, PDF*,
*Notepad: Easy Notes & Memos* and *Evernote: AI Notes & Notebook* are all built
that way, and a store visitor reads it as a feature list rather than as keyword
stuffing.

## App name

| Czech | | English | |
|---|---|---|---|
| J-Notes: Poznámky a zápisník | (28) | J-Notes: Notepad, Lock, Draw | (28) |
| J-Notes: Poznámky se zámkem | (27) | J-Notes: Private Notepad | (24) |
| J-Notes: Poznámkový blok | (24) | J-Notes: Notepad, Lock, Widget | (30) |
| J-Notes: Poznámky a kreslení | (28) | J-Notes: Notepad & Sketchpad | (28) |
| J-Notes: Zápisník a seznamy | (27) | J-Notes: Offline Notepad | (24) |

Recommendation: keep the three-feature list. It is the only form that gets
*notepad*, *lock* and *draw* into the strongest field at once, and the three of
them are precisely the intents the long tail is searchable on. If it ever needs
to change, `J-Notes: Notepad, Lock, Widget` is the straight swap — it trades
*draw* (low competition, low volume) for *widget* (higher volume, verified by
Apple's own suggestions), and *sketch* in the keyword list then carries the
drawing angle on its own.

Do not drop `J-Notes` from the front. The Home Screen name is `J-Notes`, and a
store name that no longer reads as the same app is a metadata rejection waiting
to happen. Putting the brand first also costs nothing: Apple combines terms in
any order, so *notes lock* and *lock notes* both match whatever the word order is.

## Subtitle

| Czech | | English | |
|---|---|---|---|
| Se zámkem, offline, bez reklam | (30) | Private, offline, no ads ever | (29) |
| Offline, zdarma, bez reklam | (27) | Secure, offline, no ads ever | (28) |
| Zamykací poznámky bez reklam | (28) | Locked notes, offline and free | (30) |
| Soukromé, offline, bez účtu | (27) | No ads, no account, no cloud | (28) |
| Kreslení, připomínky, offline | (29) | Sketch, remind, lock. Offline | (29) |

`en-GB` deliberately overlaps `en-US` rather than filling in its gaps. It is the
second index in the Czech storefront, but it is the *only* index in the UK,
Ireland, Australia and New Zealand — so it gets the strong set rather than the
leftovers. What it changes is one word: *secure* instead of *private*, which
frees *private* for its keyword list and picks up *secure* in the strongest field
it can. Apple's suggestions treat `private notes` and `secure notes` as two
separate phrases with two separate app clusters, so covering both across the two
English localisations is free reach.

## Keywords

In use:

```
en-US  widget,screen,reminder,memo,checklist,sketch,password,secure,free,pencil,diary,list,internet,map   (96)
en-GB  widget,screen,reminder,memo,checklist,sketch,password,private,free,pencil,diary,list,internet,map  (97)
cs     poznámkový,blok,seznam,úkoly,připomínky,kreslení,heslo,zámek,soukromé,deník,widget,zdarma,mapa      (94)
```

Why each of the less obvious ones is there:

- **`widget` + `screen`** — *lock* is already in the English name, so those two
  assemble *lock screen widget*, *notes widget* and *lock screen notes widget*,
  all three of which Apple suggests. The app has Home Screen widgets in three
  sizes and Lock Screen widgets in all three accessory shapes, so the claim
  holds. This is the highest-value pair in the list.
- **`internet`** — buys *notes without internet* and *notepad no internet*
  alongside *offline* in the subtitle. Cheap, and honest: there is no networking
  code in the app.
- **`map`** — three characters for a differentiator nobody else in the category
  has. Low volume, zero competition.
- **`diary`** — *diary* and *journal* are large adjacent intents, and location
  notes plus reminders genuinely serve them. Only one of the two fits; *diary*
  is the shorter and the more searched.
- **`pencil`** — carries *apple pencil notes*, which the drawing support earns.
- **`memo`**, **`list`**, **`checklist`** — the plain-notepad intents, and Apple
  pairs each with its plural itself, so *lists* and *memos* come free.

Rules, so that editing does not break it:

- Separate with a comma and **no space after the comma** — a space counts towards
  the limit of 100.
- Do not repeat words from the name or the subtitle, Apple indexes those
  separately. **This applies between the name and the subtitle too.** That is why
  *notes*, *notepad*, *lock*, *draw*, *private* and *offline* are absent from the
  English lists, and *poznámky*, *zápisník*, *offline* and *reklam* from the
  Czech one.
- Do not put a plural next to its singular ("list" and "lists"), Apple pairs them
  itself. The Czech set bends this once, for *zámkem* / *zámek*: Czech stemming
  is unreliable enough that the nominative is worth its five characters.
- Do not name competing apps — grounds for rejection. In this category the
  tempting ones are *evernote*, *onenote*, *goodnotes*, *keep* and *notion*, and
  all five are other people's app names.
- Do not use *apple* as a keyword. *Pencil* is fine; the trademark in front of it
  is not ours to put in an indexed field, and Apple indexes the description
  separately anyway.
- Do not claim *AI*. Half the category has bolted an AI subtitle on in the last
  two years and it is the obvious traffic magnet — but there is no AI in this app,
  and a keyword that wins the tap and loses the install is worse than no keyword.

Alternative sets, if you end up tuning by performance:

```
# EN, privacy-first angle (pairs with a "Locked, offline, no cloud" subtitle)
password,secret,secure,vault,encrypted,local,hidden,safe,memo,list,checklist,widget,free           (93)

# EN, widget angle (pairs with a "Notes on your Lock Screen" subtitle)
widget,screen,home,sticky,memo,quick,jot,pad,list,checklist,reminder,free,pin,color,tags           (95)

# EN, drawing angle (pairs with a "Sketch, write, lock. Offline." subtitle)
pencil,sketch,drawing,handwriting,pen,marker,paint,doodle,photo,memo,list,widget,free,diary        (96)

# CZ, soukromí angle
heslo,zámek,soukromé,skryté,bezpečné,trezor,místní,memo,seznam,úkoly,widget,zdarma,internetu       (94)

# CZ, kreslení a cestování angle
kreslení,tužka,kresba,fotka,mapa,cestování,deník,výlet,poznámkový,blok,widget,zdarma,připomínky    (98)
```

## The one thing to fix in the description before anything else

The live description claims **"Rich Text Editing — Format your notes with bold,
italic, underline, and more"**. The app does not do that. The body is a plain
`String` in a plain `UITextView` (`notes/Views/Notes/UndoableTextEditor.swift`);
what the editor actually offers is undo/redo and a checklist button. Under
guideline 2.3 that is inaccurate metadata, and it is also the kind of claim that
earns a one-star review from someone who bought into it. The description in
`en-US/description.txt` replaces it with the two things that are real — undo and
redo under the keyboard, and checklist lines inside the text.

While in there: the live description also leads with *"Smart Notes, Organized
Life"* and *"note-taking reimagined"*, which index nothing and say nothing. The
first line of a description is prime space; the new one spends it on the promise
that actually differentiates the app.
