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

(ert-deftest treesit-mark-selects-definitions-whole ()
  (skip-unless (treesit-ready-p 'typescript t))
  (treesit-mark-test-with-source
   (should (equal (treesit-mark-test-pick "function empty") "function empty() {}"))
   (should (string-prefix-p "class Foo {" (treesit-mark-test-pick "class Foo")))
   (should (equal (treesit-mark-test-pick "() => 1") "() => 1"))))

(ert-deftest treesit-mark-selects-conditions-whole ()
  (skip-unless (treesit-ready-p 'typescript t))
  (treesit-mark-test-with-source
   (should (equal (treesit-mark-test-pick "if (x)") "if (x) {\n    return 2;\n  }"))))

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

(ert-deftest treesit-mark-skips-nested-calls ()
  (skip-unless (treesit-ready-p 'typescript t))
  (treesit-mark-test-with-source
   (search-forward "log(1)")
   (should-not (assq (match-beginning 0) (treesit-mark--targets)))))

(ert-deftest treesit-mark-selects-block-contents ()
  (skip-unless (treesit-ready-p 'typescript t))
  (treesit-mark-test-with-source
   (should (equal (treesit-mark-test-pick "{\n    return 2") "return 2;"))
   (should (equal (treesit-mark-test-pick "{}") "{}"))))

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

(provide 'treesit-mark-test)
;;; treesit-mark-test.el ends here
