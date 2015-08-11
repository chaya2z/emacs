;;; elisp-mode-tests.el --- Tests for emacs-lisp-mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2015 Free Software Foundation, Inc.

;; Author: Dmitry Gutov <dgutov@yandex.ru>
;; Author: Stephen Leake <stephen_leake@member.fsf.org>

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Code:

(require 'ert)
(require 'xref)

;;; Completion

(defun elisp--test-completions ()
  (let ((data (elisp-completion-at-point)))
    (all-completions (buffer-substring (nth 0 data) (nth 1 data))
                     (nth 2 data)
                     (plist-get (nthcdr 3 data) :predicate))))

(ert-deftest elisp-completes-functions ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "(ba")
    (let ((comps (elisp--test-completions)))
      (should (member "backup-buffer" comps))
      (should-not (member "backup-inhibited" comps)))))

(ert-deftest elisp-completes-variables ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "(foo ba")
    (let ((comps (elisp--test-completions)))
      (should (member "backup-inhibited" comps))
      (should-not (member "backup-buffer" comps)))))

(ert-deftest elisp-completes-anything-quoted ()
  (dolist (text '("`(foo ba" "(foo 'ba"
                  "`(,foo ba" "`,(foo `ba"
                  "'(foo (ba"))
    (with-temp-buffer
      (emacs-lisp-mode)
      (insert text)
      (let ((comps (elisp--test-completions)))
        (should (member "backup-inhibited" comps))
        (should (member "backup-buffer" comps))
        (should (member "backup" comps))))))

(ert-deftest elisp-completes-variables-unquoted ()
  (dolist (text '("`(foo ,ba" "`(,(foo ba" "`(,ba"))
    (with-temp-buffer
      (emacs-lisp-mode)
      (insert text)
      (let ((comps (elisp--test-completions)))
        (should (member "backup-inhibited" comps))
        (should-not (member "backup-buffer" comps))))))

(ert-deftest elisp-completes-functions-in-special-macros ()
  (dolist (text '("(declare-function ba" "(cl-callf2 ba"))
    (with-temp-buffer
      (emacs-lisp-mode)
      (insert text)
      (let ((comps (elisp--test-completions)))
        (should (member "backup-buffer" comps))
        (should-not (member "backup-inhibited" comps))))))

(ert-deftest elisp-completes-functions-after-hash-quote ()
  (ert-deftest elisp-completes-functions-after-let-bindings ()
    (with-temp-buffer
      (emacs-lisp-mode)
      (insert "#'ba")
      (let ((comps (elisp--test-completions)))
        (should (member "backup-buffer" comps))
        (should-not (member "backup-inhibited" comps))))))

(ert-deftest elisp-completes-local-variables ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "(let ((bar 1) baz) (foo ba")
    (let ((comps (elisp--test-completions)))
      (should (member "backup-inhibited" comps))
      (should (member "bar" comps))
      (should (member "baz" comps)))))

(ert-deftest elisp-completest-variables-in-let-bindings ()
  (dolist (text '("(let (ba" "(let* ((ba"))
    (with-temp-buffer
      (emacs-lisp-mode)
      (insert text)
      (let ((comps (elisp--test-completions)))
        (should (member "backup-inhibited" comps))
        (should-not (member "backup-buffer" comps))))))

(ert-deftest elisp-completes-functions-after-let-bindings ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "(let ((bar 1) (baz 2)) (ba")
    (let ((comps (elisp--test-completions)))
      (should (member "backup-buffer" comps))
      (should-not (member "backup-inhibited" comps)))))

;;; xref

