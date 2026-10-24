#Requires AutoHotkey v2
; =============================================================================
;  Toon.ahk  -  TOON (Token-Oriented Object Notation) encoder / parser
;               for AutoHotkey v2.0.30
; =============================================================================
;  TOON is a compact, indentation based, human readable JSON alternative that
;  is designed to use fewer tokens when data is sent to LLMs.
;
;  Supported TOON features
;    - objects by indentation            key: value
;    - inline primitive arrays           tags[3]: a,b,c
;    - tabular arrays of objects         users[2]{id,name}:  (rows below)
;    - list arrays (mixed / nested)      items[2]:  "- ..." lines
;    - arrays of arrays, empty arrays, empty objects, root arrays/primitives
;    - delimiters: comma (default), tab, pipe     e.g. tags[3|]: a|b|c
;    - quoting / escaping rules  (\\  \"  \n  \r  \t)
;    - strict mode validation (counts, indentation, blank lines)
;    - key folding (encode) and path expansion (decode):  a.b.c: 1
;
;  PUBLIC API
;    Toon.Parse(text, opts?)         -> value        (alias: Toon.Decode)
;    Toon.Stringify(value, opts?)    -> TOON text    (alias: Toon.Encode)
;    Toon.ParseFile(path, opts?)     -> value
;    Toon.WriteFile(path, value, opts?)
;    Toon.FromJson(jsonText, opts?)  -> TOON text
;    Toon.ToJson(toonText, indent := 2, opts?) -> JSON text
;    Toon.JsonParse(jsonText, literals := false)
;    Toon.JsonStringify(value, indent := 0)
;    Toon.Get(data, "users[0].name", default?)   path accessor
;
;  VALUE MODEL (what Parse returns / Stringify accepts)
;    object     -> Toon.OMap  (insertion-ordered Map; plain Map/Object also ok)
;    array      -> Array
;    string     -> String
;    number     -> Integer / Float
;    true/false -> 1 / 0        (or Toon.TrueV / Toon.FalseV  if literals:true)
;    null       -> ""           (or Toon.Null                 if literals:true)
;
;  DECODE OPTIONS  (Map or object literal):
;    strict      true   validate counts, indentation, blank lines
;    indent      2      spaces per level
;    expandPaths "off"  "safe" expands unquoted dotted keys (a.b -> nested)
;    literals    false  return Toon.TrueV/FalseV/Null sentinels
;
;  ENCODE OPTIONS:
;    indent        2        spaces per level
;    delimiter     ","      "," | "`t" | "|"   (or "comma" / "tab" / "pipe")
;    keyFolding    "off"    "safe" folds single-key chains into a.b.c: 1
;    flattenDepth  (no limit) max segments folded
; =============================================================================

class Toon {

    ; ------------------------------------------------------------------ API --
    static Parse(text, opts := "") => Toon._Decoder(text, opts).Run()
    static Decode(text, opts := "") => Toon._Decoder(text, opts).Run()
    static Stringify(value, opts := "") => Toon._Encoder(opts).Run(value)
    static Encode(value, opts := "") => Toon._Encoder(opts).Run(value)

    static ParseFile(path, opts := "") => Toon.Parse(FileRead(path, "UTF-8"), opts)

    static WriteFile(path, value, opts := "") {
        f := FileOpen(path, "w", "UTF-8-RAW")
        f.Write(Toon.Stringify(value, opts))
        f.Close()
    }

    static FromJson(json, opts := "") => Toon.Stringify(Toon.JsonParse(json, true), opts)

    static ToJson(toonText, indent := 2, opts := "") {
        return Toon.JsonStringify(Toon._Decoder(toonText, opts, true).Run(), indent)
    }

    static JsonParse(json, literals := false) => Toon._JsonParser(json, literals).Run()
    static JsonStringify(value, indent := 0) => Toon._JD(value, indent, 0)

    ; Path accessor:  Toon.Get(data, "users[0].name", "n/a")
    static Get(root, path, def := "") {
        cur := root
        pos := 1
        len := StrLen(path)
        while pos <= len && RegExMatch(path, "[^.\[\]]+|\[\d+\]", &m, pos) {
            seg := m[0]
            pos := m.Pos + m.Len[0]
            if SubStr(seg, 1, 1) == "[" {
                i := Integer(SubStr(seg, 2, StrLen(seg) - 2)) + 1
                if !(cur is Array) || i > cur.Length
                    return def
                cur := cur[i]
            } else {
                if !(cur is Map) || !cur.Has(seg)
                    return def
                cur := cur[seg]
            }
        }
        return cur
    }

    ; --------------------------------------------------------- literals ------
    static Null => Toon._Lit("null")
    static TrueV => Toon._Lit("true")
    static FalseV => Toon._Lit("false")

    static _litCache := ""
    static _Lit(name) {
        if !IsObject(Toon._litCache)
            Toon._litCache := Map()
        if !Toon._litCache.Has(name)
            Toon._litCache[name] := Toon.Literal(name)
        return Toon._litCache[name]
    }

    class Literal {
        __New(name) {
            this.Name := name
        }
        ToString() => this.Name
    }

    class ParseError extends Error {
        Line := 0
    }

    ; ------------------------------------------------ ordered Map (objects) --
    class OMap extends Map {
        _order := []

        __New(Pairs*) {
            this.Set(Pairs*)
        }

        Set(Pairs*) {
            Loop Pairs.Length // 2 {
                k := Pairs[A_Index * 2 - 1]
                v := Pairs[A_Index * 2]
                if !super.Has(k)
                    this._order.Push(k)
                super.Set(k, v)
            }
            return this
        }

        __Item[key] {
            get => super.Get(key)
            set => this.Set(key, value)
        }

        Delete(key) {
            for i, k in this._order {
                if k == key {
                    this._order.RemoveAt(i)
                    break
                }
            }
            return super.Delete(key)
        }

        Clear() {
            super.Clear()
            this._order := []
        }

        Clone() {
            c := Toon.OMap()
            for k, v in this
                c.Set(k, v)
            return c
        }

        Keys() => this._order.Clone()

        __Enum(n) {
            o := this
            i := 0
            if n == 1
                return (&k) => (++i <= o._order.Length ? (k := o._order[i], true) : false)
            return (&k, &v) => (++i <= o._order.Length ? (k := o._order[i], v := o[k], true) : false)
        }
    }

    ; --------------------------------------------------------- utilities -----
    static _Opt(o, k, d) {
        if !IsObject(o)
            return d
        if o is Map
            return o.Has(k) ? o[k] : d
        return HasProp(o, k) ? o.%k% : d
    }

    static _Rep(str, n) {
        out := ""
        Loop n
            out .= str
        return out
    }

    static _Join(a, sep) {
        s := ""
        for i, x in a
            s .= (i > 1 ? sep : "") . x
        return s
    }

    static _SafeSeg(s) => RegExMatch(s, "^[A-Za-z_][A-Za-z0-9_]*$")

    static _Esc(s) {
        s := StrReplace(s, "\", "\\")
        s := StrReplace(s, '"', '\"')
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, "`r", "\r")
        s := StrReplace(s, "`t", "\t")
        return s
    }

    static _NeedsQuote(s, delim) {
        if s == ""
            return true
        if s == "true" || s == "false" || s == "null"
            return true
        if RegExMatch(s, "^\s|\s$")
            return true
        if SubStr(s, 1, 1) == "-"
            return true
        if InStr(s, delim)
            return true
        if RegExMatch(s, '[:"\\\[\]{}\x00-\x1F\x7F]')
            return true
        if RegExMatch(s, "^-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?$")
            return true
        return false
    }

    static _Num(tok) {
        if RegExMatch(tok, "^-?\d+$") {
            if StrLen(tok) <= 18
                return Integer(tok)
            return Float(tok)
        }
        tok := RegExReplace(tok, "^(-?\d+)([eE])", "$1.0$2")
        f := Float(tok)
        return f == 0 ? 0 : f
    }

    static _FmtFloat(f) {
        if f != f
            return "null"
        if f == 0
            return "0"
        if Abs(f) > 1.7976931348623157e308
            return "null"
        s := String(f)
        if InStr(s, "e")
            return Toon._ExpandExp(s)
        if InStr(s, ".")
            s := RTrim(RTrim(s, "0"), ".")
        return s
    }

    static _ExpandExp(s) {
        if !RegExMatch(s, "i)^(-?)(\d+)(?:\.(\d+))?e([+-]?\d+)$", &m)
            return s
        digits := m[2] . m[3]
        point := StrLen(m[2]) + Integer(m[4])
        if point <= 0
            r := "0." . Toon._Rep("0", -point) . digits
        else if point >= StrLen(digits)
            r := digits . Toon._Rep("0", point - StrLen(digits))
        else
            r := SubStr(digits, 1, point) . "." . SubStr(digits, point + 1)
        if InStr(r, ".")
            r := RTrim(RTrim(r, "0"), ".")
        return m[1] . r
    }

    ; =========================================================================
    ;  ENCODER
    ; =========================================================================
    class _Encoder {
        __New(opts) {
            ind := Toon._Opt(opts, "indent", 2)
            if !(ind is Integer) || ind < 1
                throw ValueError("TOON: 'indent' must be a positive integer")
            this.unit := Toon._Rep(" ", ind)
            d := Toon._Opt(opts, "delimiter", ",")
            if d = "comma"
                d := ","
            else if d = "tab"
                d := "`t"
            else if d = "pipe"
                d := "|"
            if !(d == "," || d == "`t" || d == "|")
                throw ValueError("TOON: 'delimiter' must be comma, tab or pipe")
            this.delim := d
            this.marker := (d == ",") ? "" : d
            this.foldOn := (Toon._Opt(opts, "keyFolding", "off") = "safe")
            this.flat := Toon._Opt(opts, "flattenDepth", 1000000)
            this.lines := []
            this.cache := Map()
        }

        _I(n) {
            if !this.cache.Has(n)
                this.cache[n] := Toon._Rep(this.unit, n)
            return this.cache[n]
        }

        Run(v) {
            k := this.Kind(v)
            if k == "prim"
                return this.Prim(v)
            if k == "array"
                this.Arr("", v, 0, 1, "")
            else
                this.ObjBody(v, 0)
            return Toon._Join(this.lines, "`n")
        }

        Kind(v) {
            if !IsObject(v)
                return "prim"
            if v is Toon.Literal
                return "prim"
            if v is Array
                return "array"
            if v is Func
                throw TypeError("TOON: cannot encode a function")
            return "obj"
        }

        Entries(v) {
            res := []
            if v is Map {
                for k, val in v
                    res.Push([String(k), val])
            } else {
                for k, val in v.OwnProps()
                    res.Push([k, val])
            }
            return res
        }

        Prim(v) {
            if v is Toon.Literal
                return v.Name
            if v is Integer
                return String(v)
            if v is Float
                return Toon._FmtFloat(v)
            return this.Str(String(v))
        }

        Str(s) {
            if Toon._NeedsQuote(s, this.delim)
                return '"' . Toon._Esc(s) . '"'
            return s
        }

        Key(k) {
            if RegExMatch(k, "^[A-Za-z_][A-Za-z0-9_.]*$")
                return k
            return '"' . Toon._Esc(k) . '"'
        }

        ; Key folding: a: {b: {c: 1}}  ->  a.b.c: 1
        FoldKey(key, val, sib) {
            ks := this.Key(key)
            if !this.foldOn || this.flat < 2 || !Toon._SafeSeg(key)
                return [ks, val]
            segs := [key]
            cur := val
            while segs.Length < this.flat {
                if this.Kind(cur) != "obj"
                    break
                e := this.Entries(cur)
                if e.Length != 1 || !Toon._SafeSeg(e[1][1])
                    break
                segs.Push(e[1][1])
                cur := e[1][2]
            }
            if segs.Length == 1
                return [ks, val]
            full := Toon._Join(segs, ".")
            if sib.Has(full)
                return [ks, val]
            return [full, cur]
        }

        ObjBody(v, depth) {
            e := this.Entries(v)
            sib := Map()
            for p in e
                sib[p[1]] := true
            for p in e
                this.Field(p[1], p[2], depth, "", depth + 1, sib)
        }

        ; depth = indent of the line, leader = "- " for list-item first field,
        ; nest = indent of nested content
        Field(key, val, depth, leader, nest, sib) {
            f := this.FoldKey(key, val, sib)
            ks := f[1]
            v := f[2]
            k := this.Kind(v)
            pre := this._I(depth) . leader
            if k == "prim" {
                this.lines.Push(pre . ks . ": " . this.Prim(v))
            } else if k == "array" {
                this.Arr(ks, v, depth, nest, leader)
            } else {
                this.lines.Push(pre . ks . ":")
                if this.Entries(v).Length
                    this.ObjBody(v, nest)
            }
        }

        Arr(keyStr, arr, depth, nest, leader) {
            n := arr.Length
            head := this._I(depth) . leader . keyStr . "[" . n . this.marker . "]"
            if n == 0 {
                this.lines.Push(head . ":")
                return
            }
            allPrim := true
            for x in arr {
                if this.Kind(x) != "prim" {
                    allPrim := false
                    break
                }
            }
            if allPrim {
                vals := []
                for x in arr
                    vals.Push(this.Prim(x))
                this.lines.Push(head . ": " . Toon._Join(vals, this.delim))
                return
            }
            fields := this.TabFields(arr, &rows)
            if fields is Array {
                names := []
                for f in fields
                    names.Push(this.Key(f))
                this.lines.Push(head . "{" . Toon._Join(names, this.delim) . "}:")
                pre := this._I(nest)
                for r in rows {
                    vals := []
                    for f in fields
                        vals.Push(this.Prim(r[f]))
                    this.lines.Push(pre . Toon._Join(vals, this.delim))
                }
                return
            }
            this.lines.Push(head . ":")
            pre := this._I(nest)
            for x in arr {
                k := this.Kind(x)
                if k == "prim"
                    this.lines.Push(pre . "- " . this.Prim(x))
                else if k == "array"
                    this.Arr("", x, nest, nest + 1, "- ")
                else
                    this.ListObj(x, nest)
            }
        }

        ; Returns the field list when every element is an object with the same
        ; keys and only primitive values (tabular form), else false.
        TabFields(arr, &rows) {
            rows := []
            if this.Kind(arr[1]) != "obj"
                return false
            fe := this.Entries(arr[1])
            if fe.Length == 0
                return false
            fields := []
            for p in fe
                fields.Push(p[1])
            for x in arr {
                if this.Kind(x) != "obj"
                    return false
                e := this.Entries(x)
                if e.Length != fields.Length
                    return false
                m := Map()
                for p in e
                    m[p[1]] := p[2]
                for f in fields {
                    if !m.Has(f) || this.Kind(m[f]) != "prim"
                        return false
                }
                rows.Push(m)
            }
            return fields
        }

        ListObj(obj, itemDepth) {
            e := this.Entries(obj)
            if e.Length == 0 {
                this.lines.Push(this._I(itemDepth) . "-")
                return
            }
            sib := Map()
            for p in e
                sib[p[1]] := true
            this.Field(e[1][1], e[1][2], itemDepth, "- ", itemDepth + 2, sib)
            Loop e.Length - 1 {
                p := e[A_Index + 1]
                this.Field(p[1], p[2], itemDepth + 1, "", itemDepth + 2, sib)
            }
        }
    }

    ; =========================================================================
    ;  DECODER
    ; =========================================================================
    class _Decoder {
        __New(text, opts, forceLit := false) {
            this.strict := !!Toon._Opt(opts, "strict", true)
            this.indent := Toon._Opt(opts, "indent", 2)
            if !(this.indent is Integer) || this.indent < 1
                throw ValueError("TOON: 'indent' must be a positive integer")
            this.expand := (Toon._Opt(opts, "expandPaths", "off") = "safe")
            this.lit := forceLit || !!Toon._Opt(opts, "literals", false)
            this.NullV := this.lit ? Toon.Null : ""
            this.lines := []
            this.idx := 1
            this.Scan(String(text))
        }

        Err(msg, num) {
            e := Toon.ParseError("TOON parse error (line " . num . "): " . msg)
            e.Line := num
            throw e
        }

        ; split the document into {d: depth, t: content, n: line no, b: blank before}
        Scan(text) {
            if SubStr(text, 1, 1) == Chr(0xFEFF)
                text := SubStr(text, 2)
            text := StrReplace(StrReplace(text, "`r`n", "`n"), "`r", "`n")
            blank := false
            for i, raw in StrSplit(text, "`n") {
                if Trim(raw, " `t") == "" {
                    blank := true
                    continue
                }
                RegExMatch(raw, "^( *)", &m)
                sp := StrLen(m[1])
                if this.strict {
                    if RegExMatch(raw, "^ *`t")
                        this.Err("Tabs are not allowed in indentation", i)
                    if Mod(sp, this.indent) != 0
                        this.Err("Indentation must be a multiple of " . this.indent, i)
                }
                this.lines.Push({d: sp // this.indent, t: RTrim(SubStr(raw, sp + 1), " "), n: i, b: blank})
                blank := false
            }
        }

        Run() {
            L := this.lines
            if L.Length == 0
                return Toon.OMap()
            first := L[1]
            if first.d != 0
                this.Err("Unexpected indentation at start of document", first.n)
            t := first.t
            if SubStr(t, 1, 1) == "[" && RegExMatch(t, "^\[#?\d+[\t|]?\]") {
                this.idx := 2
                h := this.Header(t, first.n)
                result := this.ArrayBody(h, 0, first.n)
            } else if L.Length == 1 && !this.Colon(t, first.n) {
                this.idx := 2
                result := this.Prim(t, first.n)
            } else {
                result := this.Obj(0)
            }
            if this.idx <= L.Length
                this.Err("Unexpected content", L[this.idx].n)
            return result
        }

        Obj(depth) {
            obj := Toon.OMap()
            L := this.lines
            while this.idx <= L.Length {
                cur := L[this.idx]
                if cur.d < depth
                    break
                if cur.d > depth
                    this.Err("Unexpected indentation", cur.n)
                this.idx++
                this.Field(cur.t, depth, obj, cur.n)
            }
            return obj
        }

        ; parse "key: value", "key:" (nested) or "key[N]...: ..." into obj
        ; fieldDepth = depth at which sibling fields live
        Field(text, fieldDepth, obj, num) {
            quoted := false
            if SubStr(text, 1, 1) == '"' {
                r := this.Quoted(text, 1, num)
                key := r[1]
                p := r[2]
                quoted := true
            } else {
                p := RegExMatch(text, "[:\[]")
                if !p
                    this.Err("Missing colon after key", num)
                key := RTrim(SubStr(text, 1, p - 1), " ")
                if key == ""
                    this.Err("Empty key", num)
            }
            rest := SubStr(text, p)
            c := SubStr(rest, 1, 1)
            if c == "[" {
                h := this.Header(rest, num)
                val := this.ArrayBody(h, fieldDepth, num)
            } else if c == ":" {
                v := Trim(SubStr(rest, 2), " ")
                if v == "" {
                    L := this.lines
                    if this.idx <= L.Length && L[this.idx].d > fieldDepth
                        val := this.Obj(fieldDepth + 1)
                    else
                        val := Toon.OMap()
                } else {
                    val := this.Prim(v, num)
                }
            } else {
                this.Err("Missing colon after key", num)
            }
            this.Insert(obj, key, quoted, val, num)
        }

        ; s starts at "[": parses [N<delim>]{fields}: inline
        Header(s, num) {
            if !RegExMatch(s, "^\[#?(\d+)([\t|]?)\]", &m)
                this.Err("Invalid array header", num)
            count := Integer(m[1])
            delim := (m[2] == "") ? "," : m[2]
            p := m.Len[0] + 1
            fields := false
            if SubStr(s, p, 1) == "{" {
                q := p + 1
                inQ := false
                Loop {
                    if q > StrLen(s)
                        this.Err("Unterminated field list", num)
                    ch := SubStr(s, q, 1)
                    if inQ {
                        if ch == "\"
                            q++
                        else if ch == '"'
                            inQ := false
                    } else if ch == '"' {
                        inQ := true
                    } else if ch == "}" {
                        break
                    }
                    q++
                }
                inner := SubStr(s, p + 1, q - p - 1)
                fields := []
                for tok in this.Split(inner, delim)
                    fields.Push(this.KeyTok(tok, num))
                p := q + 1
            }
            if SubStr(s, p, 1) != ":"
                this.Err("Missing colon after array header", num)
            return {n: count, d: delim, f: fields, a: Trim(SubStr(s, p + 1), " ")}
        }

        KeyTok(tok, num) {
            tok := Trim(tok, " ")
            if SubStr(tok, 1, 1) == '"' {
                r := this.Quoted(tok, 1, num)
                if r[2] <= StrLen(tok)
                    this.Err("Unexpected characters after closing quote", num)
                return r[1]
            }
            return tok
        }

        ; fieldDepth = depth of the line that holds the header
        ArrayBody(h, fieldDepth, num) {
            if h.a != "" {
                if h.f
                    this.Err("Tabular array header cannot have inline values", num)
                arr := []
                for t in this.Split(h.a, h.d)
                    arr.Push(this.Prim(t, num))
                if this.strict && arr.Length != h.n
                    this.Err("Expected " . h.n . " array items, got " . arr.Length, num)
                return arr
            }
            if h.n == 0
                return []
            if h.f
                return this.Tabular(h, fieldDepth + 1, num)
            return this.List(h, fieldDepth + 1, num)
        }

        Tabular(h, depth, num) {
            L := this.lines
            f := h.f
            w := f.Length
            rows := []
            while this.idx <= L.Length && rows.Length < h.n {
                cur := L[this.idx]
                if cur.d != depth
                    break
                if this.strict && cur.b
                    this.Err("Blank line inside array", cur.n)
                this.idx++
                toks := this.Split(cur.t, h.d)
                if this.strict && toks.Length != w
                    this.Err("Expected " . w . " values per row, got " . toks.Length, cur.n)
                o := Toon.OMap()
                Loop w
                    o[f[A_Index]] := (A_Index <= toks.Length) ? this.Prim(toks[A_Index], cur.n) : this.NullV
                rows.Push(o)
            }
            if this.strict {
                if rows.Length != h.n
                    this.Err("Expected " . h.n . " rows, got " . rows.Length, num)
                if this.idx <= L.Length && L[this.idx].d == depth
                    this.Err("Too many rows (expected " . h.n . ")", L[this.idx].n)
            }
            return rows
        }

        List(h, depth, num) {
            L := this.lines
            arr := []
            while this.idx <= L.Length && arr.Length < h.n {
                cur := L[this.idx]
                if cur.d != depth
                    break
                if !(cur.t == "-" || SubStr(cur.t, 1, 2) == "- ") {
                    if this.strict
                        this.Err("Expected list item starting with '-'", cur.n)
                    break
                }
                if this.strict && cur.b
                    this.Err("Blank line inside array", cur.n)
                this.idx++
                arr.Push(this.ListItem(cur, depth))
            }
            if this.strict {
                if arr.Length != h.n
                    this.Err("Expected " . h.n . " items, got " . arr.Length, num)
                if this.idx <= L.Length {
                    nx := L[this.idx]
                    if nx.d == depth && (nx.t == "-" || SubStr(nx.t, 1, 2) == "- ")
                        this.Err("Too many items (expected " . h.n . ")", nx.n)
                }
            }
            return arr
        }

        ListItem(row, itemDepth) {
            t := row.t
            num := row.n
            if t == "-"
                return Toon.OMap()
            content := LTrim(SubStr(t, 3), " ")
            if content == ""
                return Toon.OMap()
            if RegExMatch(content, "^\[#?\d+[\t|]?\]") {
                h := this.Header(content, num)
                return this.ArrayBody(h, itemDepth, num)
            }
            if !this.Colon(content, num)
                return this.Prim(content, num)
            obj := Toon.OMap()
            this.Field(content, itemDepth + 1, obj, num)
            L := this.lines
            while this.idx <= L.Length {
                nx := L[this.idx]
                if nx.d != itemDepth + 1
                    break
                this.idx++
                this.Field(nx.t, itemDepth + 1, obj, nx.n)
            }
            return obj
        }

        Prim(tok, num) {
            tok := Trim(tok, " ")
            if tok == ""
                return ""
            if SubStr(tok, 1, 1) == '"' {
                r := this.Quoted(tok, 1, num)
                if r[2] <= StrLen(tok)
                    this.Err("Unexpected characters after closing quote", num)
                return r[1]
            }
            if tok == "true"
                return this.lit ? Toon.TrueV : 1
            if tok == "false"
                return this.lit ? Toon.FalseV : 0
            if tok == "null"
                return this.NullV
            if RegExMatch(tok, "^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$")
                return Toon._Num(tok)
            return tok
        }

        ; s[p] is the opening quote; returns [value, position after closing quote]
        Quoted(s, p, num) {
            static esc := Map("n", "`n", "r", "`r", "t", "`t", "\", "\", '"', '"')
            out := ""
            i := p + 1
            Loop {
                if !RegExMatch(s, '["\\]', &m, i)
                    this.Err("Unterminated string", num)
                j := m.Pos
                out .= SubStr(s, i, j - i)
                if SubStr(s, j, 1) == '"'
                    return [out, j + 1]
                c := SubStr(s, j + 1, 1)
                if !esc.Has(c)
                    this.Err("Invalid escape sequence '\" . c . "'", num)
                out .= esc[c]
                i := j + 2
            }
        }

        ; split on a delimiter, ignoring delimiters inside quotes
        Split(str, delim) {
            if !InStr(str, '"')
                return StrSplit(str, delim)
            res := []
            cur := ""
            inQ := false
            i := 1
            L := StrLen(str)
            while i <= L {
                ch := SubStr(str, i, 1)
                if inQ {
                    cur .= ch
                    if ch == "\" {
                        i++
                        cur .= SubStr(str, i, 1)
                    } else if ch == '"' {
                        inQ := false
                    }
                } else if ch == '"' {
                    inQ := true
                    cur .= ch
                } else if ch == delim {
                    res.Push(cur)
                    cur := ""
                } else {
                    cur .= ch
                }
                i++
            }
            res.Push(cur)
            return res
        }

        ; position of the first unquoted colon, or 0
        Colon(text, num) {
            p := 1
            while RegExMatch(text, '[:"]', &m, p) {
                if SubStr(text, m.Pos, 1) == ":"
                    return m.Pos
                p := this.Quoted(text, m.Pos, num)[2]
            }
            return 0
        }

        Insert(obj, key, quoted, val, num) {
            if this.expand && !quoted && InStr(key, ".")
                && RegExMatch(key, "^[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+$") {
                segs := StrSplit(key, ".")
                cur := obj
                Loop segs.Length - 1 {
                    s := segs[A_Index]
                    if cur.Has(s) && (cur[s] is Toon.OMap) {
                        cur := cur[s]
                    } else {
                        if cur.Has(s) && this.strict
                            this.Err("Path expansion conflict at '" . s . "'", num)
                        nxt := Toon.OMap()
                        cur[s] := nxt
                        cur := nxt
                    }
                }
                this.Put(cur, segs[segs.Length], val, num)
            } else {
                this.Put(obj, key, val, num)
            }
        }

        Put(obj, key, val, num) {
            if this.expand && obj.Has(key) {
                old := obj[key]
                if (old is Toon.OMap) && (val is Toon.OMap) {
                    for k, v in val
                        this.Put(old, k, v, num)
                    return
                }
                if this.strict
                    this.Err("Path expansion conflict at '" . key . "'", num)
            }
            obj[key] := val
        }
    }

    ; =========================================================================
    ;  JSON bridge (small, dependency free)
    ; =========================================================================
    class _JsonParser {
        __New(s, lit) {
            this.s := s
            this.p := 1
            this.n := StrLen(s)
            this.lit := lit
        }

        Fail(msg) {
            throw Toon.ParseError("JSON parse error at position " . this.p . ": " . msg)
        }

        Run() {
            v := this.Value()
            this.Ws()
            if this.p <= this.n
                this.Fail("Unexpected trailing characters")
            return v
        }

        Ws() {
            if RegExMatch(this.s, "[^ \t\r\n]", &m, this.p)
                this.p := m.Pos
            else
                this.p := this.n + 1
        }

        Value() {
            this.Ws()
            c := SubStr(this.s, this.p, 1)
            if c == "{"
                return this.Obj()
            if c == "["
                return this.Arr()
            if c == '"'
                return this.Str()
            if SubStr(this.s, this.p, 4) == "true" {
                this.p += 4
                return this.lit ? Toon.TrueV : 1
            }
            if SubStr(this.s, this.p, 5) == "false" {
                this.p += 5
                return this.lit ? Toon.FalseV : 0
            }
            if SubStr(this.s, this.p, 4) == "null" {
                this.p += 4
                return this.lit ? Toon.Null : ""
            }
            if RegExMatch(this.s, "A)-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?", &m, this.p) {
                this.p += m.Len[0]
                return Toon._Num(m[0])
            }
            this.Fail("Unexpected character '" . c . "'")
        }

        Obj() {
            o := Toon.OMap()
            this.p++
            this.Ws()
            if SubStr(this.s, this.p, 1) == "}" {
                this.p++
                return o
            }
            Loop {
                this.Ws()
                if SubStr(this.s, this.p, 1) != '"'
                    this.Fail("Expected string key")
                k := this.Str()
                this.Ws()
                if SubStr(this.s, this.p, 1) != ":"
                    this.Fail("Expected ':'")
                this.p++
                o[k] := this.Value()
                this.Ws()
                c := SubStr(this.s, this.p, 1)
                this.p++
                if c == "}"
                    return o
                if c != ","
                    this.Fail("Expected ',' or '}'")
            }
        }

        Arr() {
            a := []
            this.p++
            this.Ws()
            if SubStr(this.s, this.p, 1) == "]" {
                this.p++
                return a
            }
            Loop {
                a.Push(this.Value())
                this.Ws()
                c := SubStr(this.s, this.p, 1)
                this.p++
                if c == "]"
                    return a
                if c != ","
                    this.Fail("Expected ',' or ']'")
            }
        }

        Str() {
            static esc := Map("n", "`n", "r", "`r", "t", "`t", "b", "`b", "f", "`f", "/", "/", "\", "\", '"', '"')
            out := ""
            i := this.p + 1
            Loop {
                if !RegExMatch(this.s, '["\\]', &m, i)
                    this.Fail("Unterminated string")
                j := m.Pos
                out .= SubStr(this.s, i, j - i)
                if SubStr(this.s, j, 1) == '"' {
                    this.p := j + 1
                    return out
                }
                c := SubStr(this.s, j + 1, 1)
                if c == "u" {
                    hex := SubStr(this.s, j + 2, 4)
                    if !RegExMatch(hex, "^[0-9A-Fa-f]{4}$")
                        this.Fail("Invalid unicode escape")
                    out .= Chr(Integer("0x" . hex))
                    i := j + 6
                    continue
                }
                if !esc.Has(c)
                    this.Fail("Invalid escape sequence")
                out .= esc[c]
                i := j + 2
            }
        }
    }

    static _JStr(s) {
        s := StrReplace(s, "\", "\\")
        s := StrReplace(s, '"', '\"')
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, "`r", "\r")
        s := StrReplace(s, "`t", "\t")
        s := StrReplace(s, "`b", "\b")
        s := StrReplace(s, "`f", "\f")
        while RegExMatch(s, "[\x01-\x1F]", &m)
            s := StrReplace(s, m[0], Format("\u{:04X}", Ord(m[0])))
        return '"' . s . '"'
    }

    static _JD(v, ind, lvl) {
        if !IsObject(v) {
            if v is Integer
                return String(v)
            if v is Float
                return Toon._FmtFloat(v)
            return Toon._JStr(String(v))
        }
        if v is Toon.Literal
            return v.Name
        nl := ind ? "`n" . Toon._Rep(" ", ind * (lvl + 1)) : ""
        nl0 := ind ? "`n" . Toon._Rep(" ", ind * lvl) : ""
        parts := []
        if v is Array {
            if !v.Length
                return "[]"
            for x in v
                parts.Push(Toon._JD(x, ind, lvl + 1))
            return "[" . nl . Toon._Join(parts, "," . nl) . nl0 . "]"
        }
        e := (v is Map) ? v : v.OwnProps()
        for k, x in e
            parts.Push(Toon._JStr(String(k)) . (ind ? ": " : ":") . Toon._JD(x, ind, lvl + 1))
        if !parts.Length
            return "{}"
        return "{" . nl . Toon._Join(parts, "," . nl) . nl0 . "}"
    }
}

; =============================================================================
;  DEMO  (runs only when this file is executed directly)
; =============================================================================
if (A_LineFile = A_ScriptFullPath) {
    data := Toon.OMap(
        "context", Toon.OMap("task", "Our favorite hikes", "location", "Boulder"),
        "friends", ["ana", "luis", "sam"],
        "hikes", [
            Toon.OMap("id", 1, "name", "Blue Lake Trail", "distanceKm", 7.5, "wasSunny", Toon.TrueV),
            Toon.OMap("id", 2, "name", "Ridge Overlook", "distanceKm", 9.2, "wasSunny", Toon.FalseV)
        ],
        "notes", "needs, quoting: yes",
        "mixed", [1, Toon.OMap("a", 1, "b", [2, 3]), ["x", "y"]]
    )

    text := Toon.Stringify(data)
    back := Toon.Parse(text, {literals: true})
    again := Toon.Stringify(back)

    msg := "=== TOON ===`n" . text
        . "`n`n=== Round trip identical: " . (text == again ? "yes" : "NO") . " ==="
        . "`n`nhikes[2].name = " . Toon.Get(back, "hikes[1].name")
        . "`n`n=== As JSON ===`n" . Toon.ToJson(text, 2)
    MsgBox(msg, "Toon demo")
}
