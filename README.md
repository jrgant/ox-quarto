# ox-quarto

![](https://img.shields.io/badge/Status-In%20development-red)


## Description

`ox-quarto` is a simple Org export backend derived from `ox-md`. It assumes a user who wants to utilize [Quarto's](https://quarto.org) extensive computational and export capabilities but who prefers to write in Org mode. The Org "wrapping", therefore, is minimal (for now).

At the moment, the exporter prioritizes passing native Quarto markup from an Org file, including YAML frontmatter. After exporting an `.org` file to `.qmd`, [`quarto-cli`](https://github.com/quarto-dev/quarto-cli) handles document creation and is a hard dependency if you want to export directly to formats like HTML and PDF. 

The package is in the early stages of development, and help from folks with more `elisp` than I have is most welcome. (I am a beginner, now using AI to help me out with this.) Please report bugs and enhancement requests in the [Issues](https://github.com/jrgant/ox-quarto/issues).


## Usage

### Document options

For now it's best to set `#+OPTIONS: toc:nil` to avoid rendering the table of contents directly in the `.qmd` document. `ox-quarto` will use Org's `TITLE`, `AUTHOR`, `DATE`, and `BIBLIOGRAPHY` fields, if available. If you have multiple bibliographies, you can use multiple `#+BIBLIOGRAPHY:` lines and they will be properly formatted as a YAML array.

| Option | Description |
|:---|:---|
| `#+QUARTO_OPTIONS` | Pass elements to Quarto's YAML frontmatter (ex., `toc:true toc-depth:2`). Multiple lines are concatenated automatically. |
| `#+QUARTO_FRONTMATTER` | The name of a file containing YAML frontmatter content. Inserted as-is into the `.qmd` frontmatter block. |
| `#+QUARTO_PREVIEW_ARGS` | Pass command line arguments to `quarto preview` when running preview from the export menu (ex., `--port 4444`). Can be specified across multiple lines. |
| `#+QUARTO_RENDER_ARGS` | Pass command line arguments to `quarto render` when rendering from the export menu (ex., `--output testfile.docx`). Can be specified across multiple lines. |

`ox-quarto` does not check for duplicate keys in the frontmatter, so if you use Org's `DATE` field and set `date` again in `QUARTO_OPTIONS` or your `QUARTO_FRONTMATTER` file, you will get a compilation error from `quarto-cli`.

### Citations

`ox-quarto` supports native Quarto/Pandoc citation generation.

- **`org-cite`**: Fully supported natively. When using the `org-cite` syntax (e.g., `[cite:@key1;@key2]`), `ox-quarto` registers a custom export processor that translates the citations, prefixes, and locators into valid Pandoc Markdown citations (`[@key1; @key2]`).
- **`org-ref`**: `ox-quarto` intercepts `org-ref` citation links (e.g., `cite:key1,key2`) and converts them into properly formatted Pandoc equivalents.

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

### Other Quarto markup

For Quarto markup that is not covered by special blocks, you can pass native Quarto/Pandoc markup directly. In some cases, `ox-md` will insert escape characters that cause inconsistencies in rendered content. You should consider using a `markdown` export block when you run into problems.

Feed YAML arguments for computations within source code blocks just as you would in native Quarto:

```org
#+BEGIN_SRC R
#| echo: false
#| fig-cap: My figure's caption.
hist(rnorm(100))
#+END_SRC
```

I've not yet made an effort to parse output from `org-babel` computations, which means that code chunk options are the primary means to format figures, tables, and other output. At some point I hope to add parsing of Org captions and labels.

### Keybindings

| Binding       | Export                                      |
|:--------------|:--------------------------------------------|
| `C-c C-e Q b` | To temporary buffer                         |
| `C-c C-e Q f` | To file                                     |
| `C-c C-e Q o` | To file and open                            |
| `C-c C-e Q p` | To file and preview (runs `quarto preview`) |
| `C-c C-e Q h` | To HTML and preview (runs `quarto preview --to html`) |
| `C-c C-e Q r` | To file and render (runs `quarto render`)   |


## Testing

Over time I will try to add tests to the repository. Until then, I am doing ad hoc tests on Kubuntu 22.04. Please report issues on Windows or Mac.
