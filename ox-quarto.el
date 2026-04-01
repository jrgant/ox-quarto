;; ox-quarto.el --- Quarto Backend for Org Export Engine -*- lexical-binding: t; -*-

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
  :translate-alist '((inline-src-block . org-quarto-inline-src-block)
                     (link . org-quarto-link)
                     (plain-text . org-quarto-plain-text)
                     (special-block . org-quarto-special-block)
                     (src-block . org-quarto-src-block)
                     (template . org-quarto-template))
  :options-alist `((:quarto-frontmatter "QUARTO_FRONTMATTER" nil nil t)
                   (:quarto-options "QUARTO_OPTIONS" nil nil space)
                   (:quarto-preview-args "QUARTO_PREVIEW_ARGS" nil nil space)
                   (:quarto-render-args "QUARTO_RENDER_ARGS" nil nil space)
                   (:bibliography "BIBLIOGRAPHY" nil nil space)))


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
         (process-args (append (list "preview" (expand-file-name outfile)) args-list)))
    (message "Running: quarto %s" (mapconcat #'identity process-args " "))
    (apply #'start-process "quarto-preview" "*quarto-preview*" "quarto" process-args)
    (display-buffer "*quarto-preview*")))

;;;###autoload
(defun org-quarto-export-to-qmd-and-preview-html (&optional async subtreep visible-only)
  "Export the Org file to Quarto and then run `quarto preview --to html'.
Doing so will open HTML output from the QMD file in a browser, explicitly setting the target format."
  (interactive)
  (org-quarto--check-quarto-binary)
  (let* ((outfile (org-quarto-export-to-qmd async subtreep visible-only))
         (info (org-export-get-environment 'quarto))
         (args (plist-get info :quarto-preview-args))
         (args-list (if (stringp args) (split-string args "[ \t\n]+" t) nil))
         (process-args (append (list "preview" (expand-file-name outfile) "--to" "html") args-list)))
    (message "Running: quarto %s" (mapconcat #'identity process-args " "))
    (apply #'start-process "quarto-preview" "*quarto-preview*" "quarto" process-args)
    (display-buffer "*quarto-preview*")))

;;;###autoload
(defun org-quarto-export-to-qmd-and-render (&optional async subtreep visible-only)
  "Export the Org file to Quarto and then run `quarto render'."
  (interactive)
  (org-quarto--check-quarto-binary)
  (let* ((outfile (org-quarto-export-to-qmd async subtreep visible-only))
         (info (org-export-get-environment 'quarto))
         (args (plist-get info :quarto-render-args))
         (args-list (if (stringp args) (split-string args "[ \t\n]+" t) nil))
         (process-args (append (list "render" (expand-file-name outfile)) args-list)))
    (message "Running: quarto %s" (mapconcat #'identity process-args " "))
    (apply #'start-process "quarto-render" "*quarto-render*" "quarto" process-args)
    (display-buffer "*quarto-render*")))


;; Generate YAML frontmatter
(defun org-quarto--wrangle-options (opts-str)
  "Parse a string of space-separated KEY:VALUE pairs into a YAML block."
  (if (not (and opts-str (stringp opts-str)))
      ""
    (let* ((opts-list (split-string opts-str "[ \t\n]+" t))
           (result-lines '())
           (current-pair nil))
      (while opts-list
        (setq current-pair (pop opts-list))
        (if (stringp current-pair)
            (let ((parts (split-string current-pair ":" t)))
              (if (cdr parts)
                  (push (concat (car parts) ": " (cadr parts)) result-lines)
                (push current-pair result-lines)))))
      (mapconcat 'identity (nreverse result-lines) "\n"))))

(defun org-quarto--read-file-contents (filename)
  "Read the contents of FILENAME and return them as a string.
Signals a user error if FILENAME does not exist."
  (unless (file-exists-p filename)
    (user-error "QUARTO_FRONTMATTER file not found: %s" filename))
  (with-temp-buffer
    (insert-file-contents filename)
    (buffer-string)))

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
     (when quarto_yml
       (format "%s\n" (org-quarto--read-file-contents (org-export-data quarto_yml info))))
     ;; Wrangle and format QUARTO_OPTIONS
     (when quarto_opts
       (concat (org-quarto--wrangle-options quarto_opts) "\n"))
     "---\n\n")))


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

(defun org-quarto-special-block (special-block contents info)
  "Transcode a SPECIAL-BLOCK element from Org to a Quarto fenced div.
The block type name becomes the primary CSS class.  Additional attributes
can be specified via #+ATTR_QUARTO: or inline parameters on the #+BEGIN_
line.  Inline parameters take precedence over #+ATTR_QUARTO: when both
specify the same key.

The special :title parameter emits a ## heading inside the div (used for
callout titles).  INFO is a plist holding contextual information."
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


;; Links

(defun org-quarto-link (link desc info)
  "Transcode org-ref citation LINK and DESC to Quarto format.
For other types of links, default to `org-md-link'. INFO is a plist used as a
communication channel."
  (if (string= "cite" (org-element-property :type link))
      (let* ((path (org-element-property :path link))
             (clean-path (replace-regexp-in-string "\\&" "" path))
             (keys (split-string clean-path ",")))
        (concat "["
                (mapconcat (lambda (k)
                             (concat "@" (replace-regexp-in-string "^@" "" k)))
                           keys "; ")
                "]"))
    (org-md-link link desc info)))


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

(defun org-quarto-template (contents info)
  "Return complete document string after Quarto Markdown conversion.
This function concatenates the YAML frontmatter and the document CONTENTS. INFO
is a plist used as a communication channel."
  ;; Build up YAML frontmatter
  (concat
   (org-quarto-yaml-frontmatter info)
   contents))

(provide 'ox-quarto)

;;; Local variables:
;;; generated-autoload-file: "ox-loaddefs.el"
;;; End:

;;; ox-quarto.el ends here
