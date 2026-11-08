;;; treesit-mark-test.el --- Tests for treesit-mark -*- lexical-binding: t; -*-

;;; Commentary:
;; Run with: emacs --batch -L . -L PATH-TO-AVY -l treesit-mark-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'typescript-ts-mode)
(require 'treesit-mark)

(defconst treesit-mark-test-source
  "class Foo {
  bar(a: number) {
    return a + 1;
  }
}
function baz() {
  if (x) {
    a = 3;
    return 2;
  }
}
const f = () => 1;
function empty() {}
watch(a, () => {
  log(1);
});
const tab = make({
  setup() {
    onMounted(() => {
      log(2);
    });
  },
});
const items = [
  {
    name: \"x\",
  },
];
")

(defun treesit-mark-test-pick (needle)
  "Select the node labelled at the first match of NEEDLE and return its text."
  (cl-letf (((symbol-function 'avy-process)
             (lambda (positions)
               (funcall avy-action
                        (save-excursion
                          (goto-char (point-min))
                          (search-forward needle)
                          (let ((position (match-beginning 0)))
                            (should (memq position positions))
                            position))))))
    (treesit-mark-node))
  (buffer-substring-no-properties (region-beginning) (region-end)))

(defmacro treesit-mark-test-with-source (&rest body)
  "Run BODY in a displayed TypeScript buffer."
  `(with-temp-buffer
     (switch-to-buffer (current-buffer))
     (insert treesit-mark-test-source)
     (typescript-ts-mode)
     (goto-char (point-min))
     ,@body))

(defmacro treesit-mark-test-with-language (language source &rest body)
  "Run BODY in a displayed buffer with SOURCE parsed as LANGUAGE."
  (declare (indent 2))
  `(with-temp-buffer
     (switch-to-buffer (current-buffer))
     (insert ,source)
     (treesit-parser-create ,language)
     (goto-char (point-min))
     ,@body))

(defun treesit-mark-test-labelled-p (needle)
  "Return non-nil if the first match of NEEDLE has a label."
  (save-excursion
    (goto-char (point-min))
    (search-forward needle)
    (assq (match-beginning 0) (treesit-mark--targets))))

(ert-deftest treesit-mark-selects-definitions-whole ()
  (skip-unless (treesit-ready-p 'typescript t))
  (treesit-mark-test-with-source
   (should (equal (treesit-mark-test-pick "function empty") "function empty() {}"))
   (should (string-prefix-p "class Foo {" (treesit-mark-test-pick "class Foo")))
   (should (equal (treesit-mark-test-pick "() => 1") "() => 1"))))

(ert-deftest treesit-mark-selects-conditions-whole ()
  (skip-unless (treesit-ready-p 'typescript t))
  (treesit-mark-test-with-source
   (should (equal (treesit-mark-test-pick "if (x)") "if (x) {\n    a = 3;\n    return 2;\n  }"))))

(ert-deftest treesit-mark-selects-top-level-calls-whole ()
  (skip-unless (treesit-ready-p 'typescript t))
  (treesit-mark-test-with-source
   (should (equal (treesit-mark-test-pick "watch(") "watch(a, () => {\n  log(1);\n});"))))

(ert-deftest treesit-mark-selects-top-level-declarations-whole ()
  (skip-unless (treesit-ready-p 'typescript t))
  (treesit-mark-test-with-source
   (should (string-prefix-p "const tab = make({" (treesit-mark-test-pick "const tab")))
   (should (string-suffix-p "});" (treesit-mark-test-pick "const tab")))))

(ert-deftest treesit-mark-selects-nested-callback-calls-whole ()
  (skip-unless (treesit-ready-p 'typescript t))
  (treesit-mark-test-with-source
   (should (equal (treesit-mark-test-pick "onMounted(")
                  "onMounted(() => {\n      log(2);\n    });"))))

(ert-deftest treesit-mark-selects-nested-calls-whole ()
  (skip-unless (treesit-ready-p 'typescript t))
  (treesit-mark-test-with-source
   (should (equal (treesit-mark-test-pick "log(1)") "log(1);"))))

(ert-deftest treesit-mark-skips-nested-assignments ()
  (skip-unless (treesit-ready-p 'typescript t))
  (treesit-mark-test-with-source
   (search-forward "a = 3")
   (should-not (assq (match-beginning 0) (treesit-mark--targets)))))

(ert-deftest treesit-mark-selects-block-contents ()
  (skip-unless (treesit-ready-p 'typescript t))
  (treesit-mark-test-with-source
   (should (equal (treesit-mark-test-pick "{\n    a = 3") "a = 3;\n    return 2;"))
   (should (equal (treesit-mark-test-pick "{}") "{}"))))

(ert-deftest treesit-mark-selects-object-contents-in-array ()
  (skip-unless (treesit-ready-p 'typescript t))
  (treesit-mark-test-with-source
   (should (equal (treesit-mark-test-pick "{\n    name") "name: \"x\","))))

(ert-deftest treesit-mark-uses-the-select-function ()
  (skip-unless (treesit-ready-p 'typescript t))
  (treesit-mark-test-with-source
   (let* (selected
          (treesit-mark-select-function
           (lambda (beg end)
             (setq selected (buffer-substring-no-properties beg end))
             (treesit-mark-select-region beg end))))
     (treesit-mark-test-pick "function empty")
     (should (equal selected "function empty() {}")))))

(ert-deftest treesit-mark-uses-fallback-rules-for-unknown-languages ()
  (should (eq (treesit-mark--rules 'unknown-language)
              (alist-get t treesit-mark-language-rules))))

(ert-deftest treesit-mark-selects-python-calls-and-dictionaries ()
  (skip-unless (treesit-ready-p 'python t))
  (treesit-mark-test-with-language 'python
      "def f(x):\n    print(x)\n    x = {\"a\": 1}\n"
    (should (equal (treesit-mark-test-pick "print(") "print(x)"))
    (should (equal (treesit-mark-test-pick "{") "\"a\": 1"))
    (should-not (treesit-mark-test-labelled-p "x = {"))))

(ert-deftest treesit-mark-selects-bare-lua-calls ()
  (skip-unless (treesit-ready-p 'lua t))
  (treesit-mark-test-with-language 'lua
      "function f(x)\n  log(x)\n  local y = g(1)\nend\n"
    (should (equal (treesit-mark-test-pick "log(") "log(x)"))
    (should-not (treesit-mark-test-labelled-p "g(1)"))))

(ert-deftest treesit-mark-selects-bare-ruby-calls ()
  (skip-unless (treesit-ready-p 'ruby t))
  (treesit-mark-test-with-language 'ruby
      "def f(x)\n  if x\n    log(1)\n  else\n    log(2)\n  end\n  while x\n    log(3)\n  end\n  begin\n    log(4)\n  ensure\n    log(5)\n  end\n  y = g(1)\nend\n"
    (dolist (call '("log(1)" "log(2)" "log(3)" "log(4)" "log(5)"))
      (should (equal (treesit-mark-test-pick call) call)))
    (should-not (treesit-mark-test-labelled-p "g(1)"))))

(ert-deftest treesit-mark-selects-constructor-statements ()
  (skip-unless (treesit-ready-p 'typescript t))
  (treesit-mark-test-with-language 'typescript
      "function f() {\n  new Foo();\n}\n"
    (should (equal (treesit-mark-test-pick "new Foo") "new Foo();"))))

(ert-deftest treesit-mark-selects-rust-macro-calls ()
  (skip-unless (treesit-ready-p 'rust t))
  (treesit-mark-test-with-language 'rust
      "fn f() {\n    println!(\"{}\", 1);\n}\n"
    (should (equal (treesit-mark-test-pick "println!") "println!(\"{}\", 1);"))))

(provide 'treesit-mark-test)
;;; treesit-mark-test.el ends here
