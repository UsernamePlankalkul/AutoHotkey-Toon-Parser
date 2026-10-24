<div align="center">

# 🎨 Toon.ahk

### TOON (Token-Oriented Object Notation) encoder & parser for AutoHotkey v2

*A compact, human-readable JSON alternative, built for fewer tokens.*

![AutoHotkey](https://img.shields.io/badge/AutoHotkey-v2.0.30-334455?style=for-the-badge&logo=autohotkey&logoColor=white)
![Format](https://img.shields.io/badge/format-TOON-ff6b35?style=for-the-badge)
![Encode](https://img.shields.io/badge/encode-✔-2ea44f?style=for-the-badge)
![Decode](https://img.shields.io/badge/decode-✔-1f6feb?style=for-the-badge)
![JSON](https://img.shields.io/badge/JSON_bridge-✔-8957e5?style=for-the-badge)
![Dependencies](https://img.shields.io/badge/dependencies-none-e3b341?style=for-the-badge)

**[Quick start](#-quick-start)** · **[TOON in 60 seconds](#-toon-in-60-seconds)** · **[API](#-api-reference)** · **[Options](#%EF%B8%8F-options)** · **[Examples](#-examples)** · **[Troubleshooting](#-troubleshooting)**

</div>

---

## 📖 Table of contents

- [✨ Features](#-features)
- [🚀 Quick start](#-quick-start)
- [🧠 TOON in 60 seconds](#-toon-in-60-seconds)
- [🧰 API reference](#-api-reference)
- [⚙️ Options](#%EF%B8%8F-options)
- [🧬 Value model](#-value-model)
- [🧪 Examples](#-examples)
- [🛡️ Strict mode and errors](#%EF%B8%8F-strict-mode-and-errors)
- [🧱 The `Toon.OMap` class](#-the-toonomap-class)
- [⚠️ Limitations](#%EF%B8%8F-limitations)
- [🩺 Troubleshooting](#-troubleshooting)
- [📄 License](#-license)

---

## ✨ Features

| | Feature | Details |
|---|---|---|
| 🟢 | **Encode** | AutoHotkey values to TOON text with `Toon.Stringify` |
| 🔵 | **Decode** | TOON text to AutoHotkey values with `Toon.Parse` |
| 🟣 | **JSON bridge** | `Toon.FromJson` and `Toon.ToJson`, with a built-in JSON parser and writer |
| 🟠 | **All array styles** | Inline primitive arrays, tabular arrays, list arrays, arrays of arrays |
| 🟡 | **Delimiters** | Comma (default), tab or pipe |
| 🔴 | **Strict mode** | Validates array lengths, indentation, tabs and blank lines |
| 🟤 | **Key folding / path expansion** | `a.b.c: 1` to and from nested objects |
| ⚪ | **Ordered objects** | `Toon.OMap` keeps insertion order, so field order survives a round trip |
| ⚫ | **Single file** | Drop in `Toon.ahk`, no dependencies |

---

## 🚀 Quick start

### 1️⃣ Install

Copy **`Toon.ahk`** next to your script (or into your `Lib` folder).

```ahk
#Requires AutoHotkey v2.0.30
#Include Toon.ahk
```

### 2️⃣ Parse TOON

```ahk
text := "
(
name: Ada
tags[3]: math,code,music
)"
; Tip: build multi-line text with "`n" if your editor re-indents continuation sections.

data := Toon.Parse("name: Ada`ntags[3]: math,code,music")
MsgBox data["name"]          ; Ada
MsgBox data["tags"][2]       ; code
```

### 3️⃣ Create TOON

```ahk
obj := Toon.OMap("name", "Ada", "tags", ["math", "code", "music"])
MsgBox Toon.Stringify(obj)
```

Output:

```toon
name: Ada
tags[3]: math,code,music
```

### 4️⃣ Run the built-in demo

Run `Toon.ahk` directly. It shows a round-trip encode and decode and a TOON to JSON conversion. The demo is skipped automatically when the file is `#Include`d.

---

## 🧠 TOON in 60 seconds

> [!NOTE]
> TOON uses **indentation** for structure (like YAML) and **declares array lengths and fields once** (like CSV), so repeated keys are not spelled out for every row.

**JSON**

```json
{
  "friends": ["ana", "luis", "sam"],
  "hikes": [
    { "id": 1, "name": "Blue Lake Trail", "distanceKm": 7.5, "wasSunny": true },
    { "id": 2, "name": "Ridge Overlook",  "distanceKm": 9.2, "wasSunny": false }
  ]
}
```

**TOON**

```toon
friends[3]: ana,luis,sam
hikes[2]{id,name,distanceKm,wasSunny}:
  1,Blue Lake Trail,7.5,true
  2,Ridge Overlook,9.2,false
```

### 🎯 Cheat sheet

| 🎨 Construct | ✍️ Syntax | 📝 Meaning |
|---|---|---|
| 🟦 Object field | `key: value` | Primitive value |
| 🟦 Nested object | `key:` + indented lines | Indent = nesting |
| 🟩 Inline array | `tags[3]: a,b,c` | `[N]` is the item count |
| 🟧 Tabular array | `rows[2]{id,name}:` + rows | Uniform objects with primitive values |
| 🟪 List array | `items[2]:` + `- ...` lines | Mixed or nested content |
| 🟪 Array of arrays | `- [2]: 1,2` | Inner array inside a list |
| 🟨 Pipe / tab delimiter | `tags[3\|]: a\|b\|c` | Delimiter declared in the brackets |
| 🟥 Quoted string | `"hello, world"` | Quotes only when needed |
| ⬜ Empty array | `items[0]:` | |
| ⬜ Empty object | `key:` (nothing below) | |

### 🔤 When are strings quoted?

A string value is written in quotes **only if** it:

- is empty, or has leading or trailing whitespace
- equals `true`, `false` or `null`
- looks like a number (`42`, `-3.5`, `1e6`, `05`)
- contains `:` `"` `\` `[` `]` `{` `}` or a control character such as a newline or tab
- contains the active delimiter
- starts with `-`

Escapes inside quotes: `\\` `\"` `\n` `\r` `\t`.

---

## 🧰 API reference

### 🔵 Decoding

| Call | Returns | Description |
|---|---|---|
| `Toon.Parse(text, opts?)` | value | Parse TOON text |
| `Toon.Decode(text, opts?)` | value | Alias of `Parse` |
| `Toon.ParseFile(path, opts?)` | value | Read a UTF-8 file and parse it |

### 🟢 Encoding

| Call | Returns | Description |
|---|---|---|
| `Toon.Stringify(value, opts?)` | string | Encode a value as TOON |
| `Toon.Encode(value, opts?)` | string | Alias of `Stringify` |
| `Toon.WriteFile(path, value, opts?)` | | Encode and write UTF-8 (no BOM) |

### 🟣 JSON bridge

| Call | Returns | Description |
|---|---|---|
| `Toon.FromJson(jsonText, opts?)` | TOON text | JSON to TOON (`true`, `false` and `null` are preserved) |
| `Toon.ToJson(toonText, indent := 2, opts?)` | JSON text | TOON to JSON |
| `Toon.JsonParse(jsonText, literals := false)` | value | Stand-alone JSON parser |
| `Toon.JsonStringify(value, indent := 0)` | string | Stand-alone JSON writer (`indent` 0 = compact) |

### 🟠 Helpers

| Call | Description |
|---|---|
| `Toon.Get(data, "users[0].name", default?)` | Path accessor. Returns `default` (or `""`) when the path does not exist |
| `Toon.Null` · `Toon.TrueV` · `Toon.FalseV` | Sentinels for lossless null and boolean values |
| `Toon.OMap(k1, v1, k2, v2, ...)` | Insertion-ordered Map |
| `Toon.ParseError` | Error class thrown on invalid input (has a `.Line` property) |

---

## ⚙️ Options

Options can be an object literal `{strict: false}` or a `Map("strict", false)`.

### 🔵 Decode options

| Option | Default | Values | Effect |
|---|---|---|---|
| `strict` | `true` | `true` / `false` | Validate counts, indentation, tabs and blank lines |
| `indent` | `2` | integer ≥ 1 | Spaces per indentation level |
| `expandPaths` | `"off"` | `"off"` / `"safe"` | Expand unquoted dotted keys (`a.b.c`) into nested objects |
| `literals` | `false` | `true` / `false` | Return `Toon.TrueV`, `Toon.FalseV` and `Toon.Null` instead of `1`, `0` and `""` |

### 🟢 Encode options

| Option | Default | Values | Effect |
|---|---|---|---|
| `indent` | `2` | integer ≥ 1 | Spaces per indentation level |
| `delimiter` | `","` | `","` `"\|"` `"`t"` (or `"comma"` `"pipe"` `"tab"`) | Delimiter for arrays and tables |
| `keyFolding` | `"off"` | `"off"` / `"safe"` | Fold single-key object chains into `a.b.c: 1` |
| `flattenDepth` | unlimited | integer | Maximum number of segments to fold |

---

## 🧬 Value model

| TOON | ➡️ Decoded as (default) | ➡️ With `literals: true` | ⬅️ Accepted when encoding |
|---|---|---|---|
| object | `Toon.OMap` | `Toon.OMap` | `Toon.OMap`, `Map`, plain `{}` object |
| array | `Array` | `Array` | `Array` |
| string | `String` | `String` | `String` |
| integer | `Integer` | `Integer` | `Integer` |
| decimal | `Float` | `Float` | `Float` |
| `true` / `false` | `1` / `0` | `Toon.TrueV` / `Toon.FalseV` | `Toon.TrueV` / `Toon.FalseV` |
| `null` | `""` | `Toon.Null` | `Toon.Null` |

> [!IMPORTANT]
> AutoHotkey has no real boolean or null type. If you need `true`, `false` and `null` to survive an encode and decode round trip, use `literals: true` and the `Toon.TrueV`, `Toon.FalseV` and `Toon.Null` sentinels. In that mode the decoded `true` is the object `Toon.TrueV`, not the number `1`, so compare with `data["flag"] == Toon.TrueV` instead of using it directly in an `if`.

> [!NOTE]
> Non-finite floats (NaN, ±Infinity) are encoded as `null`, and `-0` is written as `0`.

---

## 🧪 Examples

### 🟢 Example 1: Encode nested data

```ahk
data := Toon.OMap(
    "context", Toon.OMap("task", "Our favorite hikes", "location", "Boulder"),
    "friends", ["ana", "luis", "sam"],
    "hikes", [
        Toon.OMap("id", 1, "name", "Blue Lake Trail", "distanceKm", 7.5, "wasSunny", Toon.TrueV),
        Toon.OMap("id", 2, "name", "Ridge Overlook",  "distanceKm", 9.2, "wasSunny", Toon.FalseV)
    ]
)
MsgBox Toon.Stringify(data)
```

```toon
context:
  task: Our favorite hikes
  location: Boulder
friends[3]: ana,luis,sam
hikes[2]{id,name,distanceKm,wasSunny}:
  1,Blue Lake Trail,7.5,true
  2,Ridge Overlook,9.2,false
```

### 🔵 Example 2: Parse and navigate

```ahk
text := "
(
user:
  id: 123
  name: Ada
  tags[2]: admin,ops
)"
data := Toon.Parse(text)

MsgBox data["user"]["name"]                       ; Ada
MsgBox Toon.Get(data, "user.tags[1]")             ; ops  (zero-based index in the path)
MsgBox Toon.Get(data, "user.missing", "n/a")      ; n/a
```

> [!TIP]
> Indexes inside `Toon.Get` paths are **zero-based** (`tags[0]` is the first item). Real AutoHotkey arrays are one-based (`data["user"]["tags"][1]`).

### 🟡 Example 3: Different delimiters

```ahk
MsgBox Toon.Stringify(data, {delimiter: "|"})
```

```toon
friends[3|]: ana|luis|sam
hikes[2|]{id|name|distanceKm|wasSunny}:
  1|Blue Lake Trail|7.5|true
  2|Ridge Overlook|9.2|false
```

Tab-separated works the same way: `{delimiter: "tab"}`.

### 🟣 Example 4: Mixed and nested arrays

```ahk
data := Toon.OMap("mixed", [1, Toon.OMap("a", 1, "b", [2, 3]), ["x", "y"]])
MsgBox Toon.Stringify(data)
```

```toon
mixed[3]:
  - 1
  - a: 1
    b[2]: 2,3
  - [2]: x,y
```

### 🟤 Example 5: Key folding and path expansion

```ahk
cfg := Toon.OMap("server", Toon.OMap("http", Toon.OMap("port", 8080)))

folded := Toon.Stringify(cfg, {keyFolding: "safe"})
MsgBox folded                       ; server.http.port: 8080

back := Toon.Parse(folded, {expandPaths: "safe"})
MsgBox back["server"]["http"]["port"]   ; 8080
```

### 🔶 Example 6: JSON in, TOON out (and back)

```ahk
json := '{"users":[{"id":1,"name":"Ada"},{"id":2,"name":"Linus"}],"active":true}'

toon := Toon.FromJson(json)
MsgBox toon
```

```toon
users[2]{id,name}:
  1,Ada
  2,Linus
active: true
```

```ahk
MsgBox Toon.ToJson(toon, 2)        ; pretty JSON, 2-space indent
MsgBox Toon.ToJson(toon, 0)        ; compact JSON
```

### 📁 Example 7: Files

```ahk
data := Toon.ParseFile(A_ScriptDir "\config.toon")
data["lastRun"] := FormatTime(, "yyyy-MM-dd")
Toon.WriteFile(A_ScriptDir "\config.toon", data)
```

### 🔴 Example 8: Handling errors

```ahk
try {
    Toon.Parse("tags[3]: a,b")           ; declared 3, found 2
} catch Toon.ParseError as e {
    MsgBox e.Message "`nLine: " e.Line
}
```

```text
TOON parse error (line 1): Expected 3 array items, got 2
```

### 🔷 Example 9: Lossless booleans and null

```ahk
data := Toon.Parse("ok: true`nmissing: null", {literals: true})

MsgBox (data["ok"] == Toon.TrueV)        ; 1
MsgBox (data["missing"] == Toon.Null)    ; 1
MsgBox Toon.Stringify(data)              ; ok: true / missing: null
```

---

## 🛡️ Strict mode and errors

`strict` is **on by default**. It makes the parser reject malformed input instead of guessing.

| 🔍 Check | 🟢 Strict | 🟡 Non-strict |
|---|---|---|
| Declared `[N]` differs from the actual item or row count | ❌ error | accepted |
| Row has the wrong number of values | ❌ error | missing values become `null` |
| Indentation is not a multiple of `indent` | ❌ error | accepted |
| Tab characters in indentation | ❌ error | accepted |
| Blank line inside an array | ❌ error | ignored |
| Extra rows or items after the declared count | ❌ error | ignored |

> [!WARNING]
> Turn strict mode off (`{strict: false}`) only for hand-written or machine-generated TOON you do not control. Strict mode is what catches truncated or corrupted data.

Errors are thrown as **`Toon.ParseError`** (a subclass of `Error`) with:

| Property | Meaning |
|---|---|
| `Message` | Human readable message, prefixed with the line number |
| `Line` | 1-based line number of the problem |

---

## 🧱 The `Toon.OMap` class

TOON object field order matters (it defines table headers), but a plain AutoHotkey `Map` iterates in sorted key order. **`Toon.OMap`** is a `Map` subclass that remembers insertion order.

```ahk
o := Toon.OMap("b", 1, "a", 2)
o["c"] := 3

for k, v in o
    MsgBox k " = " v       ; b, a, c  (insertion order)

MsgBox o.Count             ; 3
MsgBox o.Has("a")          ; 1
o.Delete("b")
keys := o.Keys()           ; ["a", "c"]
copy := o.Clone()
```

It supports the full `Map` interface: `Set`, `Get`, `Has`, `Delete`, `Clear`, `Count`, `Clone` and `for` loops.

---

## ⚠️ Limitations

> [!CAUTION]
> Please read these before relying on the library for exact data fidelity.

- 🔸 Integers with more than 18 characters (including the sign) are decoded as `Float`, so precision may be lost.
- 🔸 In the default decode mode `true`, `false` and `null` become `1`, `0` and `""`. Use `literals: true` for lossless handling.
- 🔸 Strings that contain control characters other than `\n`, `\r` and `\t` are written inside quotes without an escape, because the TOON format only defines five escapes.
- 🔸 Unquoted keys are matched with an ASCII pattern (`A-Z a-z 0-9 _ .`). Other keys are written in quotes.
- 🔸 Encoding plain objects uses `OwnProps()`, so only own properties are written.
- 🔸 `Toon.Get` paths address maps and arrays only.

---

## 🩺 Troubleshooting

| 🐞 Symptom | 💡 Cause and fix |
|---|---|
| `Property is read-only` on a class property or method | AutoHotkey names are **case-insensitive**. Two members that differ only by case (for example `_lit` and `_Lit`) collide. Rename one. |
| `This value of type "String" has no method named ...` when calling `Toon.Something` | A local variable or parameter named `toon` (any case) **shadows the `Toon` class**. Rename your variable. |
| Parse error: `Indentation must be a multiple of 2` | Your file uses a different indent width. Pass `{indent: 4}`, or fix the file. |
| Parse error: `Expected N rows, got M` | The `[N]` in the header does not match the rows. Fix the number, or use `{strict: false}`. |
| Multi-line strings lose their indentation | Continuation sections `"( ... )"` can strip leading whitespace. Build the text with `"line1`nline2"` for exact control. |
| Keys come out in sorted order | You are using a plain `Map`. Use `Toon.OMap` to keep insertion order. |
| `true` shows up as `1` | That is the default decode mode. Use `{literals: true}`. |

---

## 🤝 Contributing

Issues and pull requests are welcome. When reporting a parsing problem, please include:

1. 📄 the smallest TOON text that reproduces it
2. 🧾 the exact error message and line number
3. 🖥️ your AutoHotkey version (`A_AhkVersion`)

---

## 📄 License

Add the license of your choice (for example MIT) as a `LICENSE` file and update the badge below.

![License](https://img.shields.io/badge/license-your_choice-lightgrey?style=flat-square)

<div align="center">

Made with 💚 for AutoHotkey v2

</div>
