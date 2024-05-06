# ox-quarto

![](https://img.shields.io/badge/Status-In%20development-red)


## Description

`ox-quarto` is a simple Org export backend derived from `ox-md`. It assumes a user who wants to utilize [Quarto's](https://quarto.org) extensive computational and export capabilities but who prefers to write in Org mode. The Org "wrapping", therefore, is minimal (for now).

At the moment, the exporter prioritizes passing native Quarto markup from an Org file, including YAML frontmatter. After exporting an `.org` file to `.qmd`, [`quarto-cli`](https://github.com/quarto-dev/quarto-cli) handles document creation and is a hard dependency if you want to export directly to formats like HTML and PDF. 

The package is in the early stages of development, and help from folks with more `elisp` than I have is most welcome. (I am a beginner.) Please report bugs and enhancement requests in the [Issues](https://github.com/jrgant/ox-quarto/issues).


## Usage

### Document options

For now it's best to set `#+OPTIONS: toc:nil` to avoid rendering the table of contents directly in the `.qmd` document. `ox-quarto` will use Org's `TITLE`, `AUTHOR`, `DATE`, and `BIBLIOGRAPHY` fields, if available.

- `#+QUARTO_OPTIONS` :: Limited to a single line, pass elements to Quarto's YAML frontmatter (ex., `toc:true toc-depth:2`). These will be inserted after the title, author, and date (when these elements are specified within the Org fields).

- `#+QUARTO_FRONTMATTER` :: The name of a file containing YAML frontmatter content. This file will be inserted as is into the `.qmd` file's frontmatter block.

`ox-quarto` does not check for duplicate keys in the frontmatter, so if you use Org's `DATE` field and set `date` again in `QUARTO_OPTIONS` or your `QUARTO_FRONTMATTER` file, you will get a compilation error from `quarto-cli`.

### Citations

For selfish reasons, `ox-quarto` looks for [`org-ref`](https://github.com/jkitchin/org-ref) citation links and parses them but then lets `ox-md` handle all other link types. If you use native Org cite links, your mileage may vary.

### Quarto markup 

In the future, I hope to add support for parsing special blocks in Org, but for the moment, you should be able to pass native Quarto markup directly into the `.qmd` document.

For the most part, Quarto markup written in the main body of the Org buffer should render correctly. In some cases, `ox-md` will insert escape characters that cause inconsistencies in rendered content. You should consider using a `markdown` source block when you run into problems.

```org
#+BEGIN_SRC markdown
::: {.callout-important}
## My Callout Title
Oh hai, Mark.
:::
#+END_SRC
```

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
| `C-c C-e Q r` | To file and render (runs `quarto render`)   |


## Testing

Over time I will try to add tests to the repository. Until then, I am doing ad hoc tests on Kubuntu 22.04. Please report issues on Windows or Mac.
