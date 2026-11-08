;;; treesit-mark.el --- Select tree-sitter nodes with avy -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Artur Yaroshenko

;; Author: Artur Yaroshenko <artawower@protonmail.com>
;; URL: https://github.com/artawower/treesit-mark.el
;; Package-Requires: ((emacs "29.1") (avy "0.5.0"))
;; Version: 0.5.0
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

(defconst treesit-mark--javascript-rules
  '(:whole ("function_declaration" "function_expression"
            "generator_function_declaration" "arrow_function" "method_definition"
            "class_declaration" "interface_declaration" "if_statement"
            "for_statement" "for_in_statement" "while_statement" "do_statement"
            "switch_statement" "try_statement")
    :block ("statement_block" "class_body" "interface_body" "object" "object_type")
    :top-level ("expression_statement" "lexical_declaration" "variable_declaration"
                "export_statement")
    :call ("call_expression" "new_expression")
    :call-statement ("expression_statement"))
  "Rules shared by JavaScript, TypeScript and TSX.")

(defcustom treesit-mark-language-rules
  `((javascript . ,treesit-mark--javascript-rules)
    (typescript . ,treesit-mark--javascript-rules)
    (tsx . ,treesit-mark--javascript-rules)
    (python
     :whole ("function_definition" "class_definition" "if_statement" "for_statement"
             "while_statement" "try_statement" "with_statement" "match_statement")
     :block ("dictionary")
     :top-level ("expression_statement")
     :call ("call")
     :call-statement ("expression_statement"))
    (rust
     :whole ("function_item" "impl_item" "struct_item" "enum_item" "trait_item"
             "mod_item" "closure_expression" "if_expression" "for_expression"
             "while_expression" "loop_expression" "match_expression")
     :block ("block" "declaration_list" "field_declaration_list"
             "field_initializer_list")
     :top-level ("const_item" "static_item")
     :call ("call_expression" "macro_invocation")
     :call-statement ("expression_statement"))
    (go
     :whole ("function_declaration" "method_declaration" "func_literal"
             "type_declaration" "if_statement" "for_statement"
             "expression_switch_statement" "type_switch_statement" "select_statement")
     :block ("block" "field_declaration_list" "literal_value")
     :top-level ("var_declaration" "const_declaration")
     :call ("call_expression")
     :call-statement ("expression_statement"))
    (java
     :whole ("class_declaration" "interface_declaration" "enum_declaration"
             "record_declaration" "method_declaration" "constructor_declaration"
             "lambda_expression" "if_statement" "for_statement"
             "enhanced_for_statement" "while_statement" "do_statement"
             "switch_expression" "try_statement")
     :block ("block" "class_body" "interface_body" "enum_body")
     :call ("method_invocation" "object_creation_expression")
     :call-statement ("expression_statement"))
    (c-sharp
     :whole ("class_declaration" "interface_declaration" "struct_declaration"
             "enum_declaration" "record_declaration" "method_declaration"
             "constructor_declaration" "lambda_expression" "if_statement"
             "for_statement" "foreach_statement" "while_statement" "do_statement"
             "switch_statement" "try_statement")
     :block ("block" "declaration_list" "enum_member_declaration_list")
     :call ("invocation_expression" "object_creation_expression")
     :call-statement ("expression_statement"))
    (c
     :whole ("function_definition" "struct_specifier" "if_statement" "for_statement"
             "while_statement" "do_statement" "switch_statement")
     :block ("compound_statement" "field_declaration_list")
     :top-level ("declaration")
     :call ("call_expression")
     :call-statement ("expression_statement"))
    (cpp
     :whole ("function_definition" "struct_specifier" "class_specifier"
             "namespace_definition" "lambda_expression" "if_statement"
             "for_statement" "for_range_loop" "while_statement" "do_statement"
             "switch_statement" "try_statement")
     :block ("compound_statement" "field_declaration_list" "declaration_list")
     :top-level ("declaration")
     :call ("call_expression")
     :call-statement ("expression_statement"))
    (lua
     :whole ("function_declaration" "function_definition" "if_statement"
             "for_statement" "while_statement" "repeat_statement")
     :block ("table_constructor")
     :top-level ("variable_declaration" "assignment_statement")
     :call ("function_call")
     :call-parent ("block"))
    (ruby
     :whole ("class" "module" "method" "singleton_method" "if" "unless" "case"
             "while" "until" "for")
     :block ("hash")
     :top-level ("assignment")
     :call ("call")
     :call-parent ("body_statement" "then" "else" "block_body" "do" "begin"
                   "ensure"))
    (t
     :whole ("function_declaration" "function_expression"
             "generator_function_declaration" "arrow_function" "method_definition"
             "method_declaration" "function_definition" "function_item"
             "class_declaration" "class_definition" "interface_declaration"
             "type_declaration" "impl_item" "struct_item" "enum_item" "trait_item"
             "if_statement" "for_statement" "for_in_statement" "while_statement"
             "do_statement" "switch_statement" "try_statement" "if_expression"
             "for_expression" "while_expression" "loop_expression"
             "match_expression")
     :block ("statement_block" "class_body" "block" "interface_body" "object"
             "object_type" "declaration_list" "field_declaration_list")
     :top-level ("expression_statement")
     :call ("call_expression" "call" "new_expression")
     :call-statement ("expression_statement")))
  "Node selection rules for each tree-sitter language.
Each element is (LANGUAGE . PLIST).  The rules for t apply to languages
without their own element.  PLIST keys hold lists of node types:

  :whole           selected whole
  :block           selected without their surrounding braces
  :top-level       selected whole at the top level of the file
  :call            calls, selected whole when they stand as a statement
  :call-statement  statements selected whole when they wrap a call
  :call-parent     containers in which a bare call is a statement"
  :type '(alist :key-type (choice symbol (const t))
                :value-type (plist :key-type symbol :value-type (repeat string))))

(defcustom treesit-mark-select-function #'treesit-mark-select-region
  "Function called with the BEG and END of the chosen node."
  :type 'function)

(defun treesit-mark-select-region (beg end)
  "Activate the region between BEG and END."
  (push-mark beg nil t)
  (goto-char end))

(defun treesit-mark--rules (language)
  "Return the selection rules for LANGUAGE."
  (or (alist-get language treesit-mark-language-rules)
      (alist-get t treesit-mark-language-rules)))

(defun treesit-mark--top-level-p (node)
  "Return non-nil if NODE is a direct child of its parser's root."
  (let ((parent (treesit-node-parent node)))
    (and parent (null (treesit-node-parent parent)))))

(defun treesit-mark--call-statement-p (node rules)
  "Return non-nil if NODE is a call standing as a statement under RULES.
That is a statement wrapping a call, or a bare call in a statement container."
  (let ((type (treesit-node-type node))
        (child (treesit-node-child node 0 t))
        (parent (treesit-node-parent node)))
    (if (member type (plist-get rules :call))
        (and parent
             (or (null (treesit-node-parent parent))
                 (member (treesit-node-type parent) (plist-get rules :call-parent))))
      (and child (member (treesit-node-type child) (plist-get rules :call))))))

(defun treesit-mark--visible-nodes (root types &optional predicate)
  "Return nodes of TYPES under ROOT that start in the selected window.
When PREDICATE is non-nil, keep only the nodes it accepts."
  (let ((first-visible (window-start))
        (last-visible (window-end nil t))
        nodes)
    (when types
      (treesit-induce-sparse-tree
       root
       (concat "\\`" (regexp-opt types) "\\'")
       (lambda (node)
         (when (and (<= first-visible (treesit-node-start node) last-visible)
                    (or (null predicate) (funcall predicate node)))
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

(defun treesit-mark--parser-nodes (parser)
  "Return (WHOLE . BLOCKS), the visible nodes of PARSER to label."
  (let* ((rules (treesit-mark--rules (treesit-parser-language parser)))
         (root (treesit-parser-root-node parser)))
    (cons (append
           (treesit-mark--visible-nodes root (plist-get rules :whole))
           (treesit-mark--visible-nodes root (plist-get rules :top-level)
                                        #'treesit-mark--top-level-p)
           (treesit-mark--visible-nodes root
                                        (append (plist-get rules :call)
                                                (plist-get rules :call-statement))
                                        (lambda (node)
                                          (treesit-mark--call-statement-p node rules))))
          (treesit-mark--visible-nodes root (plist-get rules :block)))))

(defun treesit-mark--targets ()
  "Return an alist mapping label positions to the bounds they select.
Whole nodes come first and the widest wins at a shared position."
  (let (whole blocks)
    (dolist (parser (treesit-parser-list))
      (let ((nodes (treesit-mark--parser-nodes parser)))
        (setq whole (append (car nodes) whole)
              blocks (append (cdr nodes) blocks))))
    (append
     (mapcar (lambda (node)
               (cons (treesit-node-start node)
                     (cons (treesit-node-start node) (treesit-node-end node))))
             (seq-sort-by #'treesit-node-end #'> whole))
     (mapcar (lambda (node)
               (cons (treesit-node-start node)
                     (treesit-mark--block-inner-bounds node)))
             blocks))))

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
