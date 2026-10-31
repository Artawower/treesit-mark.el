;;; treesit-mark.el --- Select tree-sitter nodes with avy -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Artur Yaroshenko

;; Author: Artur Yaroshenko <artawower@protonmail.com>
;; URL: https://github.com/artawower/treesit-mark.el
;; Package-Requires: ((emacs "29.1") (avy "0.5.0"))
;; Version: 0.1.0
;; Keywords: convenience, languages

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;; Label the functions, classes, conditions, loops and blocks visible in the
;; window with avy, and press a label to select that node.  A label on a
;; definition or statement selects it whole; a label on a block selects its
;; contents without the braces.

;;; Code:

(require 'avy)
(require 'seq)
(require 'treesit)

(defgroup treesit-mark nil
  "Select tree-sitter nodes with avy."
  :group 'convenience
  :prefix "treesit-mark-")

(defcustom treesit-mark-whole-node-types
  '("function_declaration" "function_expression" "generator_function_declaration"
    "arrow_function" "method_definition" "method_declaration"
    "function_definition" "function_item"
    "class_declaration" "class_definition" "interface_declaration"
    "type_declaration" "impl_item" "struct_item" "enum_item" "trait_item"
    "if_statement" "for_statement" "for_in_statement" "while_statement"
    "do_statement" "switch_statement" "try_statement"
    "if_expression" "for_expression" "while_expression" "loop_expression"
    "match_expression")
  "Tree-sitter node types selected whole."
  :type '(repeat string))

(defcustom treesit-mark-block-node-types
  '("statement_block" "class_body" "block" "interface_body" "object_type"
    "declaration_list" "field_declaration_list")
  "Tree-sitter node types selected without their surrounding braces."
  :type '(repeat string))

(defcustom treesit-mark-select-function #'treesit-mark-select-region
  "Function called with the BEG and END of the chosen node."
  :type 'function)

(defun treesit-mark-select-region (beg end)
  "Activate the region between BEG and END."
  (push-mark beg nil t)
  (goto-char end))

(defun treesit-mark--visible-nodes (types)
  "Return nodes of TYPES that start in the selected window."
  (let ((first-visible (window-start))
        (last-visible (window-end nil t))
        (regexp (concat "\\`" (regexp-opt types) "\\'"))
        nodes)
    (dolist (parser (treesit-parser-list))
      (treesit-induce-sparse-tree
       (treesit-parser-root-node parser)
       regexp
       (lambda (node)
         (when (<= first-visible (treesit-node-start node) last-visible)
           (push node nodes)))))
    nodes))

(defun treesit-mark--block-inner-bounds (node)
  "Return the bounds of the contents of block NODE.
An empty block returns the bounds of NODE."
  (let* ((node-start (treesit-node-start node))
         (node-end (treesit-node-end node))
         (delimited (eq (char-after node-start) ?{))
         (beg (save-excursion
                (goto-char (if delimited (1+ node-start) node-start))
                (skip-chars-forward " \t\n")
                (point)))
         (end (save-excursion
                (goto-char (if delimited (1- node-end) node-end))
                (skip-chars-backward " \t\n")
                (point))))
    (if (< beg end)
        (cons beg end)
      (cons node-start node-end))))

(defun treesit-mark--targets ()
  "Return an alist mapping label positions to the bounds they select.
Whole nodes come first and the widest wins at a shared position."
  (append
   (mapcar (lambda (node)
             (cons (treesit-node-start node)
                   (cons (treesit-node-start node) (treesit-node-end node))))
           (seq-sort-by #'treesit-node-end #'>
                        (treesit-mark--visible-nodes treesit-mark-whole-node-types)))
   (mapcar (lambda (node)
             (cons (treesit-node-start node)
                   (treesit-mark--block-inner-bounds node)))
           (treesit-mark--visible-nodes treesit-mark-block-node-types))))

;;;###autoload
(defun treesit-mark-node ()
  "Select a visible tree-sitter node chosen with an avy label."
  (interactive)
  (let* ((targets (treesit-mark--targets))
         (avy-action
          (lambda (position)
            (let ((bounds (alist-get position targets)))
              (funcall treesit-mark-select-function (car bounds) (cdr bounds))))))
    (avy-process (seq-sort #'< (seq-uniq (mapcar #'car targets))))))

(provide 'treesit-mark)
;;; treesit-mark.el ends here