(defun xref-elisp-test-descr-to-target (xref)
  "Return an appropiate `looking-at' match string for XREF."
  (let* ((loc (xref-item-location xref))
	 (type (or (xref-elisp-location-type loc)
		  'defun)))

    (cl-case type
      (defalias
       ;; summary: "(defalias xref)"
       ;; target : "(defalias 'xref)"
       (concat "(defalias '" (substring (xref-item-summary xref) 10 -1)))

      (defun
       (let ((summary (xref-item-summary xref))
	     (file (xref-elisp-location-file loc)))
	 (cond
	  ((string= "c" (file-name-extension file))
	   ;; summary: "(defun buffer-live-p)"
	   ;; target : "DEFUN (buffer-live-p"
	   (concat
	    (upcase (substring summary 1 6))
	    " (\""
	    (substring summary 7 -1)
	    "\""))

	  (t
	   (substring summary 0 -1))
	  )))

      (defvar
       (let ((summary (xref-item-summary xref))
	     (file (xref-elisp-location-file loc)))
	 (cond
	  ((string= "c" (file-name-extension file))
	   ;; summary: "(defvar system-name)"
	   ;; target : "DEFVAR_LISP ("system-name", "
           ;; summary: "(defvar abbrev-mode)"
           ;; target : DEFVAR_PER_BUFFER ("abbrev-mode"
	   (concat
	    (upcase (substring summary 1 7))
            (if (bufferp (variable-binding-locus (xref-elisp-location-symbol loc)))
                "_PER_BUFFER (\""
              "_LISP (\"")
	    (substring summary 8 -1)
	    "\""))

	  (t
	   (substring summary 0 -1))
	  )))

      (feature
       ;; summary: "(feature xref)"
       ;; target : "(provide 'xref)"
       (concat "(provide '" (substring (xref-item-summary xref) 9 -1)))

      (otherwise
       (substring (xref-item-summary xref) 0 -1))
      )))


(defmacro xref-elisp-test (name computed-xrefs expected-xrefs)
  "Define an ert test for an xref-elisp feature.
COMPUTED-XREFS and EXPECTED-XREFS are lists of xrefs, except if
an element of EXPECTED-XREFS is a cons (XREF . TARGET), TARGET is
matched to the found location; otherwise, match
to (xref-elisp-test-descr-to-target xref)."
  (declare (indent defun))
  (declare (debug (symbolp "name")))
  `(ert-deftest ,(intern (concat "xref-elisp-test-" (symbol-name name))) ()
     (let ((xrefs ,computed-xrefs)
           (expecteds ,expected-xrefs))
       (while xrefs
         (let ((xref (pop xrefs))
               (expected (pop expecteds)))

           (should (equal xref
                          (or (when (consp expected) (car expected)) expected)))

           (xref--goto-location (xref-item-location xref))
           (should (looking-at (or (when (consp expected) (cdr expected))
                                   (xref-elisp-test-descr-to-target expected)))))
         ))
     ))

;; When tests are run from the Makefile, 'default-directory' is $HOME,
;; so we must provide this dir to expand-file-name in the expected
;; results. The Makefile sets EMACS_TEST_DIRECTORY.
(defconst emacs-test-dir (getenv "EMACS_TEST_DIRECTORY"))

;; alphabetical by test name

;; FIXME: autoload

;; FIXME: defalias-defun-c cmpl-prefix-entry-head
;; FIXME: defalias-defvar-el allout-mode-map

(xref-elisp-test find-defs-defalias-defun-el
  (elisp--xref-find-definitions 'Buffer-menu-sort)
  (list
   (xref-make "(defalias Buffer-menu-sort)"
	      (xref-make-elisp-location
	       'Buffer-menu-sort 'defalias
	       (expand-file-name "../../lisp/buff-menu.elc" emacs-test-dir)))
   (xref-make "(defun tabulated-list-sort)"
	      (xref-make-elisp-location
	       'tabulated-list-sort nil
	       (expand-file-name "../../lisp/emacs-lisp/tabulated-list.el" emacs-test-dir)))
   ))

;; FIXME: defconst

(xref-elisp-test find-defs-defgeneric-el
  (elisp--xref-find-definitions 'xref-location-marker)
  (list
   (xref-make "(cl-defgeneric xref-location-marker)"
	      (xref-make-elisp-location
	       'xref-location-marker nil
	       (expand-file-name "../../lisp/progmodes/xref.el" emacs-test-dir)))
   (xref-make "(cl-defmethod xref-location-marker ((l xref-elisp-location)))"
	      (xref-make-elisp-location
	       '(xref-location-marker xref-elisp-location) 'cl-defmethod
	       (expand-file-name "../../lisp/progmodes/elisp-mode.el" emacs-test-dir)))
   (xref-make "(cl-defmethod xref-location-marker ((l xref-file-location)))"
	      (xref-make-elisp-location
	       '(xref-location-marker xref-file-location) 'cl-defmethod
	       (expand-file-name "../../lisp/progmodes/xref.el" emacs-test-dir)))
   (xref-make "(cl-defmethod xref-location-marker ((l xref-buffer-location)))"
	      (xref-make-elisp-location
	       '(xref-location-marker xref-buffer-location) 'cl-defmethod
	       (expand-file-name "../../lisp/progmodes/xref.el" emacs-test-dir)))
   (xref-make "(cl-defmethod xref-location-marker ((l xref-bogus-location)))"
	      (xref-make-elisp-location
	       '(xref-location-marker xref-bogus-location) 'cl-defmethod
	       (expand-file-name "../../lisp/progmodes/xref.el" emacs-test-dir)))
   (xref-make "(cl-defmethod xref-location-marker ((l xref-etags-location)))"
	      (xref-make-elisp-location
	       '(xref-location-marker xref-etags-location) 'cl-defmethod
	       (expand-file-name "../../lisp/progmodes/etags.el" emacs-test-dir)))
   ))

;; FIXME: constructor xref-make-elisp-location; location is
;; cl-defstruct location. use :constructor in description.

(xref-elisp-test find-defs-defgeneric-eval
  (elisp--xref-find-definitions (eval '(cl-defgeneric stephe-leake-cl-defgeneric ())))
  nil)

(xref-elisp-test find-defs-defun-el
  (elisp--xref-find-definitions 'xref-find-definitions)
  (list
   (xref-make "(defun xref-find-definitions)"
	      (xref-make-elisp-location
	       'xref-find-definitions nil
	       (expand-file-name "../../lisp/progmodes/xref.el" emacs-test-dir)))))

(xref-elisp-test find-defs-defun-eval
  (elisp--xref-find-definitions (eval '(defun stephe-leake-defun ())))
  nil)

(xref-elisp-test find-defs-defun-c
  (elisp--xref-find-definitions 'buffer-live-p)
  (list
   (xref-make "(defun buffer-live-p)"
	      (xref-make-elisp-location 'buffer-live-p nil "src/buffer.c"))))

;; FIXME: deftype

(xref-elisp-test find-defs-defun-c-defvar-c
  (elisp-xref-find 'definitions "system-name")
  (list
   (xref-make "(defvar system-name)"
	      (xref-make-elisp-location 'system-name 'defvar "src/editfns.c"))
   (xref-make "(defun system-name)"
              (xref-make-elisp-location 'system-name nil "src/editfns.c")))
  )

(xref-elisp-test find-defs-defun-el-defvar-c
  (elisp-xref-find 'definitions "abbrev-mode")
  ;; It's a minor mode, but the variable is defined in buffer.c
  (list
   (xref-make "(defvar abbrev-mode)"
	      (xref-make-elisp-location 'abbrev-mode 'defvar "src/buffer.c"))
   (cons
    (xref-make "(defun abbrev-mode)"
               (xref-make-elisp-location
                'abbrev-mode nil
                (expand-file-name "../../lisp/abbrev.el" emacs-test-dir)))
    "(define-minor-mode abbrev-mode"))
  )

;; Source for both variable and defun is "(define-minor-mode
;; compilation-minor-mode". There is no way to tell that from the
;; symbol.  find-function-regexp-alist uses find-function-regexp for
;; this, but that matches too many things for use in this test.
(xref-elisp-test find-defs-defun-defvar-el
  (elisp--xref-find-definitions 'compilation-minor-mode)
  (list
   (cons
    (xref-make "(defun compilation-minor-mode)"
               (xref-make-elisp-location
                'compilation-minor-mode nil
                (expand-file-name "../../lisp/progmodes/compile.el" emacs-test-dir)))
    "(define-minor-mode compilation-minor-mode")
   (cons
    (xref-make "(defvar compilation-minor-mode)"
	      (xref-make-elisp-location
	       'compilation-minor-mode 'defvar
	       (expand-file-name "../../lisp/progmodes/compile.el" emacs-test-dir)))
    "(define-minor-mode compilation-minor-mode")
   )
  )

(xref-elisp-test find-defs-defvar-el
  (elisp--xref-find-definitions 'xref--marker-ring)
  ;; This is a defconst, which creates an alias and a variable.
  ;; FIXME: try not to show the alias in this case
  (list
   (xref-make "(defvar xref--marker-ring)"
	      (xref-make-elisp-location
	       'xref--marker-ring 'defvar
	       (expand-file-name "../../lisp/progmodes/xref.el" emacs-test-dir)))
   (cons
    (xref-make "(defalias xref--marker-ring)"
               (xref-make-elisp-location
                'xref--marker-ring 'defalias
                (expand-file-name "../../lisp/progmodes/xref.elc" emacs-test-dir)))
    "(defvar xref--marker-ring")
    ))

(xref-elisp-test find-defs-defvar-c
  (elisp--xref-find-definitions 'default-directory)
  (list
   (cons
    (xref-make "(defvar default-directory)"
               (xref-make-elisp-location 'default-directory 'defvar "src/buffer.c"))
    ;; IMPROVEME: we might be able to compute this target
    "DEFVAR_PER_BUFFER (\"default-directory\"")))

(xref-elisp-test find-defs-defvar-eval
  (elisp--xref-find-definitions (eval '(defvar stephe-leake-defvar nil)))
  nil)

(xref-elisp-test find-defs-face-el
  (elisp--xref-find-definitions 'font-lock-keyword-face)
  ;; 'font-lock-keyword-face is both a face and a var
  ;; defface creates both a face and an alias
  ;; FIXME: try to not show the alias in this case
  (list
   (xref-make "(defvar font-lock-keyword-face)"
	      (xref-make-elisp-location
	       'font-lock-keyword-face 'defvar
	       (expand-file-name "../../lisp/font-lock.el" emacs-test-dir)))
   (xref-make "(defface font-lock-keyword-face)"
	      (xref-make-elisp-location
	       'font-lock-keyword-face 'defface
	       (expand-file-name "../../lisp/font-lock.el" emacs-test-dir)))
   (cons
    (xref-make "(defalias font-lock-keyword-face)"
	      (xref-make-elisp-location
	       'font-lock-keyword-face 'defalias
	       (expand-file-name "../../lisp/font-lock.elc" emacs-test-dir)))
    "(defface font-lock-keyword-face")
   ))

(xref-elisp-test find-defs-face-eval
  (elisp--xref-find-definitions (eval '(defface stephe-leake-defface nil "")))
  nil)

(xref-elisp-test find-defs-feature-el
  (elisp--xref-find-definitions 'xref)
  (list
   (xref-make "(feature xref)"
	      (xref-make-elisp-location
	       'xref 'feature
	       (expand-file-name "../../lisp/progmodes/xref.el" emacs-test-dir)))))

(xref-elisp-test find-defs-feature-eval
  (elisp--xref-find-definitions (eval '(provide 'stephe-leake-feature)))
  nil)

(provide 'elisp-mode-tests)
;;; elisp-mode-tests.el ends here
