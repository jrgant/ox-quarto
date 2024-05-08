;; ox-quarto.el --- Quarto Backend for Org Export Engine -*- lexical-binding: t; -*-

;; Copyright (C) 2024 Jason Gantenberg
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
(require 'ox-md)
(require 'ox-publish)

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
              (org-quarto-export-to-qmd-and-preview)))
        (?r "To file and render"
            (lambda (a s v b)
              (org-quarto-export-to-qmd-and-render)))))
  :translate-alist '((link . org-quarto-link)
                     (plain-text . org-quarto-plain-text)
                     (src-block . org-quarto-src-block)
                     (template . org-quarto-template))
  :options-alist '((:quarto-frontmatter "QUARTO_FRONTMATTER" nil nil t)
                   (:quarto-options "QUARTO_OPTIONS" nil nil t)))


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
  "Export current buffer to a Quarto file. See documentation
for `org-md-export-to-markdown'."
  (interactive)
  (let ((outfile (org-export-output-file-name ".qmd" subtreep)))
    (org-export-to-file 'quarto outfile async subtreep visible-only)))

;;;###autoload
(defun org-quarto-export-to-qmd-and-preview ()
  "Export the Org file to Quarto and then run `quarto preview'. Doing so will
open HTML output from the QMD file in a browser."
  (org-quarto-export-to-qmd)
  (shell-command (concat "quarto preview " (org-export-output-file-name ".qmd"))))

;;;###autoload
(defun org-quarto-export-to-qmd-and-render ()
  "Export the Org file to Quarto and then run `quarto render'."
  (org-quarto-export-to-qmd)
  (shell-command (concat "quarto render " (org-export-output-file-name ".qmd"))))


;; Generate YAML frontmatter

(defun org-quarto-yaml-frontmatter (info)
  "Return YAML frontmatter string from INFO for Quarto Markdown export."
  (let ((title (plist-get info :title))
        (date (plist-get info :date))
        (author (plist-get info :author))
        (bibliography (plist-get info :bibliography))
        (quarto_yml (plist-get info :quarto-frontmatter)))
    (concat
     "---\n"
     (when (and title
                (plist-get info :with-title))
       (format "title: %s\n" (org-export-data title info)))
     (when (and date
                (plist-get info :with-date))
       (format "date: %s\n" (org-export-data date info)))
     (when (and author
                (plist-get info :with-author))
       (format "author: %s\n" (org-export-data author info)))
     (when bibliography
       (format "bibliography: %s\n" (org-export-data bibliography info)))
     (when quarto_yml
       (format "%s" (f-read-text (org-export-data quarto_yml info))))
     "\n"
     ;; wrangle and format QUARTO_OPTIONS
     (replace-regexp-in-string
      ":" ": "
      (replace-regexp-in-string " " "\n" (plist-get info :quarto-options)))
     "\n---\n")))


;; Source Blocks

(defun org-quarto-src-block (src-block _contents info)
  "Transcode a SRC-BLOCK element from Org to Quarto Markdown.
INFO is a plist holding contextual information."
  (let ((lang (org-element-property :language src-block)))
  (concat
   "```{" (downcase lang) "}\n"
   (org-export-format-code-default src-block info)
   "```")))


;; Links

(defun org-quarto-link (link desc info)
  "Transcode org-ref citation LINK and DESC to Quarto format.
For other types of links, default to `org-md-link'. INFO is a plist used as a
communication channel."
  (if (string= "cite" (org-element-property :type link))
    (concat "\["
            (replace-regexp-in-string "\\&" "\@" (org-element-property :path link))
            "\]")
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

;;; ox-quarto.el ends here
