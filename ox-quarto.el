;;; ox-quarto.el --- Quarto Backend for Org Export Engine -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jason Gantenberg
;; Author: Jason Gantenberg <jason.gantenberg@gmail.com>
;; Keywords: org, export, quarto

;; OX-QUARTO is licensed under the GNU General Public License version 3,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.

;; See <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This library implements a Quarto backend for the Org exporter, based on the
;; `md' backend by Nicolas Goaziou. Much of the documentation text is copied
;; from the `md' backend, when applicable.

;;; Code:

(require 'org-macs)
(org-assert-version)

(require 'cl-lib)
(require 'format-spec)
(require 'ox)
(require 'ox-md)
(require 'ox-publish)
(require 'table)
(require 'oc)


;;; Define Back-End

(org-export-define-derived-backend 'quarto 'md
  :filters-alist '((:filter-parse-tree . org-md-separate-elements))
  :menu-entry
  '(?Q "Export to Quarto"
       ((?b "To temporary buffer"
            (lambda (a s v b) (org-quarto-export-as-qmd a s v)))
        (?f "To file" (lambda (a s v b) (org-quarto-export-to-qmd a s v)))
        (?o "To file and open"
            (lambda (a s v b)
              (if a (org-quarto-export-to-qmd t s v)
                (org-open-file (org-quarto-export-to-qmd nil s v)))))
        (?p "To file and preview"
            (lambda (a s v b)
              (org-quarto-export-to-qmd-and-preview a s v)))
        (?h "To HTML and preview"
            (lambda (a s v b)
              (org-quarto-export-to-qmd-and-preview-html a s v)))
        (?r "To file and render"
            (lambda (a s v b)
              (org-quarto-export-to-qmd-and-render a s v)))))
  :translate-alist '((entity . org-quarto-entity)
                     (footnote-definition . org-quarto-footnote-definition)
                     (footnote-reference . org-quarto-footnote-reference)
                     (inline-src-block . org-quarto-inline-src-block)
                     (inner-template . org-quarto-inner-template)
                     (link . org-quarto-link)
                     (paragraph . org-quarto-paragraph)
                     (plain-text . org-quarto-plain-text)
                     (special-block . org-quarto-special-block)
                     (src-block . org-quarto-src-block)
                     (table . org-quarto-table)
                     (table-cell . org-quarto-table-cell)
                     (table-row . org-quarto-table-row)
                     (template . org-quarto-template))
  :options-alist `((:quarto-frontmatter "QUARTO_FRONTMATTER" nil nil space)
                   (:quarto-options "QUARTO_OPTIONS" nil nil space)
                   (:quarto-preview-args "QUARTO_PREVIEW_ARGS" nil nil space)
                   (:quarto-render-args "QUARTO_RENDER_ARGS" nil nil space)
                   (:bibliography "BIBLIOGRAPHY" nil nil space)))


;;; Transcoders

;; Entities

(defun org-quarto-entity (entity _contents _info)
  "Transcode an ENTITY object from Org to Quarto Markdown.
Entities that require math mode (e.g. \\beta) are wrapped in inline math
delimiters ($...$).  Other entities fall back to their UTF-8 representation."
  (let ((latex (org-element-property :latex entity))
        (math-p (org-element-property :latex-math-p entity)))
    (if math-p
        (format "$%s$" latex)
      (or (org-element-property :utf-8 entity) latex))))


;;; Utilities

(defun org-quarto--check-quarto-binary ()
  "Signal an error if the `quarto' executable cannot be found on PATH."
  (unless (executable-find "quarto")
    (user-error "Cannot find `quarto' executable on PATH")))

(defun org-quarto--parse-parameters (params-str)
  "Parse a PARAMS-STR of `:key value' pairs into a plist.
Values enclosed in double quotes have the quotes stripped."
  (when (and params-str (org-string-nw-p params-str))
    (let ((result '())
          (remaining (string-trim params-str)))
      (while (string-match "\\(:[^ \t\n]+\\)\\s-+\\(\"[^\"]*\"\\|[^ \t\n]+\\)" remaining)
        (let ((key (intern (match-string 1 remaining)))
              (val (match-string 2 remaining)))
          (when (string-match "\\`\"\\(.*\\)\"\\'" val)
            (setq val (match-string 1 val)))
          (setq result (plist-put result key val))
          (setq remaining (substring remaining (match-end 0)))))
      result)))

(defun org-quarto--build-div-header (block-type id extra-classes attributes)
  "Build a Quarto fenced div header string.
BLOCK-TYPE is the primary class (from the Org block name).  ID is an
optional element id.  EXTRA-CLASSES is an optional space-separated string
of additional CSS classes.  ATTRIBUTES is the full parsed plist from
#+ATTR_QUARTO: and/or inline parameters, from which key-value pairs
\(excluding :id, :class, and :title) are rendered as key=\"value\"
attributes."
  (let ((parts '()))
    ;; ID
    (when (and id (org-string-nw-p id))
      (push (concat "#" id) parts))
    ;; Primary class from block type
    (push (concat "." block-type) parts)
    ;; Extra classes
    (when (and extra-classes (org-string-nw-p extra-classes))
      (dolist (cls (split-string extra-classes "[ \t]+" t))
        (push (concat "." cls) parts)))
    ;; Key-value attributes (skip :id, :class, and :title)
    (let ((plist attributes))
      (while plist
        (let ((key (pop plist))
              (val (pop plist)))
          (unless (memq key '(:id :class :title))
            (push (format "%s=\"%s\"" (substring (symbol-name key) 1) val) parts)))))
    (concat "::: {" (mapconcat #'identity (nreverse parts) " ") "}")))


;;; Interactive functions

;;;###autoload
(defun org-quarto-convert-region-to-qmd ()
  "Assume the current region has Org syntax, and convert it to Quarto Markdown.
This can be used in any buffer.  For example, you can write an
itemized list in Org syntax in a Markdown buffer and use
this command to convert it."
  (interactive)
  (org-export-replace-region-by 'quarto))

;;;###autoload
(defun org-quarto-export-as-qmd (&optional async subtreep visible-only)
  "Export current buffer to a Quarto Markdown buffer.
See documentation for `org-md-export-as-markdown'."
  (interactive)
  (org-export-to-buffer 'quarto "*Org Quarto Export*"
    async subtreep visible-only nil nil (lambda () (text-mode))))

;;;###autoload
(defun org-quarto-export-to-qmd (&optional async subtreep visible-only)
  "Export current buffer to a Quarto file.
See documentation for `org-md-export-to-markdown'."
  (interactive)
  (let ((outfile (org-export-output-file-name ".qmd" subtreep)))
    (org-export-to-file 'quarto outfile async subtreep visible-only)))

;;;###autoload
(defun org-quarto-export-to-qmd-and-preview (&optional async subtreep visible-only)
  "Export the Org file to Quarto and then run `quarto preview'.
Doing so will open HTML output from the QMD file in a browser."
  (interactive)
  (org-quarto--check-quarto-binary)
  (let* ((outfile (org-quarto-export-to-qmd async subtreep visible-only))
         (info (org-export-get-environment 'quarto))
         (args (plist-get info :quarto-preview-args))
         (args-list (if (stringp args) (split-string args "[ \t\n]+" t) nil))
         (cmd (mapconcat #'shell-quote-argument
                         (append (list "quarto" "preview" (expand-file-name outfile)) args-list)
                         " ")))
    (let ((display-buffer-alist
           (cons '("\\*quarto-preview\\*"
                   (display-buffer-in-side-window)
                   (side . bottom)
                   (window-height . 0.25))
                 display-buffer-alist)))
      (compilation-start cmd nil (lambda (_) "*quarto-preview*")))))

;;;###autoload
(defun org-quarto-export-to-qmd-and-preview-html (&optional async subtreep visible-only)
  "Export the Org file to Quarto and then run `quarto preview --to html'.
Doing so will open HTML output from the QMD file in a browser, explicitly
setting the target format."
  (interactive)
  (org-quarto--check-quarto-binary)
  (let* ((outfile (org-quarto-export-to-qmd async subtreep visible-only))
         (info (org-export-get-environment 'quarto))
         (args (plist-get info :quarto-preview-args))
         (args-list (if (stringp args) (split-string args "[ \t\n]+" t) nil))
         (cmd (mapconcat #'shell-quote-argument
                         (append (list "quarto" "preview" (expand-file-name outfile) "--to" "html") args-list)
                         " ")))
    (let ((display-buffer-alist
           (cons '("\\*quarto-preview\\*"
                   (display-buffer-in-side-window)
                   (side . bottom)
                   (window-height . 0.25))
                 display-buffer-alist)))
      (compilation-start cmd nil (lambda (_) "*quarto-preview*")))))

;;;###autoload
(defun org-quarto-export-to-qmd-and-render (&optional async subtreep visible-only)
  "Export the Org file to Quarto and then run `quarto render'."
  (interactive)
  (org-quarto--check-quarto-binary)
  (let* ((outfile (org-quarto-export-to-qmd async subtreep visible-only))
         (info (org-export-get-environment 'quarto))
         (args (plist-get info :quarto-render-args))
         (args-list (if (stringp args) (split-string args "[ \t\n]+" t) nil))
         (cmd (mapconcat #'shell-quote-argument
                         (append (list "quarto" "render" (expand-file-name outfile)) args-list)
                         " ")))
    (let ((display-buffer-alist
           (cons '("\\*quarto-render\\*"
                   (display-buffer-in-side-window)
                   (side . bottom)
                   (window-height . 0.25))
                 display-buffer-alist)))
      (compilation-start cmd nil (lambda (_) "*quarto-render*")))))


;; Generate YAML frontmatter
(defun org-quarto--wrangle-options (opts-str)
  "Parse a string of KEY:VALUE pairs into a YAML block.
Values may be plain tokens or bracket-enclosed lists like [a, b, c]."
  (if (not (and opts-str (stringp opts-str)))
      ""
    (let ((result-lines '())
          (remaining (string-trim opts-str)))
      (while (string-match
              "\\([^: \t\n]+\\):\\(\\[[^]]*\\]\\|[^ \t\n]+\\)"
              remaining)
        (push (concat (match-string 1 remaining) ": " (match-string 2 remaining))
              result-lines)
        (setq remaining (string-trim-left (substring remaining (match-end 0)))))
      (mapconcat #'identity (nreverse result-lines) "\n"))))

(defun org-quarto--read-file-contents (filename)
  "Read the contents of FILENAME and return them as a string.
Signals a user error if FILENAME does not exist."
  (unless (file-exists-p filename)
    (user-error "QUARTO_FRONTMATTER file not found: %s" filename))
  (with-temp-buffer
    (insert-file-contents filename)
    (buffer-string)))

(defun org-quarto--resolve-frontmatter (value info)
  "Return YAML content from VALUE, which may be a filename or inline YAML.
If VALUE names an existing file, it is resolved relative to the directory of
the input .org file (falling back to `default-directory'), and its contents
are returned.  Otherwise VALUE is returned as inline YAML."
  (let* ((input-file (plist-get info :input-file))
         (base-dir (if input-file
                       (file-name-directory input-file)
                     default-directory))
         (candidate (expand-file-name (string-trim value) base-dir)))
    (if (file-exists-p candidate)
        (org-quarto--read-file-contents candidate)
      value)))

(defun org-quarto--collect-format-opts (info)
  "Return an alist of (FORMAT . OPTS-STR) from QUARTO_FORMAT_OPTIONS keywords.
INFO is the export state plist.  Multiple entries for the same format are
merged with a space separator.  FORMAT is lowercased."
  (let ((result '()))
    (org-element-map (plist-get info :parse-tree) 'keyword
      (lambda (kw)
        (let ((key (org-element-property :key kw))
              (val (org-element-property :value kw)))
          (when (string-match "\\`QUARTO_\\([A-Z0-9][A-Z0-9-]*\\)_OPTIONS\\'" key)
            (let* ((fmt (downcase (match-string 1 key)))
                   (existing (assoc fmt result)))
              (if existing
                  (setcdr existing (concat (cdr existing) " " val))
                (push (cons fmt val) result)))))))
    (nreverse result)))

(defun org-quarto--parse-opts-str-to-alist (opts-str)
  "Parse OPTS-STR of KEY:VALUE pairs into an alist of (KEY . VALUE) strings.
Uses the same tokenization as `org-quarto--wrangle-options'."
  (let ((result '())
        (remaining (string-trim opts-str)))
    (while (string-match
            "\\([^: \t\n]+\\):\\(\\[[^]]*\\]\\|[^ \t\n]+\\)"
            remaining)
      (push (cons (match-string 1 remaining)
                  (match-string 2 remaining))
            result)
      (setq remaining (string-trim-left (substring remaining (match-end 0)))))
    (nreverse result)))

(defun org-quarto--strip-and-parse-format-block (yaml-str)
  "Remove the top-level `format:' block from YAML-STR and parse it.
Returns (STRIPPED-YAML . FORMAT-ALIST) where STRIPPED-YAML has the
`format:' key and all its nested content removed, and FORMAT-ALIST is an
alist of (FORMAT-NAME . ((KEY . VALUE) ...)) built from the block.
Block scalar values (indicated by `|' or `>') are preserved verbatim,
including their continuation lines.  Nested mappings are not supported."
  (let ((lines (split-string yaml-str "\n"))
        (state 'top)
        (current-fmt nil)
        (current-key nil)
        (format-alist '())
        (stripped '()))
    (cl-flet ((add-opt (key val)
                (let ((entry (assoc current-fmt format-alist)))
                  (when entry
                    (setcdr entry (append (cdr entry) (list (cons key val)))))
                  (setq current-key key)
                  (when (string-match "\\`[|>][-+]?\\'" val)
                    (setq state 'in-block-scalar)))))
      (dolist (line lines)
        (pcase state
          ('top
           (if (string-match "\\`format:[[:space:]]*\\'" line)
               (setq state 'in-format)
             (push line stripped)))
          ('in-block-scalar
           (cond
            ;; Blank line or 6+-space continuation: append to current key's value
            ((or (string-match "\\`[[:space:]]*\\'" line)
                 (string-match "\\`      " line))
             (let* ((entry (assoc current-fmt format-alist))
                    (key-entry (when entry (assoc current-key (cdr entry)))))
               (when key-entry
                 (setcdr key-entry (concat (cdr key-entry) "\n" line)))))
            ;; 4-space indent: new option, exit block scalar
            ((string-match "\\`    \\([^: \t]+\\):[[:space:]]*\\(.*\\)\\'" line)
             (setq state 'in-format-entry)
             (add-opt (match-string 1 line) (string-trim (match-string 2 line))))
            ;; 2-space indent: new format name, exit block scalar
            ((string-match "\\`  \\([a-zA-Z0-9_-]+\\):[[:space:]]*\\'" line)
             (setq state 'in-format-entry)
             (setq current-fmt (match-string 1 line))
             (setq current-key nil)
             (unless (assoc current-fmt format-alist)
               (push (cons current-fmt '()) format-alist)))
            ;; Non-indented non-blank: new top-level key
            ((string-match "\\`[^ \t]" line)
             (setq state 'top)
             (setq current-fmt nil)
             (setq current-key nil)
             (push line stripped))))
          ((or 'in-format 'in-format-entry)
           (cond
            ;; Blank line: stay in current state
            ((string-match "\\`[[:space:]]*\\'" line) nil)
            ;; 4-space indent: key-value option under current format
            ((and current-fmt
                  (string-match "\\`    \\([^: \t]+\\):[[:space:]]*\\(.*\\)\\'" line))
             (add-opt (match-string 1 line) (string-trim (match-string 2 line))))
            ;; 2-space indent: format sub-key (format name)
            ((string-match "\\`  \\([a-zA-Z0-9_-]+\\):[[:space:]]*\\'" line)
             (setq current-fmt (match-string 1 line))
             (setq current-key nil)
             (unless (assoc current-fmt format-alist)
               (push (cons current-fmt '()) format-alist))
             (setq state 'in-format-entry))
            ;; Non-indented non-blank: new top-level key
            ((string-match "\\`[^ \t]" line)
             (setq state 'top)
             (setq current-fmt nil)
             (setq current-key nil)
             (push line stripped)))))))
    (cons (string-trim-right (mapconcat #'identity (nreverse stripped) "\n"))
          (nreverse format-alist))))

(defun org-quarto--merge-format-alists (base override)
  "Merge BASE and OVERRIDE format alists; OVERRIDE takes precedence on conflicts.
Both are ((format-name . ((key . value) ...)) ...).
Formats present in only one alist are included unchanged."
  (let ((result (mapcar (lambda (p) (cons (car p) (copy-alist (cdr p)))) base)))
    (dolist (fmt-pair override)
      (let* ((fmt (car fmt-pair))
             (override-opts (cdr fmt-pair))
             (base-entry (assoc fmt result)))
        (if base-entry
            (dolist (opt override-opts)
              (let ((existing (assoc (car opt) (cdr base-entry))))
                (if existing
                    (setcdr existing (cdr opt))
                  (setcdr base-entry (append (cdr base-entry) (list opt))))))
          (push (cons fmt (copy-alist override-opts)) result))))
    result))

(defun org-quarto--format-alist-to-yaml (format-alist)
  "Return a YAML `format:' block string from FORMAT-ALIST.
FORMAT-ALIST is ((format-name . ((key . value) ...)) ...)."
  (when format-alist
    (concat "\nformat:\n"
            (mapconcat
             (lambda (fmt-pair)
               (let ((fmt-name (car fmt-pair))
                     (opts (cdr fmt-pair)))
                 (concat "  " fmt-name ":\n"
                         (mapconcat (lambda (opt)
                                      (concat "    " (car opt) ": "
                                              (string-trim-right (cdr opt))))
                                    opts "\n"))))
             format-alist
             "\n")
            "\n")))

(defun org-quarto-yaml-frontmatter (info)
  "Return YAML frontmatter string from INFO for Quarto Markdown export."
  (let ((title (plist-get info :title))
        (subtitle (plist-get info :subtitle))
        (date (plist-get info :date))
        (author (plist-get info :author))
        (bibliography (plist-get info :bibliography))
        (quarto_yml (plist-get info :quarto-frontmatter))
        (quarto_opts (plist-get info :quarto-options)))
    (concat
     "---\n"
     (when (and title
                (plist-get info :with-title))
       (format "title: %s\n" (org-export-data title info)))
     (when (and subtitle
                (plist-get info :with-title))
       (format "subtitle: %s\n" (org-export-data subtitle info)))
     (when (and date
                (plist-get info :with-date))
       (format "date: %s\n" (org-export-data date info)))
     (when (and author
                (plist-get info :with-author))
       (format "author: %s\n" (org-export-data author info)))
     (when bibliography
       (let ((bibs (split-string (if (stringp bibliography) bibliography (org-export-data bibliography info)) "[ \t\n]+" t)))
         (if (= (length bibs) 1)
             (format "bibliography: %s\n" (car bibs))
           (concat "bibliography:\n"
                   (mapconcat (lambda (b) (format "  - %s" b)) bibs "\n")
                   "\n"))))
     ;; Frontmatter YAML and #+QUARTO_<FORMAT>_OPTIONS are merged into a
     ;; single `format:' block.  When both define options for the same
     ;; format+key, the #+QUARTO_<FORMAT>_OPTIONS value takes precedence.
     (let* ((format-opts (org-quarto--collect-format-opts info))
            (org-fmt-alist
             (when format-opts
               (mapcar (lambda (p)
                         (cons (car p)
                               (org-quarto--parse-opts-str-to-alist (cdr p))))
                       format-opts)))
            (raw-fm (when quarto_yml
                      (org-quarto--resolve-frontmatter quarto_yml info)))
            (fm-stripped-parsed (when (and raw-fm org-fmt-alist)
                                  (org-quarto--strip-and-parse-format-block raw-fm)))
            (stripped-fm (cond (fm-stripped-parsed (car fm-stripped-parsed))
                               (t raw-fm)))
            (fm-fmt-alist (when fm-stripped-parsed (cdr fm-stripped-parsed)))
            (merged-fmt (org-quarto--merge-format-alists fm-fmt-alist org-fmt-alist)))
       (concat
        (when (and stripped-fm (org-string-nw-p stripped-fm))
          (format "%s\n" stripped-fm))
        (when quarto_opts
          (concat (org-quarto--wrangle-options quarto_opts) "\n"))
        (org-quarto--format-alist-to-yaml merged-fmt)))
     "---\n\n")))


;; Footnotes

(defvar org-quarto--pending-inline-fn-defs nil
  "Alist of (label . content) for inline footnote definitions pending output.
Populated during transcoding of inline footnotes; consumed and reset by
`org-quarto-template'.")

(defun org-quarto-footnote-reference (footnote-reference contents _info)
  "Transcode a FOOTNOTE-REFERENCE element from Org to Quarto Markdown.
Standard references [fn:ID] become [^ID].  Inline footnotes
[fn:ID: content] emit [^ID] at the reference site and register the
definition for output at end of document via `org-quarto-template'.
Anonymous footnotes [fn:: content] become ^[content]."
  (pcase (org-element-property :type footnote-reference)
    (`standard (format "[^%s]" (org-element-property :label footnote-reference)))
    (`inline
     (let ((label (org-element-property :label footnote-reference)))
       (push (cons label (org-trim contents)) org-quarto--pending-inline-fn-defs)
       (format "[^%s]" label)))
    (_ (format "^[%s]" (org-trim contents)))))

(defun org-quarto-footnote-definition (footnote-definition contents _info)
  "Transcode a FOOTNOTE-DEFINITION element from Org to Quarto Markdown.
[fn:ID] content becomes [^ID]: content."
  (format "[^%s]: %s"
          (org-element-property :label footnote-definition)
          (org-trim contents)))


;; Paragraphs

(defun org-quarto-paragraph (paragraph contents info)
  "Transcode a PARAGRAPH element from Org to Quarto Markdown.
Delegates to `org-md-paragraph', then appends any named inline footnote
definitions that were registered during transcoding of this paragraph's
contents."
  (let ((text (org-md-paragraph paragraph contents info))
        (defs (prog1 (nreverse org-quarto--pending-inline-fn-defs)
                (setq org-quarto--pending-inline-fn-defs nil))))
    (if defs
        (concat text "\n"
                (mapconcat (lambda (pair)
                             (format "[^%s]: %s" (car pair) (cdr pair)))
                           defs "\n")
                "\n")
      text)))


;; Source Blocks

(defun org-quarto-inline-src-block (inline-src-block _contents _info)
  "Transcode an INLINE-SRC-BLOCK element from Org to Quarto Markdown.
Exports src_LANGUAGE[:exports code]{code} as \`language code\`."
  (let ((lang (org-element-property :language inline-src-block))
        (code (org-element-property :value inline-src-block)))
    (format "`%s %s`" (downcase lang) code)))


(defun org-quarto-src-block (src-block _contents info)
  "Transcode a SRC-BLOCK element from Org to Quarto Markdown.
INFO is a plist holding contextual information."
  (let ((lang (org-element-property :language src-block)))
   (concat
    "```{" (downcase lang) "}\n"
    (org-export-format-code-default src-block info)
    "```")))


;; Special Blocks (Quarto fenced divs)

(defun org-quarto-special-block (special-block contents _info)
  "Transcode a SPECIAL-BLOCK element from Org to a Quarto fenced div.
The block type name becomes the primary CSS class.  Additional attributes
can be specified via #+ATTR_QUARTO: or inline parameters on the #+BEGIN_
line.  Inline parameters take precedence over #+ATTR_QUARTO: when both
specify the same key.

The special :title parameter emits a ## heading inside the div (used for
callout titles)."
  (let* ((block-type (org-element-property :type special-block))
         (attr-quarto (org-export-read-attribute :attr_quarto special-block))
         (inline-params (org-quarto--parse-parameters
                         (org-element-property :parameters special-block)))
         ;; Merge: inline params override attr_quarto
         (attributes (let ((merged (copy-sequence attr-quarto)))
                       (cl-loop for (key val) on inline-params by #'cddr
                                do (setq merged (plist-put merged key val)))
                       merged))
         (id (plist-get attributes :id))
         (extra-classes (plist-get attributes :class))
         (title (plist-get attributes :title))
         (header (org-quarto--build-div-header block-type id extra-classes attributes)))
    (concat header "\n"
            ;; Emit title as ## heading if provided
            (when title (concat "## " title "\n"))
            ;; Un-escape \# so that Markdown headings work inside fenced divs.
            ;; org-quarto-plain-text escapes # at line beginnings to prevent
            ;; unintended Markdown headings, but inside a fenced div they are
            ;; intentional (e.g., callout titles).
            (replace-regexp-in-string "\\\\#" "#" contents)
            ":::\n")))


;; Tables

(defun org-quarto-table-cell (table-cell contents _info)
  "Transcode a TABLE-CELL element into a Markdown pipe table cell."
  (concat " " (org-trim (or contents "")) " |"))

(defun org-quarto--repad-table-row (line col-widths)
  "Pad cells in transcoded table row LINE to widths given by COL-WIDTHS.
Each cell is left-aligned within its column so all pipes are vertically aligned.
Returns the padded row string, or LINE unchanged when cell count mismatches."
  (let* ((raw-cells (split-string (substring line 1) "|"))
         (cells (if (string= "" (car (last raw-cells)))
                    (butlast raw-cells)
                  raw-cells)))
    (if (/= (length cells) (length col-widths))
        line
      (concat "|"
              (mapconcat
               (lambda (i)
                 (let* ((trimmed (string-trim (nth i cells)))
                        (inner   (max 0 (- (nth i col-widths) 2)))
                        (pad     (max 0 (- inner (length trimmed)))))
                   (concat " " trimmed (make-string pad ?\s) " |")))
               (number-sequence 0 (1- (length cells)))
               "")))))

(defun org-quarto--table-col-widths (table)
  "Return a list of column widths for TABLE by parsing the rule row's raw text.
The rule row (e.g. `|------------+------+------+------\\=') is read from the
buffer; each segment between `|' and `+' gives the dash count for that column.
Returns nil if TABLE has no rule row or buffer text is unavailable."
  (let* ((rule-row (cl-find-if
                    (lambda (row)
                      (eq (org-element-property :type row) 'rule))
                    (org-element-contents table)))
         (beg (when rule-row (org-element-property :begin rule-row)))
         (end (when rule-row (org-element-property :end rule-row))))
    (when (and beg end)
      (let* ((raw (string-trim (buffer-substring-no-properties beg end)))
             (segments (split-string raw "[|+]" t)))
        (mapcar (lambda (seg) (max 3 (length seg))) segments)))))

(defun org-quarto--table-sep-row (col-widths align-spec)
  "Build a Markdown pipe table separator row string.
COL-WIDTHS is a list of integers (dash counts from the Org rule row).
ALIGN-SPEC is a string of alignment characters, one per column:
  l = left (:---), r = right (---:), c = center (:---:), other = default (---).
Alignment colons replace dashes so each cell stays at the same total width."
  (let ((aligns (when align-spec (string-to-list align-spec))))
    (concat "|"
            (mapconcat
             (lambda (i)
               (let* ((w (nth i col-widths))
                      (a (when (and aligns (< i (length aligns))) (nth i aligns)))
                      (sep (cond
                            ((eq a ?l) (concat ":" (make-string (max 1 (1- w)) ?-)))
                            ((eq a ?r) (concat (make-string (max 1 (1- w)) ?-) ":"))
                            ((eq a ?c) (concat ":" (make-string (max 1 (- w 2)) ?-) ":"))
                            (t (make-string (max 3 w) ?-)))))
                 (concat sep "|")))
             (number-sequence 0 (1- (length col-widths)))
             ""))))

(defun org-quarto-table-row (table-row contents _info)
  "Transcode a TABLE-ROW element into a Markdown pipe table row.
Rule rows become a fixed placeholder `| --- |' per column; the placeholder
is replaced with proper widths and alignment by `org-quarto-table'."
  (if (eq (org-element-property :type table-row) 'rule)
      (let* ((table (org-element-parent table-row))
             (ncols (length (org-element-contents
                             (cl-find-if
                              (lambda (row)
                                (eq (org-element-property :type row) 'standard))
                              (org-element-contents table))))))
        (concat "|" (apply #'concat (make-list ncols " --- |"))))
    (concat "|" contents)))

(defun org-quarto-table (table contents info)
  "Transcode a TABLE element into a Markdown pipe table.
Only org-type tables are handled; table.el tables fall back to HTML.

#+CAPTION sets the table caption.  #+NAME sets the cross-reference label
\(e.g. `#+NAME: tbl-mytable').  #+ATTR_QUARTO: accepts:
  :align   Alignment string, one character per column (l/r/c/other).
           Colons replace dashes in the separator to indicate alignment.
  :label   Fallback cross-reference label; #+NAME takes precedence.

Multiple #+ATTR_QUARTO: lines are supported and merged."
  (if (not (eq (org-element-property :type table) 'org))
      (org-html-table table contents info)
    (let* ((attr (org-export-read-attribute :attr_quarto table))
           (align-spec (let ((a (plist-get attr :align)))
                         (when a (if (stringp a) a (format "%s" a)))))
           (label (or (org-element-property :name table)
                      (let ((l (plist-get attr :label)))
                        (when l (if (stringp l) l (format "%s" l))))))
           (caption (when-let* ((c (org-export-get-caption table)))
                      (org-export-data c info)))
           (col-widths (org-quarto--table-col-widths table))
           (processed
            (if col-widths
                (let ((lines (split-string contents "\n")))
                  (mapconcat
                   #'identity
                   (mapcar (lambda (line)
                             (cond
                              ((string-match-p "^|\\( --- |\\)+" line)
                               (org-quarto--table-sep-row col-widths align-spec))
                              ((string-match-p "^|" line)
                               (org-quarto--repad-table-row line col-widths))
                              (t line)))
                           lines)
                   "\n"))
              contents))
           (caption-line (when (or label caption)
                           (concat "\n: "
                                   (or caption "")
                                   (when label (concat " {#" label "}"))))))
      (concat processed caption-line))))


;; Links

(defconst org-quarto--xref-prefix-regexp
  (rx bos
      (or "fig" "tbl" "lst" "eq" "sec"
          "thm" "lem" "cor" "prp" "cnj" "def" "exm" "exr" "sol" "rem" "alg"
          "tip" "nte" "wrn" "imp" "cau")
      "-")
  "Regexp matching Quarto cross-reference ID prefixes.")

(defun org-quarto-link (link desc info)
  "Transcode LINK and DESC to Quarto format.
Handles org-ref citations and Quarto cross-references; falls back to
`org-md-link' for all other link types.  INFO is a plist used as a
communication channel."
  (let ((type (org-element-property :type link))
        (path (org-element-property :path link)))
    (cond
     ((string= type "cite")
      (let* ((clean-path (replace-regexp-in-string "\\&" "" path))
             (keys (split-string clean-path ",")))
        (concat "["
                (mapconcat (lambda (k)
                             (concat "@" (replace-regexp-in-string "^@" "" k)))
                           keys "; ")
                "]")))
     ((and (string= type "fuzzy")
           (string-match-p org-quarto--xref-prefix-regexp path))
      (concat "@" path))
     (t
      (org-md-link link desc info)))))


;; Plain text

(defun org-quarto-plain-text (text info)
  "Transcode a TEXT string into Markdown format.
TEXT is the string to transcode.  INFO is a plist holding
contextual information. This function is copied from `org-md-plain-text'
and simply removes the activation of smart-quote export."
  ;; The below series of replacements in `text' is order sensitive.
  ;; Protect `, *, _, and \
  (setq text (replace-regexp-in-string "[`*_\\]" "\\\\\\&" text))
  ;; Protect ambiguous #.  This will protect # at the beginning of
  ;; a line, but not at the beginning of a paragraph.  See
  ;; `org-md-paragraph'.
  (setq text (replace-regexp-in-string "\n#" "\n\\\\#" text))
  ;; Protect ambiguous !
  (setq text (replace-regexp-in-string "\\(!\\)\\[" "\\\\!" text nil nil 1))
  ;; Handle special strings, if required.
  (when (plist-get info :with-special-strings)
    (setq text (org-html-convert-special-strings text)))
  ;; Handle break preservation, if required.
  (when (plist-get info :preserve-breaks)
    (setq text (replace-regexp-in-string "[ \t]*\n" "  \n" text)))
  ;; Return value.
  text)



;; Citations

(defun org-quarto--citation-export (citation style _backend info)
  "Export CITATION object to Quarto format.
STYLE is the citation style.  INFO is the export state."
  (let* ((common-prefix (org-export-data (org-element-property :prefix citation) info))
         (common-suffix (org-export-data (org-element-property :suffix citation) info))
         (style-name (and style (car style)))
         (suppress-author (string= style-name "na"))
         (text-cite (string= style-name "t"))
         (refs (mapconcat (lambda (ref)
                            (let ((key (org-element-property :key ref))
                                  (prefix (org-export-data (org-element-property :prefix ref) info))
                                  (suffix (org-export-data (org-element-property :suffix ref) info)))
                              (concat prefix 
                                      (if suppress-author "-@" "@") 
                                      key 
                                      (if (and text-cite (org-string-nw-p suffix))
                                          (concat " [" suffix "]")
                                        suffix))))
                          (org-element-contents citation)
                          (if text-cite ", " "; "))))
    (if text-cite
        (concat common-prefix refs common-suffix)
      (concat "[" common-prefix refs common-suffix "]"))))

(org-cite-register-processor 'quarto
  :export-citation #'org-quarto--citation-export)

(add-to-list 'org-cite-export-processors '(quarto . (quarto)))


;; Template

(defun org-quarto-inner-template (contents info)
  "Return body of document after Quarto Markdown conversion.
Suppresses the footnote section appended by `org-md-inner-template',
since Quarto handles footnote rendering from the .qmd source.
CONTENTS is the transcoded contents string.  INFO is a plist used as a
communication channel."
  (let ((depth (plist-get info :with-toc)))
    (concat
     (when depth
       (concat (org-md--build-toc info (and (wholenump depth) depth)) "\n"))
     contents)))

(defun org-quarto-template (contents info)
  "Return complete document string after Quarto Markdown conversion.
This function concatenates the YAML frontmatter and the document CONTENTS. INFO
is a plist used as a communication channel."
  (setq org-quarto--pending-inline-fn-defs nil)
  (concat
   (org-quarto-yaml-frontmatter info)
   contents))

(provide 'ox-quarto)

;;; Local variables:
;;; generated-autoload-file: "ox-loaddefs.el"
;;; End:

;;; ox-quarto.el ends here
