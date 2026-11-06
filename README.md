# ox-quarto

![](https://img.shields.io/badge/Status-In%20development-red)


## Description

`ox-quarto` is a simple Org export backend derived from `ox-md`. It assumes a user who wants to utilize [Quarto's](https://quarto.org) extensive computational and export capabilities but who prefers to write in Org mode. The Org "wrapping", therefore, is minimal (for now).

At the moment, the exporter prioritizes passing native Quarto markup from an Org file, including YAML frontmatter. After exporting an `.org` file to `.qmd`, [`quarto-cli`](https://github.com/quarto-dev/quarto-cli) handles document creation and is a hard dependency if you want to export directly to formats like HTML and PDF. 

The package is in the early stages of development, and help from folks with more `elisp` than I have is most welcome. (I am a beginner, now using AI to help me out with this.) Please report bugs and enhancement requests in the [Issues](https://github.com/jrgant/ox-quarto/issues).


## Usage

An example file `ox-quarto-example.org` is provided that can be used to play with the features. It also serves as a reference for examples of features.

### Document options

For now it's best to set `#+OPTIONS: toc:nil` to avoid rendering the table of contents directly in the `.qmd` document. `ox-quarto` will use Org's `TITLE`, `SUBTITLE`, `AUTHOR`, `DATE`, and `BIBLIOGRAPHY` fields, if available. If you have multiple bibliographies, you can use multiple `#+BIBLIOGRAPHY:` lines and they will be properly formatted as a YAML array.

| Option | Description |
|:---|:---|
| `#+QUARTO_OPTIONS` | Pass elements to Quarto's YAML frontmatter (ex., `toc:true toc-depth:2`). Multiple lines are concatenated automatically. |
| `#+QUARTO_FRONTMATTER` | A filename or inline YAML to insert into the frontmatter block. Filenames are resolved relative to the `.org` file's directory. |
| `#+QUARTO_<FORMAT>_OPTIONS` | Format-specific options placed under Quarto's `format:` key. Replace `<FORMAT>` with any Quarto output format (ex., `#+QUARTO_HTML_OPTIONS: toc:true`, `#+QUARTO_PDF_OPTIONS: toc:false`). Multiple lines and multiple formats are supported. |
| `#+QUARTO_PREVIEW_ARGS` | Pass command line arguments to `quarto preview` when running preview from the export menu (ex., `--port 4444`). Can be specified across multiple lines. |
| `#+QUARTO_RENDER_ARGS` | Pass command line arguments to `quarto render` when rendering from the export menu (ex., `--output testfile.docx`). Can be specified across multiple lines. |

`ox-quarto` does not check for duplicate keys in the frontmatter, so if you use Org's `DATE` field and set `date` again in `QUARTO_OPTIONS` or your `QUARTO_FRONTMATTER` file, you will get a compilation error from `quarto-cli`.

#### Format-specific options example

```org
#+QUARTO_HTML_OPTIONS: toc:true code-fold:true
#+QUARTO_PDF_OPTIONS: toc:false
```

exports to:

```yaml
format:
  html:
    toc: true
    code-fold: true
  pdf:
    toc: false
```

Quarto extension format names that contain hyphens are supported:

```org
#+QUARTO_ACM-PDF_OPTIONS: toc:false fontsize:11pt
```

#### Merging with `#+QUARTO_FRONTMATTER`

When a `#+QUARTO_FRONTMATTER` file (or inline block) already contains a `format:` section, `ox-quarto` merges it with any `#+QUARTO_<FORMAT>_OPTIONS` keywords rather than emitting two separate `format:` keys. The merged output contains a single `format:` block with a single sub-block per format.

Precedence rules:
- If the same format+key appears in both the frontmatter and a `#+QUARTO_<FORMAT>_OPTIONS` line, the value from the org file takes precedence.
- Keys present in only one source are included unchanged.

For example, given a frontmatter file containing:

```yaml
format:
  pdf:
    toc: true
    header-includes: |
      \usepackage{booktabs}
```

and the org file:

```org
#+QUARTO_FRONTMATTER: frontmatter.yaml
#+QUARTO_PDF_OPTIONS: toc:false fontsize:12pt
```

the exported frontmatter will contain:

```yaml
format:
  pdf:
    toc: false
    header-includes: |
      \usepackage{booktabs}
    fontsize: 12pt
```

**Note:** The merge parser handles YAML block scalars (`|`, `>`) and preserves their content verbatim. Nested mappings under a format key (e.g., a `shift-heading-level-by` sub-map) are not parsed and should be kept exclusively in the frontmatter file.

### Citations

`ox-quarto` supports native Quarto/Pandoc citation generation.

- **`org-cite`**: Fully supported natively. When using the `org-cite` syntax (e.g., `[cite:@key1;@key2]`), `ox-quarto` registers a custom export processor that translates the citations, prefixes, and locators into valid Pandoc Markdown citations (`[@key1; @key2]`).
- **`org-ref`**: `ox-quarto` intercepts `org-ref` citation links (e.g., `cite:key1,key2`) and converts them into properly formatted Pandoc equivalents.

The following `org-cite` citation styles are supported:

| Style | Org syntax | Output |
|:---|:---|:---|
| Default (parenthetical) | `[cite:@key]` | `[@key]` |
| Suppress author (`:na`) | `[cite/na:@key]` | `[-@key]` |
| Text citation (`:t`) | `[cite/t:@key]` | `@key` |

### Cross-references

Bare internal links whose targets begin with one of [Quarto's reserved cross-reference prefixes](https://quarto.org/docs/authoring/cross-references.html) (`fig`, `tbl`, `sec`, `eq`, etc.) are transcoded to `@`-references. Both Quarto's `prefix-name` form and the Org-style `prefix:name` form are accepted; the colon is converted to a hyphen on export:

```org
See [[fig-myfig]] and [[tbl:mytable]].
```

exports to:

```markdown
See @fig-myfig and @tbl-mytable.
```

The same conversion applies to `#+NAME` labels on figures and tables, so `#+NAME: fig:elephant` produces the Quarto ID `#fig-elephant`.

### Quarto blocks (fenced divs)

`ox-quarto` supports Quarto's fenced div syntax (`:::`) through Org special blocks. The block name becomes the CSS class in the exported `.qmd` file.

```org
#+BEGIN_column-margin
This appears in the margin.
#+END_column-margin
```

exports to:

```markdown
::: {.column-margin}
This appears in the margin.
:::
```

This works for any Quarto div type: callouts (`callout-note`, `callout-warning`, etc.), content visibility (`content-hidden`, `content-visible`), column layouts (`column-margin`), and more.

#### Callout titles

For callout blocks, use the `:title` parameter on the `#+BEGIN_` line:

```org
#+BEGIN_callout-important :title "My Callout Title"
Oh hai, Mark.
#+END_callout-important
```

exports to:

```markdown
::: {.callout-important}
## My Callout Title
Oh hai, Mark.
:::
```

#### Additional attributes

You can pass attributes using `#+ATTR_QUARTO:` or inline parameters on the `#+BEGIN_` line. Inline parameters take precedence when both specify the same key.

```org
#+ATTR_QUARTO: :id my-note :collapse true
#+BEGIN_callout-note :title "Collapsible note"
This is a collapsible note.
#+END_callout-note
```

exports to:

```markdown
::: {#my-note .callout-note collapse="true"}
## Collapsible note
This is a collapsible note.
:::
```

### Footnotes

`ox-quarto` supports all three Org footnote forms:

| Form | Org syntax | Output |
|:---|:---|:---|
| Standard reference | `[fn:ID]` with a separate `[fn:ID] content` definition | `[^ID]` / `[^ID]: content` |
| Named inline | `[fn:ID: content]` | `[^ID]` with definition appended after the paragraph |
| Anonymous inline | `[fn:: content]` | `^[content]` |

### Tables

Org tables are exported as Markdown pipe tables. A horizontal rule in the Org table becomes the header separator row, with dash counts matching the Org column widths. `table.el`-style tables fall back to HTML export.

```org
| Column A | Column B |
|----------+----------|
| foo      | bar      |
| baz      | qux      |
```

exports to:

```markdown
| Column A | Column B |
|----------|----------|
| foo      | bar      |
| baz      | qux      |
```

Use `#+CAPTION` for the table caption, `#+NAME` for the cross-reference label, and `#+ATTR_QUARTO:` for alignment:

| Keyword | Description |
|:---|:---|
| `#+NAME` | Cross-reference label (e.g. `tbl-mytable` or `tbl:mytable`). Takes precedence over `:label`. |
| `#+ATTR_QUARTO: :align` | Alignment string, one character per column: `l` (left), `r` (right), `c` (center), other (default). |
| `#+ATTR_QUARTO: :label` | Fallback cross-reference label if `#+NAME` is absent. |

Multiple `#+ATTR_QUARTO:` lines are supported and merged.

```org
#+NAME: tbl-example
#+CAPTION: This is a caption.
#+ATTR_QUARTO: :align lrcd
| Col1       | Col2 | Col3 | Col4 |
|------------+------+------+------|
| Some stuff |    2 |    6 |   10 |
| More stuff |    4 |    8 |   12 |
```

exports to:

```markdown
| Col1       | Col2 | Col3 | Col4 |
|:-----------|-----:|:----:|------|
| Some stuff | 2    | 6    | 10   |
| More stuff | 4    | 8    | 12   |

: This is a caption. {#tbl-example}
```

### Figures

Inline image links export as Markdown images. When an image is the only content of its paragraph, `#+CAPTION` becomes the caption, `#+NAME` (or `:label` in `#+ATTR_QUARTO:`) becomes the cross-reference ID, `:class` adds CSS classes, and any other `#+ATTR_QUARTO:` pairs become attributes:

```org
#+ATTR_QUARTO: :width 2in :class lightbox
#+CAPTION: This is an elephant
#+NAME: fig:elephant
[[./elephant.jpg]]

Then we can reference [[fig:elephant]].
```

exports to:

```markdown
![This is an elephant](./elephant.jpg){#fig-elephant .lightbox width=2in}

Then we can reference @fig-elephant.
```

Attribute values are quoted only when they contain whitespace, `"`, or `}`. An image that appears inside running text exports as a plain `![](path)`, without caption or attributes.

### Subscripts and superscripts

Org subscripts and superscripts export with Pandoc syntax: `H_{2}O` becomes `H~2~O` and `x^{2}` becomes `x^2^`. Which constructs are interpreted follows Org's `^` export option: `#+OPTIONS: ^:{}` (braced forms only), `^:t` (all), or `^:nil` (none, exported literally).

### Code blocks

Inline source blocks (`src_LANGUAGE{code}`) are exported as inline code with the language prefix:

```org
The mean is src_R{mean(x)}.
```

exports to:

```markdown
The mean is `r mean(x)`.
```

Inline source blocks are exported as code for Quarto to evaluate; `org-babel` does not evaluate them or substitute their results during export.

Feed YAML arguments for computations within source code blocks just as you would in native Quarto:

```org
#+BEGIN_SRC R
#| echo: false
#| fig-cap: My figure's caption.
hist(rnorm(100))
#+END_SRC
```

I've not yet made an effort to parse output from `org-babel` computations, which means that code chunk options are the primary means to format figures, tables, and other output generated by code. (Org captions and labels are supported for static [tables](#tables) and [figures](#figures).)


### Other Quarto markup

For Quarto markup that is not covered by special blocks, you can pass native Quarto/Pandoc markup directly. In some cases, `ox-md` will insert escape characters that cause inconsistencies in rendered content. You should consider using a `markdown` export block when you run into problems.


### Keybindings

| Binding       | Export                                      |
|:--------------|:--------------------------------------------|
| `C-c C-e Q b` | To temporary buffer                         |
| `C-c C-e Q f` | To file                                     |
| `C-c C-e Q o` | To file and open                            |
| `C-c C-e Q p` | To file and preview (runs `quarto preview`) |
| `C-c C-e Q h` | To HTML and preview (runs `quarto preview --to html`) |
| `C-c C-e Q r` | To file and render (runs `quarto render`)   |

`M-x org-quarto-convert-region-to-qmd` converts a selected region of Org syntax to Quarto Markdown in place. This can be used in any buffer.

### Browser

After a preview starts, `ox-quarto` opens it as set by `org-quarto-browser`:

| Value               | Behavior                                                                 |
|:--------------------|:-------------------------------------------------------------------------|
| `"xdg-open"`        | Default. Open with the system's default browser.                         |
| `"firefox"`, etc.   | Open with the named browser program.                                     |
| `xwidget`           | Open in an `xwidget-webkit` buffer inside Emacs (needs xwidgets support). |
| `nil`               | Let `quarto preview` open its own browser.                               |

For preview, `ox-quarto` passes `--no-browser` to Quarto and opens the URL itself. If `#+QUARTO_PREVIEW_ARGS` already contains `--no-browser`, nothing is opened.

To open the output after a render as well, set `org-quarto-open-after-render` to `t` (off by default). HTML output then goes to `org-quarto-browser`. Any other output (PDF, DOCX, ...) is visited in Emacs with whatever mode you already use for it, such as pdf-tools' `pdf-view-mode`. Re-rendering reverts the existing buffer instead of opening a new one.

When a render produces several formats at once, `org-quarto-output-preferred-format` picks which file to open. Set it to a file extension (`"pdf"`) or a list of extensions in order of preference (`'("pdf" "docx")`). If it is `nil` (the default) or nothing matches, the first file Quarto reports is opened.

Two options control where the xwidget window and rendered files open:

- `org-quarto-output-window-side`: `right` (default), `left`, `above`, or `below` the Org window.
- `org-quarto-output-window-size`: a fraction of the Org window (default `0.5`), or an integer number of columns. For `above` and `below`, it sets the height, in lines when it is an integer.

```elisp
(setq org-quarto-browser 'xwidget
      org-quarto-open-after-render t
      org-quarto-output-preferred-format "pdf"
      org-quarto-output-window-side 'right
      org-quarto-output-window-size 0.4)
```

Later previews reuse the same xwidget buffer.


## Testing

Over time I will try to add tests to the repository. Until then, I am doing ad hoc tests on:

- Kubuntu 26.04
- emacs 30.2 (doom 3.0.0-pre)

Please report issues on Windows or Mac, or in other emacs configs.
